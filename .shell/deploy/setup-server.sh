#!/usr/bin/env bash
# shellcheck disable=SC2086  # package lists are intentionally word-split
#
# setup-server.sh — multi-distro Linux server setup.
# Auto-detects the package manager: apt, dnf, yum, pacman, zypper, apk.
#
# Usage (public repo, no auth needed):
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/deploy/setup-server.sh | bash
#
set -euo pipefail

# --- privilege helper ----------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

# --- detect package manager ---------------------------------------------
detect_pm() {
  for pm in apt-get dnf yum pacman zypper apk; do
    if command -v "$pm" >/dev/null 2>&1; then
      echo "$pm"
      return 0
    fi
  done
  return 1
}

PM="$(detect_pm)" || { echo "No supported package manager found." >&2; exit 1; }
echo ">> Detected package manager: ${PM}"

# --- per-manager commands + package names -------------------------------
case "${PM}" in
  apt-get)
    PKGS="micro curl wget git speedtest-cli python3 python3-pip python3-dev python3-virtualenv"
    ${SUDO} apt-get update
    ${SUDO} apt-get upgrade -y
    ${SUDO} apt-get install -y ${PKGS}
    ${SUDO} apt-get autoremove -y
    ${SUDO} apt-get autoclean
    ;;
  dnf)
    PKGS="micro curl wget git speedtest-cli python3 python3-pip python3-devel python3-virtualenv"
    ${SUDO} dnf -y upgrade --refresh
    ${SUDO} dnf -y install ${PKGS}
    ${SUDO} dnf -y autoremove
    ${SUDO} dnf clean all
    ;;
  yum)
    PKGS="micro curl wget git python3 python3-pip python3-devel"
    ${SUDO} yum -y update
    ${SUDO} yum -y install ${PKGS}
    ${SUDO} yum -y autoremove || true
    ${SUDO} yum clean all
    ;;
  pacman)
    PKGS="micro curl wget git python python-pip python-virtualenv speedtest-cli"
    ${SUDO} pacman -Syu --noconfirm
    ${SUDO} pacman -S --noconfirm --needed ${PKGS}
    # remove orphaned deps (ignore if none)
    ${SUDO} pacman -Qtdq 2>/dev/null | ${SUDO} pacman -Rns --noconfirm - 2>/dev/null || true
    ;;
  zypper)
    PKGS="micro curl wget git python3 python3-pip python3-devel python3-virtualenv"
    ${SUDO} zypper --non-interactive refresh
    ${SUDO} zypper --non-interactive update
    ${SUDO} zypper --non-interactive install ${PKGS}
    ${SUDO} zypper clean --all
    ;;
  apk)
    PKGS="micro curl wget git python3 py3-pip python3-dev py3-virtualenv"
    ${SUDO} apk update
    ${SUDO} apk upgrade
    ${SUDO} apk add ${PKGS}
    ;;
  *)
    echo "Unsupported package manager: ${PM}" >&2
    exit 1
    ;;
esac

# --- speedtest-cli fallback via pip (distros lacking the package) -------
if ! command -v speedtest-cli >/dev/null 2>&1; then
  if command -v pip3 >/dev/null 2>&1; then
    echo ">> Installing speedtest-cli via pip3"
    pip3 install --user speedtest-cli || true
  fi
fi

echo ">> Setup complete."
