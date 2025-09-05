#!/bin/sh
# Start Waybar with the provided configuration
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots
waybar -c ~/.config/mango/waybar/config -s ~/.config/mango/waybar/style.css &
