#!/bin/sh
set -e

# Update environment for Wayland
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=wlroots

# Set wallpaper
swaybg -i ~/.config/mango/wallpapers/default.jpg &

# Launch notification daemon
mako &

# Start Waybar with the provided configuration
waybar -c ~/.config/mango/waybar/config -s ~/.config/mango/waybar/style.css &
