#!/usr/bin/env bash

# rice-plan.sh - provision minimal rice setup
#
# Usage:
#   scripts/rice-plan.sh [OPTIONS]
#
# Options:
#   --fonts             Install a Nerd Font (JetBrainsMono)
#   --config            Copy local mangowc-config into ~/.config/mangowc
#   --css               Apply pywal CSS variables to the mangowc style
#   --wallpaper URL     Download wallpaper to ~/Pictures/wallpapers
#   --pywal FILE        Run pywal for automatic color extraction
#   -h, --help          Show this help message
#
# With no options, --fonts, --config and --css run.  If --wallpaper is
# supplied, the downloaded image becomes the target for --pywal unless
# an explicit FILE is passed to --pywal.

set -euo pipefail

usage() {
  awk 'NR==1{next} /^#/{sub(/^# ?/, ""); print; next} /^$/{print; next} {exit}' "$0"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

install_nerd_fonts() {
  local font_dir="$HOME/.local/share/fonts"
  mkdir -p "$font_dir"
  local url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
  local tmp_zip
  tmp_zip="$(mktemp)"
  echo "Downloading JetBrainsMono Nerd Font..."
  curl -fsSL "$url" -o "$tmp_zip"
  unzip -o "$tmp_zip" -d "$font_dir" >/dev/null
  rm "$tmp_zip"
  fc-cache -fv "$font_dir" >/dev/null
  echo "Nerd Font installed to $font_dir"
}

copy_mangowc_config() {
  local src="$REPO_ROOT/mangowc-config"
  local dest="$HOME/.config/mangowc"
  mkdir -p "$dest"
  cp -r "$src"/* "$dest"/
  echo "mangowc configuration copied to $dest"
}

apply_css_variables() {
  local css_dest="$HOME/.config/mangowc/style.css"
  local wal_css="$HOME/.cache/wal/colors.css"
  local start_marker="/* wal-start */"
  local end_marker="/* wal-end */"
  if [[ -f "$wal_css" ]]; then
    mkdir -p "$(dirname "$css_dest")"
    local wal_block
    wal_block=$(printf '%s\n' "$start_marker"; cat "$wal_css"; printf '%s\n' "$end_marker")
    if [[ -f "$css_dest" ]]; then
      sed -e '/\/\* wal-start \*\//,/\/\* wal-end \*\//d' "$css_dest" > "${css_dest}.tmp"
      mv "${css_dest}.tmp" "$css_dest"
    fi
    printf '%s\n' "$wal_block" >> "$css_dest"
    echo "Applied pywal CSS variables to $css_dest"
  else
    echo "No pywal colors.css found at $wal_css; skipping"
  fi
}

download_wallpapers() {
  local url="$1"
  local dest_dir="$HOME/Pictures/wallpapers"
  mkdir -p "$dest_dir"
  local file
  file="$dest_dir/$(basename "$url")"
  echo "Downloading wallpaper from $url..."
  curl -fsSL "$url" -o "$file"
  echo "$file"
}

run_pywal() {
  local img="$1"
  if command -v wal >/dev/null 2>&1; then
    wal -i "$img"
  else
    echo "pywal not installed; skipping color extraction" >&2
  fi
}

main() {
  local do_fonts=false do_config=false do_css=false wallpaper_url="" pywal_img=""
  if [[ $# -eq 0 ]]; then
    do_fonts=true; do_config=true; do_css=true
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --fonts) do_fonts=true ;;
      --config) do_config=true ;;
      --css) do_css=true ;;
      --wallpaper) wallpaper_url="$2"; shift ;;
      --pywal) pywal_img="$2"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
  done

  [[ "$do_fonts" == true ]] && install_nerd_fonts
  [[ "$do_config" == true ]] && copy_mangowc_config
  [[ "$do_css" == true ]] && apply_css_variables

  local downloaded=""
  if [[ -n "$wallpaper_url" ]]; then
    downloaded=$(download_wallpapers "$wallpaper_url")
  fi

  if [[ -z "$pywal_img" && -n "$downloaded" ]]; then
    pywal_img="$downloaded"
  fi
  [[ -n "$pywal_img" ]] && run_pywal "$pywal_img"
}

main "$@"

