#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-packages.sh — update system & install base packages (multi-distro).
# Package managers: apt, dnf, yum, pacman, zypper, apk.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/deploy/install-packages.sh | bash
#
# SPDX-License-Identifier: MIT
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
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
detect_pm() { for pm in apt-get dnf yum pacman zypper apk; do command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return 0; }; done; return 1; }

# ---- package-manager wrappers ------------------------------------------
pm_update() {
  case "${PM}" in
    apt-get) ${SUDO} apt-get update ;; dnf) ${SUDO} dnf -y makecache ;; yum) ${SUDO} yum -y makecache ;;
    pacman) ${SUDO} pacman -Sy --noconfirm ;; zypper) ${SUDO} zypper --non-interactive refresh ;; apk) ${SUDO} apk update ;;
  esac
}
pm_upgrade() {
  case "${PM}" in
    apt-get) ${SUDO} apt-get upgrade -y ;; dnf) ${SUDO} dnf -y upgrade --refresh ;; yum) ${SUDO} yum -y update ;;
    pacman) ${SUDO} pacman -Su --noconfirm ;; zypper) ${SUDO} zypper --non-interactive update ;; apk) ${SUDO} apk upgrade ;;
  esac
}
pm_install() {
  local pkgs="$*"
  case "${PM}" in
    apt-get) ${SUDO} apt-get install -y ${pkgs} ;; dnf) ${SUDO} dnf -y install ${pkgs} ;; yum) ${SUDO} yum -y install ${pkgs} ;;
    pacman) ${SUDO} pacman -S --noconfirm --needed ${pkgs} ;; zypper) ${SUDO} zypper --non-interactive install ${pkgs} ;; apk) ${SUDO} apk add ${pkgs} ;;
  esac
}
pm_cleanup() {
  case "${PM}" in
    apt-get) ${SUDO} apt-get autoremove -y; ${SUDO} apt-get autoclean ;;
    dnf) ${SUDO} dnf -y autoremove; ${SUDO} dnf clean all ;;
    yum) ${SUDO} yum -y autoremove || true; ${SUDO} yum clean all ;;
    pacman) ${SUDO} pacman -Qtdq 2>/dev/null | ${SUDO} pacman -Rns --noconfirm - 2>/dev/null || true ;;
    zypper) ${SUDO} zypper clean --all ;; apk) : ;;
  esac
}
base_pkgs() {
  case "${PM}" in
    apt-get) echo "micro curl wget git speedtest-cli python3 python3-pip python3-dev python3-virtualenv" ;;
    dnf) echo "micro curl wget git speedtest-cli python3 python3-pip python3-devel python3-virtualenv" ;;
    yum) echo "micro curl wget git python3 python3-pip python3-devel" ;;
    pacman) echo "micro curl wget git python python-pip python-virtualenv speedtest-cli" ;;
    zypper) echo "micro curl wget git python3 python3-pip python3-devel python3-virtualenv" ;;
    apk) echo "micro curl wget git python3 py3-pip python3-dev py3-virtualenv" ;;
  esac
}

# ---- run ----------------------------------------------------------------
banner
PM="$(detect_pm)" || { err "No supported package manager found."; exit 1; }
info "Package manager: ${C_BOLD}${PM}${C_RESET}"
info "Refreshing package index..."; pm_update
info "Upgrading installed packages..."; pm_upgrade
PKGS="$(base_pkgs)"; info "Installing: ${PKGS}"; pm_install ${PKGS}
info "Cleaning up..."; pm_cleanup
if ! command -v speedtest-cli >/dev/null 2>&1 && command -v pip3 >/dev/null 2>&1; then
  info "speedtest-cli missing from repo; installing via pip3"
  pip3 install --user speedtest-cli >/dev/null 2>&1 || true
fi
printf "\n%b✔ Packages ready.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
