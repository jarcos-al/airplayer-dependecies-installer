#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Proxmox Audio Prep v1.0 (root-friendly)
# - Installs ALSA tooling + useful diagnostics
# - Ensures root is in audio group (optional but harmless)
# - Ensures snd_usb_audio doesn't steal index 0 (stable card ordering)
# - Idempotent, safe-ish defaults, logs to /tmp
# ==============================================================================
LOGFILE="/tmp/proxmox-audio-prep.log"
exec >>"$LOGFILE" 2>&1

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

NEEDS_REBOOT=false
APT_UPDATED=false

print_info()    { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }

command_exists() { command -v "$1" &>/dev/null; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    print_error "Run this script as root."
    exit 1
  fi
}

is_debian_like() {
  [ -f /etc/debian_version ] && command_exists apt-get
}

maybe_apt_update() {
  if [ "$APT_UPDATED" = false ]; then
    print_info "Updating package cache..."
    if ! apt-get update -y >/dev/null; then
      print_warning "Could not update apt cache (continuing)."
    fi
    APT_UPDATED=true
  fi
}

install_package() {
  local pkg="$1"
  local cmd="${2:-$pkg}"

  if command_exists "$cmd"; then
    print_info "Package '$pkg' already installed (cmd '$cmd' found)."
    return 0
  fi

  if ! is_debian_like; then
    print_warning "Non Debian-like system or apt-get missing. Skipping install of '$pkg'."
    return 0
  fi

  print_info "Installing package '$pkg'..."
  maybe_apt_update
  if apt-get install -y "$pkg"; then
    print_success "Package '$pkg' installed."
  else
    print_error "Could not install '$pkg'. Please install it manually."
  fi
}

backup_file() {
  local file="$1"
  if [ -e "$file" ]; then
    local bak="${file}.bak.$(date +%s)"
    cp -a "$file" "$bak" && print_info "Backup: $file -> $bak"
  fi
}

ensure_line_in_file() {
  local line="$1"
  local file="$2"

  touch "$file"
  if ! grep -Fxq "$line" "$file"; then
    echo "$line" >> "$file"
    return 0
  fi
  return 1
}

write_modprobe_order() {
  local target="/etc/modprobe.d/alsa-base.conf"
  local line="options snd_usb_audio index=-2"

  # Make a backup once per run if we're going to modify.
  if [ ! -f "$target" ]; then
    touch "$target"
    chmod 644 "$target"
  fi

  if ensure_line_in_file "$line" "$target"; then
    chmod 644 "$target"
    print_success "Updated $target: added '$line'"
    NEEDS_REBOOT=true
  else
    print_info "No change: '$line' already present in $target"
  fi
}

show_cards() {
  print_info "Sound cards (/proc/asound/cards):"
  if [ -r /proc/asound/cards ]; then
    cat /proc/asound/cards
  else
    print_warning "Cannot read /proc/asound/cards"
  fi

  if command_exists aplay; then
    print_info "aplay -l:"
    aplay -l || true
  fi
}

ensure_audio_group_and_root_membership() {
  # Ensure audio group exists
  if ! getent group audio >/dev/null; then
    print_info "Group 'audio' not found. Creating..."
    if groupadd audio; then
      print_success "Group 'audio' created."
      NEEDS_REBOOT=true
    else
      print_warning "Could not create group 'audio' (continuing)."
    fi
  fi

  # Add root to audio group (often already effectively privileged, but helps some setups/tools)
  if id -nG root | grep -qw audio; then
    print_info "User 'root' already belongs to group 'audio'."
  else
    print_info "Adding user 'root' to group 'audio'..."
    if usermod -aG audio root; then
      print_success "User 'root' added to group 'audio'."
      NEEDS_REBOOT=true
    else
      print_warning "Could not add root to group 'audio' (continuing)."
    fi
  fi
}

main() {
  require_root
  print_info "Starting Proxmox audio preparation (root-friendly)..."
  print_info "Log: $LOGFILE"

  # 1) Group membership
  ensure_audio_group_and_root_membership

  # 2) Packages (common + helpful for audio debugging on Debian/Proxmox)
  install_package alsa-utils aplay
  install_package pciutils lspci

  # Optional: only install if available (not all Proxmox installs need it)
  # If it fails, it will just warn.
  install_package firmware-sof-signed true

  # 3) Detect sound cards
  if command_exists aplay; then
    if aplay -l 2>&1 | grep -qi "no soundcards found"; then
      print_warning "No sound cards detected by ALSA (aplay reports none)."
    else
      print_success "ALSA reports sound card(s) present."
    fi
  else
    print_warning "aplay not available (alsa-utils missing?)."
  fi
  show_cards

  # 4) Fix ALSA order for USB audio (avoid grabbing index 0)
  write_modprobe_order

  # 5) Final summary
  show_cards
  if [ "$NEEDS_REBOOT" = true ]; then
    print_warning "Some changes may require reboot (or re-login) to apply cleanly."
    print_warning "Recommended: reboot the node if this is a dedicated box."
  else
    print_success "Done. No reboot required."
  fi

  print_success "Completed. Check log at: $LOGFILE"
}
