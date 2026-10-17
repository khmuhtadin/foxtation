# dmgbuild settings for the installer window: the app on the left, Applications
# on the right, and a background that says to drag one onto the other.
# scripts/make-dmg.sh runs: uvx --from dmgbuild==1.6.5 dmgbuild -s packaging/dmg/settings.py …

format = "UDZO"
files = ["dist/Foxtation.app"]
symlinks = {"Applications": "/Applications"}
icon = "Resources/AppIcon.icns"  # the mounted volume's icon

background = "packaging/dmg/background.png"  # with background@2x.png beside it for Retina
window_rect = ((200, 160), (640, 428))  # 400 of background plus the title bar
icon_size = 112
text_size = 13
icon_locations = {"Foxtation.app": (170, 230), "Applications": (470, 230)}

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
