#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")"
BASE_DIR="$(pwd)"

# Source shared logic
source ./scriptdata/environment-variables
source ./scriptdata/functions
source ./scriptdata/installers
source ./scriptdata/options

ASK=false
DRY_RUN=false
LINK=true
FORCE=false
INSTALL_CONFIGS=true
INSTALL_PACKAGES=true
SKIP_BACKUP=true

while [[ $# -gt 0 ]]; do
  case "$1" in
  --no-confirm) ASK=false ;;
  --dry-run) DRY_RUN=true ;;
  --copy) LINK=false ;;
  --force) FORCE=true ;;
  --skip-backup) SKIP_BACKUP=true ;;
  --only-configs) INSTALL_PACKAGES=false ;;
  --only-packages) INSTALL_CONFIGS=false ;;
  --help)
    echo "Usage: $0 [--no-confirm] [--dry-run] [--copy] [--force] [--skip-backup] [--only-configs|--only-packages]"
    exit 0
    ;;
  --)
    shift
    break
    ;;
  *) echo "Unknown flag: $1" && exit 1 ;;
  esac
  shift
done

log() { echo -e "\e[36m[INFO]\e[0m $1"; }
warn() { echo -e "\e[33m[WARN]\e[0m $1"; }
run() { $DRY_RUN && echo "[DRY-RUN] $*" || eval "$*"; }

prevent_sudo_or_root

# === 1. GIT UPDATE ===
log "Pulling latest changes from git..."
git fetch origin
UPDATED_FILES=$(git diff --name-only HEAD..origin/HEAD)
git pull --rebase --stat

if [[ -n "$UPDATED_FILES" ]]; then
  log "Dotfiles updated:"
  echo "$UPDATED_FILES"
else
  log "Dotfiles already up to date."
fi

# === 2. BACKUP ===
if [[ "$SKIP_BACKUP" == false ]]; then
  log "Backing up ~/.config and ~/.local"
  run backup_configs
else
  log "Skipping backup..."
fi

# === 3. PACKAGE UPDATES ===
if [[ "$INSTALL_PACKAGES" == true ]]; then
  log "Syncing package database and upgrading system..."
  $ASK && run sudo pacman -Syu || run sudo pacman -Syu --noconfirm

  remove_bashcomments_emptylines "$DEPLISTFILE" ./cache/dependencies_stripped.conf
  mapfile -t pkglist <./cache/dependencies_stripped.conf

  if ! command -v yay >/dev/null; then
    log "\"yay\" not found, installing it..."
    run install-yay
  fi

  log "Installing/updating listed packages..."
  UPDATED_PKGS=()
  for pkg in "${pkglist[@]}"; do
    if ! pacman -Q "$pkg" &>/dev/null || ! is_installed_exact "$pkg"; then
      UPDATED_PKGS+=("$pkg")
      run yay -S --needed --noconfirm "$pkg"
    fi
  done

  run handle-deprecated-dependencies

  meta_pkgs=(
    illogical-impulse-audio
    illogical-impulse-backlight
    illogical-impulse-basic
    illogical-impulse-fonts-themes
    illogical-impulse-hyprland
    illogical-impulse-kde
    illogical-impulse-portal
    illogical-impulse-python
    illogical-impulse-screencapture
    illogical-impulse-toolkit
    illogical-impulse-widgets
    illogical-impulse-microtex-git
  )

  for mp in "${meta_pkgs[@]}"; do
    path="./arch-packages/$mp"
    [[ -d "$path" ]] || continue
    flags="--needed"
    [[ "$ASK" == false ]] && flags="$flags --noconfirm"
    run install-local-pkgbuild "$path" "$flags"
  done

  run install-python-packages

  if [[ ${#UPDATED_PKGS[@]} -gt 0 ]]; then
    log "Packages installed/updated:"
    printf '%s\n' "${UPDATED_PKGS[@]}"
  else
    log "All packages were already up to date."
  fi
else
  log "Skipping package updates (--only-configs)"
fi

# === 4. CONFIG UPDATES ===
if [[ "$INSTALL_CONFIGS" == true ]]; then
  log "Syncing configuration files..."

  mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_BIN_HOME"

  for config in $(find .config/ -mindepth 1 -maxdepth 1 -exec basename {} \;); do
    src="$BASE_DIR/.config/$config"
    dest="$XDG_CONFIG_HOME/$config"

    if [[ "$LINK" == true ]]; then
      if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
        log "Skipping already-linked $dest"
      else
        [[ "$FORCE" == true ]] && run rm -rf "$dest"
        log "Linking $src → $dest"
        run ln -sfn "$src" "$dest"
      fi
    else
      log "Copying $src → $dest"
      run rsync -av --delete "$src/" "$dest/"
    fi
  done
else
  log "Skipping config sync (--only-packages)"
fi

log "Update complete ✅"
if [[ "$DRY_RUN" == true ]]; then
  echo -e "\e[33m[DRY-RUN] No files or packages were modified.\e[0m"
fi
