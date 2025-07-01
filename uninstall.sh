#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"
source ./scriptdata/environment-variables
source ./scriptdata/functions

# Defaults
ASK=true
DRY_RUN=false
REMOVE_PACKAGES=true
REMOVE_CONFIGS=true

# Arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=true ;;
  --no-confirm) ASK=false ;;
  --only-configs) REMOVE_PACKAGES=false ;;
  --only-packages) REMOVE_CONFIGS=false ;;
  --help)
    echo "Usage: $0 [--dry-run] [--no-confirm] [--only-configs|--only-packages]"
    exit 0
    ;;
  *) echo "Unknown flag: $1" && exit 1 ;;
  esac
  shift
done

log() { echo -e "\e[36m[INFO]\e[0m $1"; }
warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
run() { $DRY_RUN && echo "[DRY-RUN] $*" || eval "$*"; }

log "Requesting sudo access..."
sudo -v
prevent_sudo_or_root

if [[ "$REMOVE_CONFIGS" == true ]]; then
  log "Removing dotfile configs (linked or copied)..."

  configs=(
    ags fish fontconfig foot fuzzel hypr mpv wlogout
    qt5ct qt6ct quickshell kitty zshrc.d starship.toml
    chrome-flags.conf code-flags.conf kdeglobals thorium-flags.conf
  )

  for c in "${configs[@]}"; do
    target="$XDG_CONFIG_HOME/$c"
    [[ -e "$target" ]] && run rm -rf "$target"
  done

  run rm -rf "$XDG_CACHE_HOME/ags"
  run sudo rm -rf "$XDG_STATE_HOME/ags"
  run rm -rf "$XDG_BIN_HOME/fuzzel-emoji"
  run rm -rf "$XDG_DATA_HOME/gradience"
  run rm -f "$XDG_DATA_HOME/glib-2.0/schemas/com.github.GradienceTeam.Gradience.Devel.gschema.xml"
fi

# Remove user groups and modules
log "Removing group and module configurations..."
user=$(whoami)
run sudo gpasswd -d "$user" video || true
run sudo gpasswd -d "$user" i2c || true
run sudo gpasswd -d "$user" input || true
run sudo rm -f /etc/modules-load.d/i2c-dev.conf

# Package uninstallation
if [[ "$REMOVE_PACKAGES" == true ]]; then
  if [[ "$ASK" == true ]]; then
    echo -e "\e[33m[WARN] This will uninstall all illogical-impulse packages.\e[0m"
    read -p "Press Enter to continue or Ctrl+C to abort"
  fi

  pkglist=(
    illogical-impulse-agsv1
    illogical-impulse-audio
    illogical-impulse-backlight
    illogical-impulse-basic
    illogical-impulse-bibata-modern-classic-bin
    illogical-impulse-fonts-themes
    illogical-impulse-gnome
    illogical-impulse-gtk
    illogical-impulse-hyprland
    illogical-impulse-microtex-git
    illogical-impulse-oneui4-icons-git
    illogical-impulse-portal
    illogical-impulse-python
    illogical-impulse-screencapture
    illogical-impulse-widgets
    plasma-browser-integration
  )

  run yay -Rns "${pkglist[@]}"
fi

log "Uninstallation complete. ✅"
$DRY_RUN && echo -e "\n\e[33mThis was a dry run. No actual files or packages were removed.\e[0m"
