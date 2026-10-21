//! A small C ABI around `railway-api`, so the SwiftUI app can reuse the exact same
//! provider implementations (HAFAS profiles, search.ch, Transitous, DB) as Railway.
//!
//! Every call takes JSON and answers through a callback with a JSON envelope; see
//! `include/railway_bridge.h`.

use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char, c_void};
use std::str::FromStr;
use std::sync::Mutex;
use std::time::Duration;

use chrono::{DateTime, Utc};
use chrono_tz::Tz;
use once_cell::sync::Lazy;
use rcore::{
    JourneysOptions, LocationsOptions, LoyaltyCard, Mode, Provider, ProductsSelection,
    RefreshJourneyOptions, TariffClass, TransferOptions,
};
use serde::{Deserialize, Serialize};

/// Requests are aborted after this many seconds, mirroring Railway.
const TIMEOUT: Duration = Duration::from_secs(30);

type Callback = extern "C" fn(context: *mut c_void, json: *const c_char);

static RUNTIME: Lazy<tokio::runtime::Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .thread_name("railway-bridge")
        .build()
        .expect("Failed to start tokio runtime")
});

/// Constructed providers, keyed by their canonical name, so connections are reused.
static PROVIDERS: Lazy<Mutex<HashMap<String, rapi::RailwayProvider>>> = Lazy::new(Default::default);

/// `*mut c_void` is not `Send`; the Swift side guarantees the context may be used from any thread.
struct Context(*mut c_void);
unsafe impl Send for Context {}

#[derive(Serialize)]
#[serde(rename_all = "snake_case")]
enum ErrorKind {
    /// The network request failed (offline, DNS, TLS, ...).
    Request,
    /// The provider answered with an error or something unparsable.
    Provider,
    NotImplemented,
    Timeout,
    /// The request could not be understood by the bridge (a bug in the app).
    InvalidRequest,
}

#[derive(Serialize)]
struct BridgeError {
    kind: ErrorKind,
    message: String,
}

impl BridgeError {
    fn new(kind: ErrorKind, message: impl ToString) -> Self {
        Self {
            kind,
            message: message.to_string(),
        }
    }
}

impl<R: std::error::Error, P: std::error::Error> From<rcore::Error<R, P>> for BridgeError {
    fn from(e: rcore::Error<R, P>) -> Self {
        match e {
            rcore::Error::Request(e) => Self::new(ErrorKind::Request, e),
            rcore::Error::Provider(e) => Self::new(ErrorKind::Provider, e),
            rcore::Error::NotImplemented => Self::new(
                ErrorKind::NotImplemented,
                "Not implemented by this provider",
            ),
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "snake_case")]
enum Envelope<T: Serialize> {
    Ok(T),
    Error(BridgeError),
}

fn provider(name: &str) -> Result<rapi::RailwayProvider, BridgeError> {
    let kind = rapi::RailwayProviderType::from_str(name)
        .map_err(|_| BridgeError::new(ErrorKind::InvalidRequest, format!("Unknown provider {name}")))?;
    let mut providers = PROVIDERS.lock().expect("Provider cache poisoned");
    Ok(providers
        .entry(kind.to_string())
        .or_insert_with(|| rapi::RailwayProvider::new(kind, rcore::ReqwestRequesterBuilder::default()))
        .clone())
}

/// Parses the arguments, runs `f` on the runtime and reports the outcome to `callback`.
fn dispatch<Req, Res, F, Fut>(
    provider_name: *const c_char,
    request_json: *const c_char,
    context: *mut c_void,
    callback: Callback,
    f: F,
) where
    Req: for<'de> Deserialize<'de> + Send + 'static,
    Res: Serialize,
    F: FnOnce(rapi::RailwayProvider, Req) -> Fut + Send + 'static,
    Fut: Future<Output = Result<Res, BridgeError>> + Send + 'static,
{
    let context = Context(context);
    let parsed = (|| {
        let name = unsafe { CStr::from_ptr(provider_name) }
            .to_str()
            .map_err(|e| BridgeError::new(ErrorKind::InvalidRequest, e))?;
        let json = unsafe { CStr::from_ptr(request_json) }
            .to_str()
            .map_err(|e| BridgeError::new(ErrorKind::InvalidRequest, e))?;
        let request: Req = serde_json::from_str(json)
            .map_err(|e| BridgeError::new(ErrorKind::InvalidRequest, e))?;
        Ok::<_, BridgeError>((provider(name)?, request))
    })();

    let (client, request) = match parsed {
        Ok(v) => v,
        Err(e) => {
            respond::<Res>(context, callback, Err(e));
            return;
        }
    };

    RUNTIME.spawn(async move {
        let result = tokio::time::timeout(TIMEOUT, f(client, request))
            .await
            .unwrap_or_else(|_| Err(BridgeError::new(ErrorKind::Timeout, "Timed out")));
        respond(context, callback, result);
    });
}

fn respond<T: Serialize>(context: Context, callback: Callback, result: Result<T, BridgeError>) {
    let envelope = match result {
        Ok(v) => Envelope::Ok(v),
        Err(e) => Envelope::Error(e),
    };
    let json = serde_json::to_string(&envelope).unwrap_or_else(|e| {
        format!(r#"{{"error":{{"kind":"provider","message":{}}}}}"#, serde_json::Value::from(e.to_string()))
    });
    let json = CString::new(json).unwrap_or_default();
    callback(context.0, json.as_ptr());
}

fn utc(timestamp: Option<i64>) -> Option<DateTime<Tz>> {
    timestamp
        .and_then(|t| DateTime::<Utc>::from_timestamp(t, 0))
        .map(|t| t.with_timezone(&Tz::UTC))
}

// --- Providers ---------------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn rw_providers() -> *mut c_char {
    let names: Vec<String> = rapi::RailwayProviderType::variants()
        .iter()
        .map(ToString::to_string)
        .collect();
    CString::new(serde_json::to_string(&names).unwrap_or_default())
        .unwrap_or_default()
        .into_raw()
}

/// # Safety
/// `string` must have been returned by this library and not been freed before.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rw_string_free(string: *mut c_char) {
    if !string.is_null() {
        drop(unsafe { CString::from_raw(string) });
    }
}

// --- Locations ---------------------------------------------------------------------------------

#[derive(Deserialize)]
struct LocationsRequest {
    query: String,
    results: Option<u64>,
    language: Option<String>,
}

#[unsafe(no_mangle)]
pub extern "C" fn rw_locations(
    provider: *const c_char,
    request_json: *const c_char,
    context: *mut c_void,
    callback: Callback,
) {
    dispatch(provider, request_json, context, callback, |client, r: LocationsRequest| async move {
        let opts = LocationsOptions {
            query: r.query,
            results: r.results.unwrap_or(10),
            language: r.language,
        };
        client.locations(opts).await.map_err(BridgeError::from)
    });
}

// --- Journeys ----------------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum TimeType {
    Departure,
    Arrival,
}

#[derive(Deserialize)]
struct JourneysRequest {
    from: rcore::Place,
    to: rcore::Place,
    /// Unix timestamp of the requested departure/arrival.
    time: Option<i64>,
    time_type: TimeType,
    earlier_than: Option<String>,
    later_than: Option<String>,
    language: Option<String>,
    #[serde(default)]
    first_class: bool,
    /// Loyalty card id as used by Railway's settings (0 = none).
    #[serde(default)]
    loyalty_card: u8,
    #[serde(default)]
    bike_friendly: bool,
    #[serde(default)]
    direct_only: bool,
    #[serde(default)]
    transfer_time_minutes: i64,
    /// Allowed modes; `None` means all of them.
    products: Option<Vec<Mode>>,
}

#[derive(Serialize)]
struct JourneysResponse {
    earlier_ref: Option<String>,
    later_ref: Option<String>,
    journeys: Vec<rcore::Journey>,
}

#[unsafe(no_mangle)]
pub extern "C" fn rw_journeys(
    provider: *const c_char,
    request_json: *const c_char,
    context: *mut c_void,
    callback: Callback,
) {
    dispatch(provider, request_json, context, callback, |client, r: JourneysRequest| async move {
        let time = utc(r.time);
        let opts = JourneysOptions {
            earlier_than: r.earlier_than,
            later_than: r.later_than,
            departure: matches!(r.time_type, TimeType::Departure).then_some(time).flatten(),
            arrival: matches!(r.time_type, TimeType::Arrival).then_some(time).flatten(),
            language: r.language,
            stopovers: true,
            loyalty_card: LoyaltyCard::from_id(r.loyalty_card),
            bike_friendly: r.bike_friendly,
            transfers: if r.direct_only {
                TransferOptions::Limited(0)
            } else {
                TransferOptions::Unlimited
            },
            transfer_time: chrono::Duration::try_minutes(r.transfer_time_minutes).unwrap_or_default(),
            tariff_class: if r.first_class {
                TariffClass::First
            } else {
                TariffClass::Second
            },
            products: r
                .products
                .map(|p| ProductsSelection::from(p.into_iter().collect::<std::collections::HashSet<_>>()))
                .unwrap_or_default(),
            ..Default::default()
        };
        let response = client.journeys(r.from, r.to, opts).await?;
        Ok(JourneysResponse {
            earlier_ref: response.earlier_ref,
            later_ref: response.later_ref,
            journeys: response.journeys,
        })
    });
}

// --- Refresh -----------------------------------------------------------------------------------

#[derive(Deserialize)]
struct RefreshRequest {
    journey: rcore::Journey,
    language: Option<String>,
}

#[unsafe(no_mangle)]
pub extern "C" fn rw_refresh_journey(
    provider: *const c_char,
    request_json: *const c_char,
    context: *mut c_void,
    callback: Callback,
) {
    dispatch(provider, request_json, context, callback, |client, r: RefreshRequest| async move {
        let opts = RefreshJourneyOptions {
            stopovers: true,
            language: r.language,
            ..Default::default()
        };
        client
            .refresh_journey(&r.journey, opts)
            .await
            .map_err(BridgeError::from)
    });
}
