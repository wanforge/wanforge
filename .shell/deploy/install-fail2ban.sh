#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-fail2ban.sh — install & enable Fail2Ban (interactive, multi-distro).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/deploy/install-fail2ban.sh | bash
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="install-fail2ban"

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
svc_enable_start() {
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

# ---- run ----------------------------------------------------------------
banner
PM="$(detect_pm)" || { err "No supported package manager found."; exit 1; }
ANS="$(ask "Install & enable Fail2Ban? [Y/n]:" "y")"
case "${ANS}" in
  n|N|no) info "Skipped Fail2Ban."; exit 0 ;;
esac
info "Installing fail2ban..."
pm_install fail2ban || { err "Failed to install fail2ban."; exit 1; }
svc_enable_start fail2ban
printf "\n%b✔ Fail2Ban installed and started.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
