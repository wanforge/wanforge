#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-cockpit.sh — install Cockpit web console + modules, configure it to
# run behind a reverse proxy (e.g. CloudPanel), open the firewall port.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/install-cockpit.sh | bash
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="install-cockpit"

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
  local themes=("51 50 44 38 37 31" "45 39 33 32 26 21" "48 42 36 35 29 28" \
    "141 135 134 98 92 91" "218 212 211 205 199 198" "215 214 208 202 173 166")
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
svc_enable_start() { local s="$1"; ${SUDO} systemctl enable "$s" >/dev/null 2>&1 || true; ${SUDO} systemctl start "$s" || true; }

# ---- run ----------------------------------------------------------------
banner
if ! command -v apt-get >/dev/null 2>&1; then err "This script targets Debian/Ubuntu (apt)."; exit 1; fi

info "Installing Cockpit..."
${SUDO} apt-get update
${SUDO} apt-get install -y cockpit
svc_enable_start cockpit
ok "Cockpit installed and running."

info "Installing extra modules (networkmanager, storaged, sosreport, pcp)..."
${SUDO} apt-get install -y cockpit-networkmanager cockpit-storaged cockpit-sosreport cockpit-pcp || warn "Some modules unavailable."
${SUDO} systemctl enable --now pmcd pmlogger 2>/dev/null || warn "Could not enable pmcd/pmlogger."

# reverse-proxy config
RP_ANS="$(ask "Configure Cockpit behind a reverse proxy (CloudPanel)? [y/N]:" "n")"
case "${RP_ANS}" in
  y|Y|yes)
    ORIGIN="$(ask "Allowed origin (e.g. https://cockpit.domain.id):" "")"
    if [ -z "${ORIGIN}" ]; then
      warn "No origin given; skipping cockpit.conf."
    else
      warn "AllowUnencrypted=true is only safe when TLS is terminated by the proxy."
      ${SUDO} mkdir -p /etc/cockpit
      printf '[WebService]\nAllowOrigins = %s\nProtocolHeader = X-Forwarded-Proto\nAllowUnencrypted = true\n' "${ORIGIN}" \
        | ${SUDO} tee /etc/cockpit/cockpit.conf >/dev/null
      ${SUDO} systemctl restart cockpit || true
      ok "Wrote /etc/cockpit/cockpit.conf (origin: ${ORIGIN})."
    fi
    ;;
  *) info "Skipped reverse-proxy config." ;;
esac

# firewall
if command -v ufw >/dev/null 2>&1; then
  PORT_ANS="$(ask "Open port 9090 in ufw? [Y/n]:" "y")"
  case "${PORT_ANS}" in
    n|N|no) info "Left firewall unchanged." ;;
    *) ${SUDO} ufw allow 9090/tcp && ok "Opened 9090/tcp." ;;
  esac
else
  info "ufw not installed; skipping firewall rule (Cockpit listens on 9090)."
fi

printf "\n%b✔ Cockpit ready.%b  %bhttp://127.0.0.1:9090%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" "${C_DIM}" "${C_RESET}" >&2
