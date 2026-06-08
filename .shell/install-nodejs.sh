#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-nodejs.sh — install Node.js via nvm in the user's home (no sudo),
# choose the version, then optionally install PM2 + pm2-logrotate.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/install-nodejs.sh | bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="install-nodejs"
NVM_VERSION="v0.40.1"   # pinned nvm release; bump as needed

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
ask() { local prompt="$1" def="${2:-}" ans; printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${prompt}" >&2; read -r ans <&3 || ans=""; echo "${ans:-$def}"; }

# ---- run ----------------------------------------------------------------
banner
if [ "$(id -u)" -eq 0 ]; then
  warn "Running as root — Node will install under /root. Run as a normal user for a user-local install."
fi
command -v curl >/dev/null 2>&1 || { err "curl is required."; exit 1; }

# install nvm (user-local, no sudo)
export NVM_DIR="${HOME}/.nvm"
if [ -s "${NVM_DIR}/nvm.sh" ]; then
  info "nvm already present at ${NVM_DIR}"
else
  info "Installing nvm ${NVM_VERSION} into ${NVM_DIR}..."
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi
# shellcheck disable=SC1091
. "${NVM_DIR}/nvm.sh"

NODE_VER="$(ask "Node version to install? (e.g. 18, 20, lts, latest):" "18")"
case "${NODE_VER}" in
  lts|LTS) NODE_VER="--lts" ;;
  latest)  NODE_VER="node" ;;
esac

info "Installing Node ${NODE_VER}..."
# shellcheck disable=SC2086
nvm install ${NODE_VER}
# resolve the concrete version that was installed/selected
RESOLVED="$(nvm version ${NODE_VER} 2>/dev/null || nvm current)"
nvm use "${RESOLVED}"
nvm alias default "${RESOLVED}"
nvm alias stable default >/dev/null 2>&1 || true
ok "Node $(node -v) / npm $(npm -v) (default: ${RESOLVED})"

# PM2 (installed into the nvm-managed prefix — still no sudo)
PM2_ANS="$(ask "Install PM2 process manager + pm2-logrotate? [Y/n]:" "y")"
case "${PM2_ANS}" in
  n|N|no) info "Skipped PM2." ;;
  *)
    info "Installing pm2 globally (user-local via nvm)..."
    npm install -g pm2
    pm2 install pm2-logrotate || warn "pm2-logrotate install failed."
    pm2 save || true
    STARTUP_ANS="$(ask "Enable PM2 on boot? (systemd — needs sudo) [y/N]:" "n")"
    case "${STARTUP_ANS}" in
      y|Y|yes)
        if command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
          CMD="$(pm2 startup systemd -u "${USER}" --hp "${HOME}" | tail -1)"
          info "Running: ${CMD}"
          eval "${CMD}" || warn "pm2 startup failed; run the printed command manually."
        else
          pm2 startup || true
        fi
        pm2 save || true
        ;;
      *) info "Skipped boot startup (run 'pm2 startup' later if needed)." ;;
    esac
    ;;
esac

printf "\n%b✔ Node.js ready.%b  %bopen a new shell or run: source ~/.bashrc%b\n\n" \
  "${C_BOLD}${C_GREEN}" "${C_RESET}" "${C_DIM}" "${C_RESET}" >&2
