#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# secure-ssh.sh — harden SSH: change port (default 20829), disable root login,
# optionally disable password auth, enable pubkey auth. Opens the new port in
# the firewall BEFORE restarting sshd to avoid lockout.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/secure-ssh.sh | bash
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="secure-ssh"
DEFAULT_PORT="20829"

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

SSHD_MAIN="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
DROPIN="${DROPIN_DIR}/99-wanforge-hardening.conf"

# set_opt KEY VALUE FILE — replace commented/uncommented line, or append
set_opt() {
  local key="$1" val="$2" file="$3"
  if ${SUDO} grep -qE "^[#[:space:]]*${key}\b" "${file}" 2>/dev/null; then
    ${SUDO} sed -i "s|^[#[:space:]]*${key}\b.*|${key} ${val}|" "${file}"
  else
    echo "${key} ${val}" | ${SUDO} tee -a "${file}" >/dev/null
  fi
}

# ---- run ----------------------------------------------------------------
banner
[ -f "${SSHD_MAIN}" ] || { err "${SSHD_MAIN} not found. Is OpenSSH server installed?"; exit 1; }

warn "Changing the SSH port and disabling password auth can LOCK YOU OUT."
warn "Keep your CURRENT session open. Only close it after logging in on the new port."

# port
PORT="$(ask "New SSH port:" "${DEFAULT_PORT}")"
if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
  err "Invalid port: ${PORT}"; exit 1
fi

# policy choices
ROOT_ANS="$(ask "Disable root login (PermitRootLogin no)? [Y/n]:" "y")"
PUBKEY_ANS="$(ask "Enable pubkey auth (PubkeyAuthentication yes)? [Y/n]:" "y")"
PWAUTH_ANS="$(ask "Disable password auth (key-only login)? [y/N]:" "n")"

# safety: if disabling passwords, make sure a key is present
if [[ "${PWAUTH_ANS}" =~ ^(y|Y|yes)$ ]]; then
  KEYFOUND=0
  for f in "${HOME}/.ssh/authorized_keys" /root/.ssh/authorized_keys; do
    [ -s "$f" ] && KEYFOUND=1
  done
  if [ "${KEYFOUND}" -eq 0 ]; then
    warn "No authorized_keys found. Disabling password auth now may lock you out."
    CONFIRM="$(ask "Type 'yes' to proceed anyway:" "no")"
    [ "${CONFIRM}" = "yes" ] || { info "Keeping password auth enabled."; PWAUTH_ANS="n"; }
  fi
fi

# choose target file: drop-in if Include is active, else the main config
if ${SUDO} grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' "${SSHD_MAIN}"; then
  ${SUDO} mkdir -p "${DROPIN_DIR}"
  TARGET="${DROPIN}"
  ${SUDO} touch "${TARGET}"
  info "Using drop-in: ${TARGET}"
else
  TARGET="${SSHD_MAIN}"
  info "Editing main config: ${TARGET}"
fi

# backup
BACKUP="${SSHD_MAIN}.bak.$(date +%s 2>/dev/null || echo bak)"
${SUDO} cp "${SSHD_MAIN}" "${BACKUP}"
[ "${TARGET}" != "${SSHD_MAIN}" ] && ${SUDO} cp "${TARGET}" "${TARGET}.bak" 2>/dev/null || true
info "Backup: ${BACKUP}"

# apply settings
set_opt "Port" "${PORT}" "${TARGET}"
[[ "${ROOT_ANS}"   =~ ^(n|N|no)$ ]] || set_opt "PermitRootLogin" "no" "${TARGET}"
[[ "${PUBKEY_ANS}" =~ ^(n|N|no)$ ]] || set_opt "PubkeyAuthentication" "yes" "${TARGET}"
[[ "${PWAUTH_ANS}" =~ ^(y|Y|yes)$ ]] && set_opt "PasswordAuthentication" "no" "${TARGET}"
ok "Applied SSH settings."

# open the new port in the firewall BEFORE restarting sshd
if command -v ufw >/dev/null 2>&1; then
  info "Allowing ${PORT}/tcp in ufw (before restart)..."
  ${SUDO} ufw allow "${PORT}/tcp" || warn "Failed to add ufw rule for ${PORT}."
else
  warn "ufw not installed. Make sure ${PORT}/tcp is open in your firewall/security group."
fi

# validate config before restarting
if ! ${SUDO} sshd -t; then
  err "sshd config test FAILED. Restoring backup; NOT restarting."
  ${SUDO} cp "${BACKUP}" "${SSHD_MAIN}"
  [ "${TARGET}" != "${SSHD_MAIN}" ] && ${SUDO} rm -f "${TARGET}"
  exit 1
fi
ok "sshd -t passed."

RESTART="$(ask "Restart SSH now to apply port ${PORT}? [y/N]:" "n")"
case "${RESTART}" in
  y|Y|yes)
    ${SUDO} systemctl restart ssh 2>/dev/null || ${SUDO} systemctl restart sshd 2>/dev/null || warn "Could not restart ssh; restart manually."
    ok "SSH restarted on port ${PORT}."
    ;;
  *) info "Not restarted. Apply later with: ${SUDO} systemctl restart ssh" ;;
esac

# optionally remove the old port 22 rule (ask, default keep to avoid lockout)
if command -v ufw >/dev/null 2>&1 && [ "${PORT}" != "22" ]; then
  DROP22="$(ask "Remove the old ufw rule for 22/tcp / OpenSSH? (only after the new port works) [y/N]:" "n")"
  case "${DROP22}" in
    y|Y|yes)
      ${SUDO} ufw delete allow OpenSSH 2>/dev/null || true
      ${SUDO} ufw delete allow 22/tcp 2>/dev/null || true
      ok "Removed old SSH (22) rules."
      ;;
    *) info "Kept port 22 rule. Remove it later once ${PORT} is verified." ;;
  esac
fi

printf "\n%b✔ SSH hardening applied.%b\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
printf "%b  TEST NOW in a new terminal: ssh -p %s <user>@<host>%b\n" "${C_YELLOW}" "${PORT}" "${C_RESET}" >&2
printf "%b  Keep this session open until the new port works.%b\n\n" "${C_DIM}" "${C_RESET}" >&2
