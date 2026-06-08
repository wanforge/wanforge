#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# enable-mysql-remote.sh — allow remote access to MySQL/MariaDB by setting
# bind-address and opening the firewall (security-sensitive).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/enable-mysql-remote.sh | bash
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="enable-mysql-remote"

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

# ---- run ----------------------------------------------------------------
banner
if [ ! -d /etc/mysql ]; then err "/etc/mysql not found. Install MySQL/MariaDB first."; exit 1; fi

warn "This exposes the database to the network. Restrict the source range when possible."

# locate the config file that defines bind-address
CONF="$(${SUDO} grep -rlE '^[[:space:]]*bind-address' /etc/mysql 2>/dev/null | head -1 || true)"
if [ -z "${CONF}" ]; then
  for c in /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mariadb.conf.d/50-server.cnf; do
    [ -f "$c" ] && { CONF="$c"; break; }
  done
fi
[ -z "${CONF}" ] && { err "Could not find a MySQL/MariaDB config file."; exit 1; }
info "Config file: ${CONF}"

CIDR="$(ask "Allowed source CIDR (e.g. 10.0.0.0/8; '0.0.0.0/0'=anywhere, NOT recommended):" "0.0.0.0/0")"

PROCEED="$(ask "Set bind-address = 0.0.0.0 in ${CONF}? [y/N]:" "n")"
case "${PROCEED}" in
  y|Y|yes)
    ${SUDO} cp "${CONF}" "${CONF}.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
    if ${SUDO} grep -qE '^[[:space:]]*bind-address' "${CONF}"; then
      ${SUDO} sed -i 's|^[[:space:]]*bind-address.*|bind-address = 0.0.0.0|' "${CONF}"
    else
      printf '\n[mysqld]\nbind-address = 0.0.0.0\n' | ${SUDO} tee -a "${CONF}" >/dev/null
    fi
    ok "Set bind-address = 0.0.0.0."

    # restart whichever service exists
    if ${SUDO} systemctl restart mysql 2>/dev/null; then ok "Restarted mysql."
    elif ${SUDO} systemctl restart mariadb 2>/dev/null; then ok "Restarted mariadb."
    else warn "Could not restart mysql/mariadb; restart manually."; fi

    if command -v ufw >/dev/null 2>&1; then
      if [ "${CIDR}" = "0.0.0.0/0" ]; then ${SUDO} ufw allow 3306/tcp
      else ${SUDO} ufw allow from "${CIDR}" to any port 3306 proto tcp; fi
      ok "Firewall: allowed 3306/tcp from ${CIDR}."
    else
      info "ufw not installed; open port 3306 manually if needed."
    fi
    warn "Remember to grant DB users a host that matches remote clients (e.g. 'user'@'%')."
    ;;
  *) info "Aborted; no changes made." ;;
esac

printf "\n%b✔ MySQL remote-access step finished.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
