#!/usr/bin/env bash
#
# install.sh — interactive launcher for wanforge server scripts.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/install.sh | bash
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
  C_RED="\033[38;5;196m"; C_GREEN="\033[38;5;46m"; C_YELLOW="\033[38;5;226m"; C_CYAN="\033[38;5;45m"
  USE_COLOR=1
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""
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
  # single-hue gradients (light -> dark, one tone); one picked at random each run
  local themes=(
    "51 50 44 38 37 31"     # cyan
    "45 39 33 32 26 21"     # blue
    "48 42 36 35 29 28"     # green
    "141 135 134 98 92 91"  # purple
    "218 212 211 205 199 198" # pink
    "215 214 208 202 173 166" # orange
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
  printf "%b        wanforge.asia • MIT © 2026 Sugeng Sulistiyawan%b\n\n" "${C_DIM}" "${C_RESET}" >&2
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

# --- config: source repo -------------------------------------------------
REPO_OWNER="wanforge"
REPO_NAME="wanforge"
REPO_BRANCH="master"

# Script registry — add new scripts here as: "label|path-in-repo|description"
SCRIPTS=(
  "install-packages|.shell/install-packages.sh|Update system + install base packages (multi-distro)"
  "set-timezone|.shell/set-timezone.sh|Set timezone (default Asia/Jakarta)"
  "install-firewall|.shell/install-firewall.sh|Install & configure ufw firewall"
  "install-fail2ban|.shell/install-fail2ban.sh|Install & enable Fail2Ban"
  "install-cloudpanel|.shell/install-cloudpanel.sh|Install CloudPanel CE v2 (Debian/Ubuntu only)"
  "install-cockpit|.shell/install-cockpit.sh|Install Cockpit web console + modules (Debian/Ubuntu)"
  "install-postgresql|.shell/install-postgresql.sh|Install PostgreSQL + create roles + remote access"
  "enable-mysql-remote|.shell/enable-mysql-remote.sh|Allow remote MySQL/MariaDB access (sensitive)"
  "install-nodejs|.shell/install-nodejs.sh|Install Node.js via nvm (user-local) + PM2"
  "install-composer|.shell/install-composer.sh|Install Composer (user-local, signature-verified)"
  "secure-ssh|.shell/secure-ssh.sh|Harden SSH: change port, disable root/password, pubkey"
)
# ------------------------------------------------------------------------

# When run via `curl | bash`, stdin is the pipe, so read from the terminal.
if [ -e /dev/tty ]; then
  exec 3</dev/tty
else
  echo "No TTY available; cannot prompt interactively." >&2
  exit 1
fi

# --- checkbox multi-select menu ------------------------------------------
# Populates the global array SELECTED with chosen indices. ↑/↓ move,
# SPACE toggle, A toggle-all, ENTER confirm, Q quit.
SELECTED=()
checkbox_menu() {
  local n=${#SCRIPTS[@]} i cursor=0 first=1 key rest
  local -a checked
  for ((i = 0; i < n; i++)); do checked[i]=0; done

  printf "%bSelect scripts to run:%b  %b↑/↓ move · SPACE toggle · A all · ENTER run · Q quit%b\n\n" \
    "${C_BOLD}" "${C_RESET}" "${C_DIM}" "${C_RESET}" >&2

  while true; do
    [ "$first" -eq 0 ] && printf "\033[%dA" "$n" >&2
    first=0
    for ((i = 0; i < n; i++)); do
      IFS='|' read -r lbl _ dsc <<< "${SCRIPTS[i]}"
      local box="[ ]"; [ "${checked[i]}" -eq 1 ] && box="[x]"
      printf "\033[2K" >&2
      if [ "$i" -eq "$cursor" ]; then
        printf "%b❯ %s %-20s%b %b%s%b\n" "${C_CYAN}${C_BOLD}" "$box" "$lbl" "${C_RESET}" "${C_DIM}" "$dsc" "${C_RESET}" >&2
      else
        printf "  %b%s%b %-20s %b%s%b\n" "${C_GREEN}" "$box" "${C_RESET}" "$lbl" "${C_DIM}" "$dsc" "${C_RESET}" >&2
      fi
    done

    IFS= read -rsn1 key <&3 || break
    if [ "$key" = $'\x1b' ]; then IFS= read -rsn2 -t 0.01 rest <&3 || rest=""; key+="$rest"; fi
    case "$key" in
      $'\x1b[A'|k) cursor=$(( (cursor - 1 + n) % n )) ;;
      $'\x1b[B'|j) cursor=$(( (cursor + 1) % n )) ;;
      ' ') checked[cursor]=$(( 1 - checked[cursor] )) ;;
      a|A)
        local all=1; for ((i = 0; i < n; i++)); do [ "${checked[i]}" -eq 0 ] && all=0; done
        for ((i = 0; i < n; i++)); do checked[i]=$(( 1 - all )); done ;;
      q|Q) SELECTED=(); return 1 ;;
      '') break ;;  # Enter
    esac
  done

  for ((i = 0; i < n; i++)); do [ "${checked[i]}" -eq 1 ] && SELECTED+=("$i"); done
}

banner
checkbox_menu || { printf "\n%bCancelled.%b\n" "${C_YELLOW}" "${C_RESET}" >&2; exit 0; }

if [ "${#SELECTED[@]}" -eq 0 ]; then
  printf "\n%bNothing selected.%b\n" "${C_YELLOW}" "${C_RESET}" >&2
  exit 0
fi

printf "\n%bSelected %d script(s).%b\n\n" "${C_GREEN}" "${#SELECTED[@]}" "${C_RESET}" >&2

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

# --- fetch + run each selected script, in menu order ---------------------
TMP_SCRIPT="$(mktemp)"
trap 'rm -f "${TMP_SCRIPT}"' EXIT

for sel in "${SELECTED[@]}"; do
  IFS='|' read -r SEL_LABEL SCRIPT_PATH _ <<< "${SCRIPTS[$sel]}"
  RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${SCRIPT_PATH}"

  curl -fsSL "${AUTH[@]}" "${RAW_URL}" -o "${TMP_SCRIPT}" &
  spinner $! "Fetching ${SEL_LABEL}"
  wait $! || { echo "Download failed: ${SCRIPT_PATH} (check token / repo)." >&2; exit 1; }

  printf "%b▶ running %s...%b\n" "${C_BOLD}${C_GREEN}" "${SEL_LABEL}" "${C_RESET}" >&2
  bash "${TMP_SCRIPT}" || { err_msg="${SEL_LABEL} exited non-zero"; printf "%b✖ %s%b\n" "${C_BOLD}" "${err_msg}" "${C_RESET}" >&2; }
done

printf "\n%b✔ All selected scripts finished.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
