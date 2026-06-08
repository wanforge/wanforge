#!/usr/bin/env bash
#
# bootstrap.sh — interactive launcher for wanforge deploy scripts.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/deploy/bootstrap.sh | bash
#
# Shows a menu of available scripts, then fetches and runs the chosen one.
# Auth (username + PAT) is OPTIONAL — only needed for scripts in private repos.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail

# --- colors --------------------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"; C_DIM="\033[2m"
  C_GREEN="\033[38;5;46m"; C_YELLOW="\033[38;5;226m"
  USE_COLOR=1
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_GREEN=""; C_YELLOW=""
  USE_COLOR=0
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
  # preset gradient themes; one is picked at random each run
  local themes=(
    "51 45 39 99 135 171"   # cyan -> magenta
    "46 48 50 45 39 33"     # green -> blue
    "214 208 202 196 160 124" # orange -> red
    "93 99 135 171 207 213" # purple -> pink
    "226 220 214 208 202 196" # fire
    "51 45 39 33 27 21"     # ocean
    "196 208 226 46 51 93"  # rainbow
    "201 165 129 93 57 21"  # violet -> blue
  )
  local pick=$(( RANDOM % ${#themes[@]} ))
  read -r -a grad <<< "${themes[$pick]}"
  printf "\n" >&2
  local i=0
  for l in "${lines[@]}"; do
    if [ "${USE_COLOR}" -eq 1 ]; then
      printf "\033[1;38;5;%sm%s\033[0m\n" "${grad[$i]}" "$l" >&2
    else
      printf "%s\n" "$l" >&2
    fi
    i=$((i + 1))
    sleep 0.05
  done
  printf "%b        ⚡ wanforge deploy • MIT © 2026 Sugeng Sulistiyawan%b\n\n" "${C_DIM}" "${C_RESET}" >&2
}

spinner() {
  # spinner PID "message"
  local pid=$1 msg=$2
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#frames} ))
    printf "\r%b%s%b %s" "${C_YELLOW}" "${frames:$i:1}" "${C_RESET}" "$msg" >&2
    sleep 0.08
  done
  printf "\r%b✔%b %s\n" "${C_GREEN}" "${C_RESET}" "$msg" >&2
}

banner

# --- config: source repo -------------------------------------------------
REPO_OWNER="wanforge"
REPO_NAME="wanforge"
REPO_BRANCH="master"

# Script registry — add new scripts here as: "label|path-in-repo|description"
SCRIPTS=(
  "install-server|.shell/deploy/install-server.sh|Update system + base packages, timezone, firewall, fail2ban"
  "install-cloudpanel|.shell/deploy/install-cloudpanel.sh|Install CloudPanel CE v2 (Debian/Ubuntu only)"
)
# ------------------------------------------------------------------------

# When run via `curl | bash`, stdin is the pipe, so read from the terminal.
if [ -e /dev/tty ]; then
  exec 3</dev/tty
else
  echo "No TTY available; cannot prompt interactively." >&2
  exit 1
fi

# --- menu ----------------------------------------------------------------
printf "%bAvailable scripts:%b\n" "${C_BOLD}" "${C_RESET}" >&2
idx=1
for entry in "${SCRIPTS[@]}"; do
  IFS='|' read -r m_label _ m_desc <<< "${entry}"
  printf "  %b%d%b) %-16s %b%s%b\n" \
    "${C_YELLOW}" "${idx}" "${C_RESET}" "${m_label}" "${C_DIM}" "${m_desc}" "${C_RESET}" >&2
  idx=$((idx + 1))
done

printf "\nSelect [1-%d] (default 1): " "${#SCRIPTS[@]}" >&2
read -r CHOICE <&3
CHOICE="${CHOICE:-1}"

if ! [[ "${CHOICE}" =~ ^[0-9]+$ ]] || [ "${CHOICE}" -lt 1 ] || [ "${CHOICE}" -gt "${#SCRIPTS[@]}" ]; then
  echo "Invalid selection: ${CHOICE}" >&2
  exit 1
fi

IFS='|' read -r SEL_LABEL SCRIPT_PATH _ <<< "${SCRIPTS[$((CHOICE - 1))]}"
printf "\n%bSelected:%b %s\n\n" "${C_GREEN}" "${C_RESET}" "${SEL_LABEL}" >&2

# --- optional auth (private repos only) ----------------------------------
PAT_URL="https://github.com/settings/tokens/new?scopes=repo&description=wanforge-deploy"
printf "%bAuth is only needed for PRIVATE repos. Press Enter to skip.%b\n" "${C_DIM}" "${C_RESET}" >&2
printf "%bGenerate a token (PAT):%b %b%s%b\n" "${C_DIM}" "${C_RESET}" "${C_YELLOW}" "${PAT_URL}" "${C_RESET}" >&2

printf "GitHub username (Enter to skip): " >&2
read -r GH_USER <&3

AUTH=()
if [ -n "${GH_USER}" ]; then
  printf "GitHub token (PAT, hidden): " >&2
  read -rs GH_TOKEN <&3
  printf "\n" >&2
  if [ -z "${GH_TOKEN}" ]; then
    echo "Token required when username is given." >&2
    exit 1
  fi
  AUTH=(-u "${GH_USER}:${GH_TOKEN}")
fi

# --- fetch + run ---------------------------------------------------------
RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${SCRIPT_PATH}"

TMP_SCRIPT="$(mktemp)"
trap 'rm -f "${TMP_SCRIPT}"' EXIT

curl -fsSL "${AUTH[@]}" "${RAW_URL}" -o "${TMP_SCRIPT}" &
spinner $! "Fetching ${SCRIPT_PATH}"
wait $! || { echo "Download failed (check selection / token / repo)." >&2; exit 1; }

printf "%b▶ running %s...%b\n\n" "${C_BOLD}${C_GREEN}" "${SEL_LABEL}" "${C_RESET}" >&2
bash "${TMP_SCRIPT}"
