#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# setup-pm2-app.sh — configure pm2-logrotate and register an application with
# PM2 by generating an ecosystem.config.js, then start + save (no sudo).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/setup-pm2-app.sh | bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="setup-pm2-app"

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

# make pm2 (installed via nvm) available in this shell
export NVM_DIR="${HOME}/.nvm"
# shellcheck disable=SC1091
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh" && nvm use default >/dev/null 2>&1 || true
if ! command -v pm2 >/dev/null 2>&1; then
  err "pm2 not found. Run install-nodejs.sh first (it installs Node + PM2)."
  exit 1
fi
info "Using $(pm2 -v 2>/dev/null && echo "pm2 $(pm2 -v)" || echo pm2)"

# ---- pm2-logrotate config (optional) ------------------------------------
LR_ANS="$(ask "Configure pm2-logrotate (size/retention/compress)? [Y/n]:" "y")"
case "${LR_ANS}" in
  n|N|no) info "Skipped logrotate config." ;;
  *)
    pm2 install pm2-logrotate >/dev/null 2>&1 || true
    MAXSIZE="$(ask "Max log size before rotate:" "10M")"
    RETAIN="$(ask "Number of rotated files to keep:" "30")"
    COMPRESS="$(ask "Compress rotated logs? [Y/n]:" "y")"
    [[ "${COMPRESS}" =~ ^(n|N|no)$ ]] && COMPRESS="false" || COMPRESS="true"
    pm2 set pm2-logrotate:max_size "${MAXSIZE}"
    pm2 set pm2-logrotate:retain "${RETAIN}"
    pm2 set pm2-logrotate:compress "${COMPRESS}"
    pm2 set pm2-logrotate:rotateInterval '0 0 * * *'
    ok "pm2-logrotate: max_size=${MAXSIZE}, retain=${RETAIN}, compress=${COMPRESS}"
    ;;
esac

# ---- define an application ----------------------------------------------
APP_ANS="$(ask "Register an application now? [Y/n]:" "y")"
case "${APP_ANS}" in
  n|N|no) info "No app registered."; pm2 save || true; exit 0 ;;
esac

APP_NAME="$(ask "App name:" "my-app")"
APP_CWD="$(ask "Working directory (project path):" "$(pwd)")"
if [ ! -d "${APP_CWD}" ]; then err "Directory not found: ${APP_CWD}"; exit 1; fi
APP_SCRIPT="$(ask "Entry script or command (e.g. app.js, dist/main.js, npm):" "app.js")"
APP_ARGS="$(ask "Arguments (e.g. 'run start' for npm, empty otherwise):" "")"
APP_INSTANCES="$(ask "Instances (1, a number, or 'max' for cluster):" "1")"
if [ "${APP_INSTANCES}" = "1" ]; then EXEC_MODE="fork"; else EXEC_MODE="cluster"; fi
APP_NODE_ENV="$(ask "NODE_ENV:" "production")"
APP_MEM="$(ask "Restart if memory exceeds:" "300M")"

ECOSYS="${APP_CWD}/ecosystem.config.js"
if [ -f "${ECOSYS}" ]; then
  OVERWRITE="$(ask "${ECOSYS} exists. Overwrite? [y/N]:" "n")"
  [[ "${OVERWRITE}" =~ ^(y|Y|yes)$ ]] || { err "Aborted to avoid overwriting."; exit 1; }
fi

# normalise instances value for JS (quote 'max', keep numbers bare)
if [ "${APP_INSTANCES}" = "max" ]; then INST_JS='"max"'; else INST_JS="${APP_INSTANCES}"; fi
# args line only if provided
ARGS_LINE=""
[ -n "${APP_ARGS}" ] && ARGS_LINE="    args: \"${APP_ARGS}\","

cat > "${ECOSYS}" <<EOF
// Generated by wanforge.asia setup-pm2-app.sh
module.exports = {
  apps: [
    {
      name: "${APP_NAME}",
      cwd: "${APP_CWD}",
      script: "${APP_SCRIPT}",
${ARGS_LINE}
      instances: ${INST_JS},
      exec_mode: "${EXEC_MODE}",
      autorestart: true,
      max_memory_restart: "${APP_MEM}",
      env: {
        NODE_ENV: "${APP_NODE_ENV}"
      }
    }
  ]
};
EOF
ok "Wrote ${ECOSYS}"

info "Starting app with PM2..."
pm2 start "${ECOSYS}" --update-env
pm2 save
ok "Saved PM2 process list."
pm2 list || true

printf "\n%b✔ PM2 app configured.%b\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
printf "%b  Manage: pm2 status · pm2 logs %s · pm2 restart %s%b\n\n" "${C_DIM}" "${APP_NAME}" "${APP_NAME}" "${C_RESET}" >&2
