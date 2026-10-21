// C interface of the Railway backend bridge (see RailwayBridge/src/lib.rs).
//
// All requests and responses are UTF-8 JSON. Each asynchronous call returns
// immediately and later invokes `callback` exactly once, on a background
// thread, with a JSON envelope of the form
//
//     {"ok": <result>}  or  {"error": {"kind": "...", "message": "..."}}
//
// The string passed to the callback is only valid for the duration of the
// callback; copy it if needed.

#ifndef RAILWAY_BRIDGE_H
#define RAILWAY_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*rw_callback)(void *_Nullable context, const char *_Nonnull json);

/// JSON array of all provider identifiers compiled into the bridge.
/// Free the result with `rw_string_free`.
char *_Nonnull rw_providers(void);

/// Free a string returned by the bridge.
void rw_string_free(char *_Nullable string);

/// Autocomplete places. Request: `{"query": String, "results"?: u64, "language"?: String}`.
void rw_locations(const char *_Nonnull provider,
                  const char *_Nonnull request_json,
                  void *_Nullable context,
                  rw_callback _Nonnull callback);

/// Search journeys. See `JourneysRequest` in lib.rs for the request shape.
void rw_journeys(const char *_Nonnull provider,
                 const char *_Nonnull request_json,
                 void *_Nullable context,
                 rw_callback _Nonnull callback);

/// Refresh a journey. Request: `{"journey": Journey, "language"?: String}`.
void rw_refresh_journey(const char *_Nonnull provider,
                        const char *_Nonnull request_json,
                        void *_Nullable context,
                        rw_callback _Nonnull callback);

#ifdef __cplusplus
}
#endif

#endif
