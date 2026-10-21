# dmgbuild settings for the Railway disk image, used by make-dmg.sh.
# Icon positions are in points from the window's top-left and must match make-dmg-background.swift.
import os

app = defines["app"]
app_name = os.path.basename(app)

format = "UDZO"
compression_level = 9
filesystem = "HFS+"
size = None

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [app_name]
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")

background = defines["background"]
# Origin is measured from the bottom of the screen; the size includes the title and status bars.
window_rect = ((300, 500), (640, 458))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {
    app_name: (180, 190),
    "Applications": (460, 190),
}
