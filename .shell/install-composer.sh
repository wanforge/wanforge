#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-composer.sh — install Composer into ~/.local/bin (no sudo),
# verify the installer signature, then run composer self-update.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/install-composer.sh | bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="install-composer"

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

# ---- run ----------------------------------------------------------------
banner
command -v php >/dev/null 2>&1 || { err "PHP is required for Composer. Install PHP first."; exit 1; }

BIN_DIR="${HOME}/.local/bin"
mkdir -p "${BIN_DIR}"
TMP_DIR="$(mktemp -d)"; trap 'rm -rf "${TMP_DIR}"' EXIT
cd "${TMP_DIR}"

info "Downloading Composer installer..."
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"

info "Verifying installer signature..."
EXPECTED="$(curl -fsSL https://composer.github.io/installer.sig)"
ACTUAL="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
if [ "${EXPECTED}" != "${ACTUAL}" ]; then
  err "Installer signature mismatch — refusing to run untrusted installer."
  info "expected: ${EXPECTED}"
  info "actual:   ${ACTUAL}"
  exit 1
fi
ok "Signature verified."

info "Installing composer to ${BIN_DIR}/composer ..."
php composer-setup.php --quiet --install-dir="${BIN_DIR}" --filename=composer
export PATH="${BIN_DIR}:${PATH}"

# ensure ~/.local/bin is on PATH for future shells
if ! grep -qs 'HOME/.local/bin' "${HOME}/.bashrc" 2>/dev/null; then
  printf '\n# add user-local bin to PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "${HOME}/.bashrc"
  info "Added ~/.local/bin to PATH in ~/.bashrc"
fi

info "Running composer self-update..."
composer self-update || warn "self-update failed (offline or already latest)."

ok "$(composer --version 2>/dev/null || echo 'composer installed')"
printf "\n%b✔ Composer ready.%b  %bopen a new shell or run: source ~/.bashrc%b\n\n" \
  "${C_BOLD}${C_GREEN}" "${C_RESET}" "${C_DIM}" "${C_RESET}" >&2
