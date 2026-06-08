#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# generate-ssh-key.sh — generate an ed25519 SSH key in the user's ~/.ssh
# (no sudo), fix permissions, and print the public key for GitHub/GitLab.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/generate-ssh-key.sh | bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="generate-ssh-key"

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
ask()  { local p="$1" d="${2:-}" a; printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${p}" >&2; read -r a <&3 || a=""; echo "${a:-$d}"; }
asks() { local p="$1" a; printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${p}" >&2; read -rs a <&3 || a=""; printf "\n" >&2; echo "${a}"; }

# ---- run ----------------------------------------------------------------
banner
command -v ssh-keygen >/dev/null 2>&1 || { err "ssh-keygen not found. Install openssh-client first."; exit 1; }

KEYFILE="$(ask "Key file path:" "${HOME}/.ssh/id_ed25519")"
COMMENT="$(ask "Key comment:" "wanforge-asia@$(hostname 2>/dev/null || echo wanforge-app)")"

# passphrase (optional)
PASS=""
PP_ANS="$(ask "Protect the key with a passphrase? [y/N]:" "n")"
if [[ "${PP_ANS}" =~ ^(y|Y|yes)$ ]]; then
  P1="$(asks 'Passphrase:')"; P2="$(asks 'Confirm passphrase:')"
  if [ "${P1}" != "${P2}" ]; then err "Passphrases do not match."; exit 1; fi
  PASS="${P1}"; unset P1 P2
fi

mkdir -p "$(dirname "${KEYFILE}")"

# do not silently overwrite an existing key
if [ -e "${KEYFILE}" ]; then
  OW="$(ask "${KEYFILE} exists. Overwrite? [y/N]:" "n")"
  [[ "${OW}" =~ ^(y|Y|yes)$ ]] || { err "Aborted to avoid overwriting the existing key."; exit 1; }
  rm -f "${KEYFILE}" "${KEYFILE}.pub"
fi

info "Generating ed25519 key..."
ssh-keygen -t ed25519 -f "${KEYFILE}" -N "${PASS}" -C "${COMMENT}"

# permissions
chmod 700 "$(dirname "${KEYFILE}")"
chmod 600 "${KEYFILE}"
chmod 644 "${KEYFILE}.pub"
ok "Key generated: ${KEYFILE}"

# fingerprint + public key
info "Fingerprint:"; ssh-keygen -lf "${KEYFILE}.pub" >&2 || true

printf "\n%bPublic key (add to GitHub/GitLab → Settings → Deploy Keys / SSH Keys):%b\n\n" "${C_BOLD}" "${C_RESET}" >&2
printf "%b" "${C_CYAN}" >&2; cat "${KEYFILE}.pub" >&2; printf "%b\n" "${C_RESET}" >&2

printf "\n%b✔ Done.%b  %bTip: eval \"\$(ssh-agent -s)\" && ssh-add %s%b\n\n" \
  "${C_BOLD}${C_GREEN}" "${C_RESET}" "${C_DIM}" "${KEYFILE}" "${C_RESET}" >&2
