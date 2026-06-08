#!/usr/bin/env bash
# shellcheck disable=SC2086  # package lists are intentionally word-split
#
# install-server.sh — multi-distro Linux server setup.
# Auto-detects the package manager: apt, dnf, yum, pacman, zypper, apk.
#
# Steps: base packages -> timezone -> firewall (ufw) -> fail2ban.
# Interactive steps can be skipped.
#
# Usage (public repo, no auth needed):
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/deploy/install-server.sh | bash
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail

# =========================================================================
# colors
# =========================================================================
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"; C_DIM="\033[2m"
  C_RED="\033[38;5;196m"; C_GREEN="\033[38;5;46m"
  C_YELLOW="\033[38;5;226m"; C_CYAN="\033[38;5;45m"
  USE_COLOR=1
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
  USE_COLOR=0
fi

# =========================================================================
# random-gradient WANFORGE banner
# =========================================================================
banner() {
  local lines=(
'██╗    ██╗ █████╗ ███╗   ██╗███████╗ ██████╗ ██████╗  ██████╗ ███████╗'
'██║    ██║██╔══██╗████╗  ██║██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝'
'██║ █╗ ██║███████║██╔██╗ ██║█████╗  ██║   ██║██████╔╝██║  ███╗█████╗  '
'██║███╗██║██╔══██║██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝  '
'╚███╔███╔╝██║  ██║██║ ╚████║██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗'
' ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝'
  )
  # preset gradient themes; one is picked at random each run
  local themes=(
    "51 45 39 99 135 171"   # cyan -> magenta
    "46 48 50 45 39 33"     # green -> blue
    "214 208 202 196 160 124" # orange -> red
    "93 99 135 171 207 213" # purple -> pink
    "226 220 214 208 202 196" # fire
    "51 45 39 33 27 21"     # ocean
    "196 208 226 46 51 93"  # rainbow
    "201 165 129 93 57 21"  # violet -> blue
  )
  local pick=$(( RANDOM % ${#themes[@]} ))
  read -r -a grad <<< "${themes[$pick]}"
  printf "\n" >&2
  local i=0
  for l in "${lines[@]}"; do
    if [ "${USE_COLOR}" -eq 1 ]; then
      printf "\033[1;38;5;%sm%s\033[0m\n" "${grad[$i]}" "$l" >&2
    else
      printf "%s\n" "$l" >&2
    fi
    i=$((i + 1))
    sleep 0.04
  done
  printf "%b        install-server • MIT © 2026 Sugeng Sulistiyawan%b\n\n" "${C_DIM}" "${C_RESET}" >&2
}

# =========================================================================
# logging helpers
# =========================================================================
STEP=0
TOTAL=4
step() { STEP=$((STEP + 1)); printf "\n%b==> [%d/%d] %s%b\n" "${C_BOLD}${C_CYAN}" "${STEP}" "${TOTAL}" "$1" "${C_RESET}" >&2; }
info() { printf "    %b•%b %s\n" "${C_DIM}" "${C_RESET}" "$1" >&2; }
ok()   { printf "    %b✔%b %s\n" "${C_GREEN}" "${C_RESET}" "$1" >&2; }
warn() { printf "    %b!%b %s\n" "${C_YELLOW}" "${C_RESET}" "$1" >&2; }
err()  { printf "    %b✖%b %s\n" "${C_RED}" "${C_RESET}" "$1" >&2; }

# read from the terminal even when run via `curl | bash`
if [ -e /dev/tty ]; then exec 3</dev/tty; else exec 3<&0; fi
ask() { # ask "prompt" "default" -> echoes answer
  local prompt="$1" def="${2:-}" ans
  printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${prompt}" >&2
  read -r ans <&3 || ans=""
  echo "${ans:-$def}"
}

# =========================================================================
# privilege + package manager
# =========================================================================
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

detect_pm() {
  for pm in apt-get dnf yum pacman zypper apk; do
    command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return 0; }
  done
  return 1
}

pm_update() {
  case "${PM}" in
    apt-get) ${SUDO} apt-get update ;;
    dnf)     ${SUDO} dnf -y makecache ;;
    yum)     ${SUDO} yum -y makecache ;;
    pacman)  ${SUDO} pacman -Sy --noconfirm ;;
    zypper)  ${SUDO} zypper --non-interactive refresh ;;
    apk)     ${SUDO} apk update ;;
  esac
}

pm_upgrade() {
  case "${PM}" in
    apt-get) ${SUDO} apt-get upgrade -y ;;
    dnf)     ${SUDO} dnf -y upgrade --refresh ;;
    yum)     ${SUDO} yum -y update ;;
    pacman)  ${SUDO} pacman -Su --noconfirm ;;
    zypper)  ${SUDO} zypper --non-interactive update ;;
    apk)     ${SUDO} apk upgrade ;;
  esac
}

pm_install() { # pm_install pkg1 pkg2 ...
  local pkgs="$*"
  case "${PM}" in
    apt-get) ${SUDO} apt-get install -y ${pkgs} ;;
    dnf)     ${SUDO} dnf -y install ${pkgs} ;;
    yum)     ${SUDO} yum -y install ${pkgs} ;;
    pacman)  ${SUDO} pacman -S --noconfirm --needed ${pkgs} ;;
    zypper)  ${SUDO} zypper --non-interactive install ${pkgs} ;;
    apk)     ${SUDO} apk add ${pkgs} ;;
  esac
}

pm_cleanup() {
  case "${PM}" in
    apt-get) ${SUDO} apt-get autoremove -y; ${SUDO} apt-get autoclean ;;
    dnf)     ${SUDO} dnf -y autoremove; ${SUDO} dnf clean all ;;
    yum)     ${SUDO} yum -y autoremove || true; ${SUDO} yum clean all ;;
    pacman)  ${SUDO} pacman -Qtdq 2>/dev/null | ${SUDO} pacman -Rns --noconfirm - 2>/dev/null || true ;;
    zypper)  ${SUDO} zypper clean --all ;;
    apk)     : ;;
  esac
}

# base package set per manager (names differ across distros)
base_pkgs() {
  case "${PM}" in
    apt-get) echo "micro curl wget git speedtest-cli python3 python3-pip python3-dev python3-virtualenv" ;;
    dnf)     echo "micro curl wget git speedtest-cli python3 python3-pip python3-devel python3-virtualenv" ;;
    yum)     echo "micro curl wget git python3 python3-pip python3-devel" ;;
    pacman)  echo "micro curl wget git python python-pip python-virtualenv speedtest-cli" ;;
    zypper)  echo "micro curl wget git python3 python3-pip python3-devel python3-virtualenv" ;;
    apk)     echo "micro curl wget git python3 py3-pip python3-dev py3-virtualenv" ;;
  esac
}

# enable + start a systemd/openrc service, best effort
svc_enable_start() { # svc_enable_start name
  local svc="$1"
  if command -v systemctl >/dev/null 2>&1; then
    ${SUDO} systemctl enable "${svc}" >/dev/null 2>&1 || true
    ${SUDO} systemctl start "${svc}" || true
  elif command -v rc-update >/dev/null 2>&1; then
    ${SUDO} rc-update add "${svc}" default >/dev/null 2>&1 || true
    ${SUDO} rc-service "${svc}" start || true
  else
    warn "No init system detected; start ${svc} manually."
  fi
}

# =========================================================================
# run
# =========================================================================
banner

PM="$(detect_pm)" || { err "No supported package manager found."; exit 1; }
info "Detected package manager: ${C_BOLD}${PM}${C_RESET}"

# ---- step 1: base packages ----------------------------------------------
step "Update system & install base packages"
info "Refreshing package index..."
pm_update
info "Upgrading installed packages..."
pm_upgrade
PKGS="$(base_pkgs)"
info "Installing: ${PKGS}"
pm_install ${PKGS}
info "Cleaning up..."
pm_cleanup
if ! command -v speedtest-cli >/dev/null 2>&1 && command -v pip3 >/dev/null 2>&1; then
  info "speedtest-cli missing from repo; installing via pip3"
  pip3 install --user speedtest-cli >/dev/null 2>&1 || true
fi
ok "Base packages ready."

# ---- step 2: timezone ----------------------------------------------------
step "Set timezone"
if ! command -v timedatectl >/dev/null 2>&1; then
  warn "timedatectl not available; skipping timezone."
else
  TZ_ANS="$(ask "Timezone? [Asia/Jakarta] (Enter=set, 's'=skip, or type a zone):" "Asia/Jakarta")"
  if [ "${TZ_ANS}" = "s" ] || [ "${TZ_ANS}" = "S" ] || [ "${TZ_ANS}" = "skip" ]; then
    info "Skipped timezone."
  else
    info "Setting timezone to ${TZ_ANS}"
    if ${SUDO} timedatectl set-timezone "${TZ_ANS}"; then
      ${SUDO} timedatectl || true
      ok "Timezone set to ${TZ_ANS}."
    else
      err "Failed to set timezone '${TZ_ANS}' (invalid zone?)."
    fi
  fi
fi

# ---- step 3: firewall (ufw) ---------------------------------------------
step "Configure firewall (ufw)"
FW_ANS="$(ask "Configure ufw firewall? [y/N/skip]:" "n")"
case "${FW_ANS}" in
  y|Y|yes)
    if ! command -v ufw >/dev/null 2>&1; then
      info "Installing ufw..."
      pm_install ufw || warn "Could not install ufw (mainly Debian/Ubuntu)."
    fi
    if command -v ufw >/dev/null 2>&1; then
      info "Applying base rules: OpenSSH, http, https"
      ${SUDO} ufw allow OpenSSH 2>/dev/null || ${SUDO} ufw allow 22/tcp
      ${SUDO} ufw allow http  2>/dev/null || ${SUDO} ufw allow 80/tcp
      ${SUDO} ufw allow https 2>/dev/null || ${SUDO} ufw allow 443/tcp
      # extra custom ports (e.g. 8443/tcp), comma/space separated; Enter to skip
      PORTS_ANS="$(ask "Extra ports to allow? (e.g. '8443/tcp 3000/tcp', Enter to skip):" "")"
      if [ -n "${PORTS_ANS}" ]; then
        for p in ${PORTS_ANS//,/ }; do
          info "Allowing ${p}"
          ${SUDO} ufw allow "${p}" || warn "Failed to allow ${p}"
        done
      fi
      info "Enabling firewall..."
      ${SUDO} ufw --force enable
      ${SUDO} ufw status verbose || true
      ok "Firewall configured."
    fi
    ;;
  *) info "Skipped firewall." ;;
esac

# ---- step 4: fail2ban ----------------------------------------------------
step "Install Fail2Ban"
F2B_ANS="$(ask "Install & enable Fail2Ban? [y/N/skip]:" "n")"
case "${F2B_ANS}" in
  y|Y|yes)
    info "Installing fail2ban..."
    if pm_install fail2ban; then
      svc_enable_start fail2ban
      ok "Fail2Ban installed and started."
    else
      err "Failed to install fail2ban."
    fi
    ;;
  *) info "Skipped Fail2Ban." ;;
esac

printf "\n%b✔ Setup complete.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
