# mangowc Nord "Polar Night" example

This directory contains a basic mangowc setup styled with the Nord "Polar Night" palette.

## Usage

Copy the contents to `~/.config/mango` and make the autostart script executable:

```bash
mkdir -p ~/.config/mango
cp -r mangowc-config/* ~/.config/mango/
chmod +x ~/.config/mango/autostart.sh
```

Start mangowc from a TTY:

```bash
mango
```

The supplied Waybar configuration creates a vertical launcher panel on the left and a top bar with a centred clock and system tray on the right. Colours are based on the four Polar Night hues (`#2e3440`, `#3b4252`, `#434c5e`, `#4c566a`).
