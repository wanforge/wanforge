#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-cockpit.sh — install the Cockpit web console with a grouped checkbox
# menu: core, reverse-proxy config, NetworkManager, plugins, and PCP metrics.
# Each action is selectable/skippable. Debian/Ubuntu only.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/install-cockpit.sh | bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
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
  printf "%b        wanforge.asia · %s • GPLv3 © 2026 Sugeng Sulistiyawan%b\n\n" "${C_DIM}" "${TASK}" "${C_RESET}" >&2
}
info() { printf "    %b•%b %s\n" "${C_DIM}" "${C_RESET}" "$1" >&2; }
ok()   { printf "    %b✔%b %s\n" "${C_GREEN}" "${C_RESET}" "$1" >&2; }
warn() { printf "    %b!%b %s\n" "${C_YELLOW}" "${C_RESET}" "$1" >&2; }
err()  { printf "    %b✖%b %s\n" "${C_RED}" "${C_RESET}" "$1" >&2; }
if [ -e /dev/tty ]; then exec 3</dev/tty; else exec 3<&0; fi
ask() { local p="$1" d="${2:-}" a; printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${p}" >&2; read -r a <&3 || a=""; echo "${a:-$d}"; }
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
svc_enable_start() { local s="$1"; ${SUDO} systemctl enable "$s" >/dev/null 2>&1 || true; ${SUDO} systemctl start "$s" || true; }

# ---- generic checkbox menu (items: "group|key|description"; default ON) --
CHOSEN_KEYS=()
checkbox() {
  local title="${1:-Select:}"
  local n=${#MENU[@]} i cursor=0 first=1 key rest prev g lbl dsc
  local -a checked
  for ((i = 0; i < n; i++)); do checked[i]=1; done
  local groups=0 pg=""
  for ((i = 0; i < n; i++)); do IFS='|' read -r g _ <<< "${MENU[i]}"; [ "$g" != "$pg" ] && { groups=$((groups + 1)); pg="$g"; }; done
  local total=$((n + groups))
  printf "%b%s%b  %b↑/↓ move · SPACE toggle · A all · ENTER confirm · Q quit%b\n\n" \
    "${C_BOLD}" "${title}" "${C_RESET}" "${C_DIM}" "${C_RESET}" >&2
  while true; do
    [ "$first" -eq 0 ] && printf "\033[%dA" "$total" >&2
    first=0; prev=""
    for ((i = 0; i < n; i++)); do
      IFS='|' read -r g lbl dsc <<< "${MENU[i]}"
      if [ "$g" != "$prev" ]; then printf "\033[2K%b── %s ──%b\n" "${C_BOLD}${C_YELLOW}" "$g" "${C_RESET}" >&2; prev="$g"; fi
      local box="[ ]"; [ "${checked[i]}" -eq 1 ] && box="[x]"
      printf "\033[2K" >&2
      if [ "$i" -eq "$cursor" ]; then
        printf "%b❯ %s %-24s%b %b%s%b\n" "${C_CYAN}${C_BOLD}" "$box" "$lbl" "${C_RESET}" "${C_DIM}" "$dsc" "${C_RESET}" >&2
      else
        printf "  %b%s%b %-24s %b%s%b\n" "${C_GREEN}" "$box" "${C_RESET}" "$lbl" "${C_DIM}" "$dsc" "${C_RESET}" >&2
      fi
    done
    IFS= read -rsn1 key <&3 || break
    [ "$key" = $'\x1b' ] && { IFS= read -rsn2 -t 0.01 rest <&3 || rest=""; key+="$rest"; }
    case "$key" in
      $'\x1b[A'|k) cursor=$(( (cursor - 1 + n) % n )) ;;
      $'\x1b[B'|j) cursor=$(( (cursor + 1) % n )) ;;
      ' ') checked[cursor]=$(( 1 - checked[cursor] )) ;;
      a|A) local all=1; for ((i = 0; i < n; i++)); do [ "${checked[i]}" -eq 0 ] && all=0; done; for ((i = 0; i < n; i++)); do checked[i]=$(( 1 - all )); done ;;
      q|Q) CHOSEN_KEYS=(); return 1 ;;
      '') break ;;
    esac
  done
  CHOSEN_KEYS=()
  for ((i = 0; i < n; i++)); do
    if [ "${checked[i]}" -eq 1 ]; then IFS='|' read -r _ lbl _ <<< "${MENU[i]}"; CHOSEN_KEYS+=("$lbl"); fi
  done
  return 0
}
has_key() { local x; for x in "${CHOSEN_KEYS[@]}"; do [ "$x" = "$1" ] && return 0; done; return 1; }

# ---- menu ---------------------------------------------------------------
MENU=(
  "Core|cockpit|Web console: install, enable, start"
  "Core|ufw-9090|Open port 9090 in ufw (skip if proxied by CloudPanel)"
  "Proxy|cockpit-conf|Reverse-proxy config (AllowOrigins, X-Forwarded-Proto)"
  "Network|networkmanager|Install NetworkManager + netplan renderer (risky)"
  "Plugins|cockpit-networkmanager|Networking management"
  "Plugins|cockpit-storaged|Storage management"
  "Plugins|cockpit-sosreport|Diagnostic reports"
  "Plugins|cockpit-pcp|Performance metrics (PCP)"
  "Plugins|cockpit-machines|KVM / libvirt virtual machines"
  "Plugins|cockpit-podman|Podman containers"
  "Metrics|pmcd-pmlogger|Enable pmcd + pmlogger services"
)

# ---- run ----------------------------------------------------------------
banner
if ! command -v apt-get >/dev/null 2>&1; then err "This script targets Debian/Ubuntu (apt)."; exit 1; fi
checkbox "Select Cockpit actions:" || { warn "Cancelled."; exit 0; }
[ "${#CHOSEN_KEYS[@]}" -eq 0 ] && { warn "Nothing selected."; exit 0; }

${SUDO} apt-get update

# core
if has_key cockpit; then
  info "Installing Cockpit..."; ${SUDO} apt-get install -y cockpit; svc_enable_start cockpit; ok "Cockpit running."
fi

# reverse-proxy config
if has_key cockpit-conf; then
  ORIGIN="$(ask "Allowed origin domain (e.g. cockpit.domain.id, Enter to skip):" "")"
  ORIGIN="${ORIGIN#http://}"; ORIGIN="${ORIGIN#https://}"
  if [ -n "${ORIGIN}" ]; then
    warn "AllowUnencrypted=true is only safe behind a TLS-terminating proxy."
    ${SUDO} mkdir -p /etc/cockpit
    printf '[WebService]\nAllowOrigins = %s\nProtocolHeader = X-Forwarded-Proto\nAllowUnencrypted = true\n' "${ORIGIN}" \
      | ${SUDO} tee /etc/cockpit/cockpit.conf >/dev/null
    ${SUDO} systemctl restart cockpit || true
    ok "Wrote /etc/cockpit/cockpit.conf (origin: ${ORIGIN})."
  else
    info "No origin given; skipped cockpit.conf."
  fi
fi

# firewall
if has_key ufw-9090; then
  if command -v ufw >/dev/null 2>&1; then ${SUDO} ufw allow 9090/tcp && ok "Opened 9090/tcp."
  else info "ufw not installed; skipped (Cockpit listens on 9090)."; fi
fi

# NetworkManager + netplan renderer
if has_key networkmanager; then
  warn "Changing the netplan renderer can drop your SSH connection. A backup is made."
  CONF="$(ask "Proceed with NetworkManager renderer? type 'yes' to confirm:" "no")"
  if [ "${CONF}" = "yes" ]; then
    ${SUDO} apt-get install -y network-manager
    NP="$(ls /etc/netplan/*.yaml 2>/dev/null | head -1 || true)"
    if [ -n "${NP}" ]; then
      ${SUDO} cp "${NP}" "${NP}.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
      if ${SUDO} grep -qE '^\s*renderer:' "${NP}"; then
        ${SUDO} sed -i 's|^\s*renderer:.*|  renderer: NetworkManager|' "${NP}"
      else
        ${SUDO} sed -i 's|^\(network:\)|\1\n  renderer: NetworkManager|' "${NP}"
      fi
      ${SUDO} netplan generate && ${SUDO} netplan apply || warn "netplan apply failed; check ${NP}.bak"
      svc_enable_start NetworkManager
      ok "NetworkManager renderer applied (backup: ${NP}.bak.*)."
    else
      warn "No /etc/netplan/*.yaml found; installed NetworkManager only."
    fi
  else
    info "Skipped NetworkManager renderer change."
  fi
fi

# plugins
PLUGINS=""
for p in cockpit-networkmanager cockpit-storaged cockpit-sosreport cockpit-pcp cockpit-machines cockpit-podman; do
  has_key "$p" && PLUGINS="${PLUGINS} ${p}"
done
if [ -n "${PLUGINS# }" ]; then
  info "Installing plugins:${PLUGINS}"
  ${SUDO} apt-get install -y ${PLUGINS} || warn "Some plugins unavailable on this release."
fi

# PCP services
if has_key pmcd-pmlogger; then
  ${SUDO} systemctl enable --now pmcd pmlogger 2>/dev/null && ok "pmcd/pmlogger enabled." || warn "Could not enable pmcd/pmlogger."
fi

printf "\n%b✔ Cockpit setup done.%b  %bhttp://127.0.0.1:9090%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" "${C_DIM}" "${C_RESET}" >&2
