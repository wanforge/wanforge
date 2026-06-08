#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-firewall.sh — install & configure ufw firewall (interactive).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/deploy/install-firewall.sh | bash
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="install-firewall"

# ---- common preamble ----------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"; C_DIM="\033[2m"
  C_RED="\033[38;5;196m"; C_GREEN="\033[38;5;46m"; C_YELLOW="\033[38;5;226m"; C_CYAN="\033[38;5;45m"
  USE_COLOR=1
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; USE_COLOR=0
fi
banner() {
  local lines=(
'██╗    ██╗ █████╗ ███╗   ██╗███████╗ ██████╗ ██████╗  ██████╗ ███████╗'
'██║    ██║██╔══██╗████╗  ██║██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝'
'██║ █╗ ██║███████║██╔██╗ ██║█████╗  ██║   ██║██████╔╝██║  ███╗█████╗  '
'██║███╗██║██╔══██║██║╚██╗██║██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝  '
'╚███╔███╔╝██║  ██║██║ ╚████║██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗'
' ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝'
  )
  local themes=("51 45 39 99 135 171" "46 48 50 45 39 33" "214 208 202 196 160 124" \
    "93 99 135 171 207 213" "226 220 214 208 202 196" "51 45 39 33 27 21" \
    "196 208 226 46 51 93" "201 165 129 93 57 21")
  local pick=$(( RANDOM % ${#themes[@]} )); read -r -a grad <<< "${themes[$pick]}"
  printf "\n" >&2; local i=0
  for l in "${lines[@]}"; do
    if [ "${USE_COLOR}" -eq 1 ]; then printf "\033[1;38;5;%sm%s\033[0m\n" "${grad[$i]}" "$l" >&2
    else printf "%s\n" "$l" >&2; fi
    i=$((i + 1)); sleep 0.04
  done
  printf "%b        wanforge.asia · %s • MIT © 2026 Sugeng Sulistiyawan%b\n\n" "${C_DIM}" "${TASK}" "${C_RESET}" >&2
}
info() { printf "    %b•%b %s\n" "${C_DIM}" "${C_RESET}" "$1" >&2; }
ok()   { printf "    %b✔%b %s\n" "${C_GREEN}" "${C_RESET}" "$1" >&2; }
warn() { printf "    %b!%b %s\n" "${C_YELLOW}" "${C_RESET}" "$1" >&2; }
err()  { printf "    %b✖%b %s\n" "${C_RED}" "${C_RESET}" "$1" >&2; }
if [ -e /dev/tty ]; then exec 3</dev/tty; else exec 3<&0; fi
ask() { local prompt="$1" def="${2:-}" ans; printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${prompt}" >&2; read -r ans <&3 || ans=""; echo "${ans:-$def}"; }
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
detect_pm() { for pm in apt-get dnf yum pacman zypper apk; do command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return 0; }; done; return 1; }
pm_install() {
  local pkgs="$*"
  case "${PM}" in
    apt-get) ${SUDO} apt-get install -y ${pkgs} ;; dnf) ${SUDO} dnf -y install ${pkgs} ;; yum) ${SUDO} yum -y install ${pkgs} ;;
    pacman) ${SUDO} pacman -S --noconfirm --needed ${pkgs} ;; zypper) ${SUDO} zypper --non-interactive install ${pkgs} ;; apk) ${SUDO} apk add ${pkgs} ;;
  esac
}

# ---- run ----------------------------------------------------------------
banner
PM="$(detect_pm)" || { err "No supported package manager found."; exit 1; }

if ! command -v ufw >/dev/null 2>&1; then
  info "ufw not found; installing..."
  pm_install ufw || { err "Could not install ufw (mainly Debian/Ubuntu)."; exit 1; }
fi

info "Applying base rules: OpenSSH, http, https"
${SUDO} ufw allow OpenSSH 2>/dev/null || ${SUDO} ufw allow 22/tcp
${SUDO} ufw allow http  2>/dev/null || ${SUDO} ufw allow 80/tcp
${SUDO} ufw allow https 2>/dev/null || ${SUDO} ufw allow 443/tcp

PORTS_ANS="$(ask "Extra ports to allow? (e.g. '8443/tcp 3000/tcp', Enter to skip):" "")"
if [ -n "${PORTS_ANS}" ]; then
  for p in ${PORTS_ANS//,/ }; do
    info "Allowing ${p}"; ${SUDO} ufw allow "${p}" || warn "Failed to allow ${p}"
  done
fi

ENABLE_ANS="$(ask "Enable firewall now? [Y/n]:" "y")"
case "${ENABLE_ANS}" in
  n|N|no) info "Rules added but firewall left disabled." ;;
  *) info "Enabling firewall..."; ${SUDO} ufw --force enable; ${SUDO} ufw status verbose || true ;;
esac
printf "\n%b✔ Firewall configured.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
