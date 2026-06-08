#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-packages.sh — update system & install base packages (multi-distro),
# with a grouped checkbox menu to pick exactly which actions/packages to run.
# Package managers: apt, dnf, yum, pacman, zypper, apk.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/install-packages.sh | bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="install-packages"

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
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# ---- generic checkbox menu (items: "group|key|description"; default ON) --
# Sets global CHOSEN_KEYS to the selected keys. ↑/↓ move, SPACE toggle,
# A toggle-all, ENTER confirm, Q quit.
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
        printf "%b❯ %s %-20s%b %b%s%b\n" "${C_CYAN}${C_BOLD}" "$box" "$lbl" "${C_RESET}" "${C_DIM}" "$dsc" "${C_RESET}" >&2
      else
        printf "  %b%s%b %-20s %b%s%b\n" "${C_GREEN}" "$box" "${C_RESET}" "$lbl" "${C_DIM}" "$dsc" "${C_RESET}" >&2
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

# ---- package manager ----------------------------------------------------
detect_pm() { for pm in apt-get dnf yum pacman zypper apk; do command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return 0; }; done; return 1; }
PM="$(detect_pm)" || { err "No supported package manager found."; exit 1; }

pm_update()  { case "${PM}" in apt-get) ${SUDO} apt-get update ;; dnf) ${SUDO} dnf -y makecache ;; yum) ${SUDO} yum -y makecache ;; pacman) ${SUDO} pacman -Sy --noconfirm ;; zypper) ${SUDO} zypper --non-interactive refresh ;; apk) ${SUDO} apk update ;; esac; }
pm_upgrade() { case "${PM}" in apt-get) ${SUDO} apt-get upgrade -y ;; dnf) ${SUDO} dnf -y upgrade --refresh ;; yum) ${SUDO} yum -y update ;; pacman) ${SUDO} pacman -Su --noconfirm ;; zypper) ${SUDO} zypper --non-interactive update ;; apk) ${SUDO} apk upgrade ;; esac; }
pm_install() { local pkgs="$*"; [ -z "$pkgs" ] && return 0; case "${PM}" in apt-get) ${SUDO} apt-get install -y ${pkgs} ;; dnf) ${SUDO} dnf -y install ${pkgs} ;; yum) ${SUDO} yum -y install ${pkgs} ;; pacman) ${SUDO} pacman -S --noconfirm --needed ${pkgs} ;; zypper) ${SUDO} zypper --non-interactive install ${pkgs} ;; apk) ${SUDO} apk add ${pkgs} ;; esac; }
pm_cleanup() { case "${PM}" in apt-get) ${SUDO} apt-get autoremove -y; ${SUDO} apt-get autoclean ;; dnf) ${SUDO} dnf -y autoremove; ${SUDO} dnf clean all ;; yum) ${SUDO} yum -y autoremove || true; ${SUDO} yum clean all ;; pacman) ${SUDO} pacman -Qtdq 2>/dev/null | ${SUDO} pacman -Rns --noconfirm - 2>/dev/null || true ;; zypper) ${SUDO} zypper clean --all ;; apk) : ;; esac; }

# resolve a logical package key to the distro package name (empty = skip)
pkg_name() {
  case "$1" in
    micro|curl|wget|git) echo "$1" ;;
    speedtest-cli) case "${PM}" in apk) echo "" ;; *) echo speedtest-cli ;; esac ;;
    python3) case "${PM}" in pacman) echo python ;; *) echo python3 ;; esac ;;
    pip) case "${PM}" in apt-get|dnf|yum|zypper) echo python3-pip ;; pacman) echo python-pip ;; apk) echo py3-pip ;; esac ;;
    dev) case "${PM}" in apt-get|apk) echo python3-dev ;; dnf|yum|zypper) echo python3-devel ;; pacman) echo "" ;; esac ;;
    venv) case "${PM}" in apt-get|dnf|yum|zypper) echo python3-virtualenv ;; pacman) echo python-virtualenv ;; apk) echo py3-virtualenv ;; esac ;;
  esac
}

# ---- menu ---------------------------------------------------------------
MENU=(
  "System|update|Refresh package index"
  "System|upgrade|Upgrade installed packages"
  "System|cleanup|Autoremove + clean cache"
  "Editor|micro|Modern terminal text editor"
  "Network|curl|Transfer data / fetch URLs"
  "Network|wget|Download files over HTTP/FTP"
  "VCS|git|Distributed version control"
  "Diagnostics|speedtest-cli|Internet speed test (CLI)"
  "Python|python3|Python 3 interpreter"
  "Python|pip|Python package manager (pip)"
  "Python|dev|Python headers for building modules"
  "Python|venv|Isolated Python environments (virtualenv)"
)

# ---- run ----------------------------------------------------------------
banner
info "Package manager: ${C_BOLD}${PM}${C_RESET}"
checkbox "Select actions & packages to install:" || { warn "Cancelled."; exit 0; }
[ "${#CHOSEN_KEYS[@]}" -eq 0 ] && { warn "Nothing selected."; exit 0; }

has_key update  && { info "Refreshing package index..."; pm_update; }
has_key upgrade && { info "Upgrading installed packages..."; pm_upgrade; }

# collect selected packages (resolved per distro)
PKGS=""
for key in micro curl wget git speedtest-cli python3 pip dev venv; do
  if has_key "$key"; then p="$(pkg_name "$key")"; [ -n "$p" ] && PKGS="${PKGS} ${p}"; fi
done
if [ -n "${PKGS# }" ]; then info "Installing:${PKGS}"; pm_install ${PKGS}; fi

# speedtest-cli pip fallback where the package is unavailable
if has_key speedtest-cli && ! command -v speedtest-cli >/dev/null 2>&1 && command -v pip3 >/dev/null 2>&1; then
  info "speedtest-cli not in repo; installing via pip3"; pip3 install --user speedtest-cli >/dev/null 2>&1 || true
fi

has_key cleanup && { info "Cleaning up..."; pm_cleanup; }

printf "\n%b✔ Packages ready.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
