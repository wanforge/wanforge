#!/usr/bin/env bash
#
# bootstrap.sh — interactive loader for a PRIVATE GitHub deploy script.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/<branch>/.shell/deploy/bootstrap.sh | bash
#
# It prompts for GitHub username + token (PAT), then fetches and runs
# setup-server.sh from the private repo.
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
  # vertical gradient: cyan -> blue -> violet -> magenta
  local grad=(51 45 39 99 135 171)
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
  printf "%b        ⚡ server bootstrap • github private deploy%b\n\n" "${C_DIM}" "${C_RESET}" >&2
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

# --- config: points at the public wanforge repo --------------------------
REPO_OWNER="wanforge"
REPO_NAME="wanforge"
REPO_BRANCH="master"
SCRIPT_PATH=".shell/deploy/setup-server.sh"
# ------------------------------------------------------------------------

# When run via `curl | bash`, stdin is the pipe, so read from the terminal.
if [ -e /dev/tty ]; then
  exec 3</dev/tty
else
  echo "No TTY available; cannot prompt interactively." >&2
  exit 1
fi

PAT_URL="https://github.com/settings/tokens/new?scopes=repo&description=server-bootstrap"
printf "%bGenerate a token (PAT) here:%b\n  %b%s%b\n\n" \
  "${C_DIM}" "${C_RESET}" "${C_YELLOW}" "${PAT_URL}" "${C_RESET}" >&2

printf "GitHub username: " >&2
read -r GH_USER <&3

printf "GitHub token (PAT, hidden): " >&2
read -rs GH_TOKEN <&3
printf "\n" >&2

if [ -z "${GH_USER}" ] || [ -z "${GH_TOKEN}" ]; then
  echo "Username and token are required." >&2
  exit 1
fi

RAW_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${SCRIPT_PATH}"

TMP_SCRIPT="$(mktemp)"
trap 'rm -f "${TMP_SCRIPT}"' EXIT

curl -fsSL -u "${GH_USER}:${GH_TOKEN}" "${RAW_URL}" -o "${TMP_SCRIPT}" &
spinner $! "Fetching ${SCRIPT_PATH}"
wait $! || { echo "Download failed (check username/token/repo)." >&2; exit 1; }

printf "%b▶ running setup...%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
bash "${TMP_SCRIPT}"
