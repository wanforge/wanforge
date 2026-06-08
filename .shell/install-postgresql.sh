#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install-postgresql.sh — install PostgreSQL, create login roles (interactive,
# no hardcoded secrets), optionally enable remote access.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/install-postgresql.sh | bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="install-postgresql"

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
asks() { local prompt="$1" ans; printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${prompt}" >&2; read -rs ans <&3 || ans=""; printf "\n" >&2; echo "${ans}"; }
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
psql_super() { ${SUDO} -u postgres psql -v ON_ERROR_STOP=1 "$@"; }

# ---- run ----------------------------------------------------------------
banner
if ! command -v apt-get >/dev/null 2>&1; then err "This script targets Debian/Ubuntu (apt)."; exit 1; fi

# Add the official PostgreSQL APT repository (PGDG) to get the latest version.
add_pgdg_repo() {
  info "Configuring PGDG repository for the latest PostgreSQL..."
  ${SUDO} apt-get install -y curl ca-certificates gnupg
  ${SUDO} install -d /usr/share/postgresql-common/pgdg
  ${SUDO} curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
    https://www.postgresql.org/media/keys/ACCC4CF8.asc
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
    | ${SUDO} tee /etc/apt/sources.list.d/pgdg.list >/dev/null
}

info "Installing the latest PostgreSQL..."
if add_pgdg_repo; then
  ${SUDO} apt-get update
else
  warn "PGDG repo setup failed; falling back to the distro package."
  ${SUDO} apt-get update
fi
# 'postgresql' meta-package pulls the newest available major version.
${SUDO} apt-get install -y postgresql postgresql-contrib
${SUDO} systemctl enable postgresql >/dev/null 2>&1 || true
${SUDO} systemctl start postgresql || true
PG_VER="$(${SUDO} -u postgres psql -tAc 'SHOW server_version;' 2>/dev/null || echo '?')"
ok "PostgreSQL ${PG_VER} installed and running."

# ---- create login roles (interactive, no hardcoded secrets) -------------
info "Create login roles. Passwords are entered interactively, never stored in this script."
while true; do
  ADD="$(ask "Create a database role now? [y/N]:" "n")"
  case "${ADD}" in y|Y|yes) ;; *) break ;; esac

  ROLE="$(ask "Role name:" "")"
  if ! [[ "${ROLE}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    warn "Invalid role name (use letters, digits, underscore; must not start with a digit)."; continue
  fi
  PW1="$(asks "Password for ${ROLE}:")"
  PW2="$(asks "Confirm password:")"
  if [ -z "${PW1}" ] || [ "${PW1}" != "${PW2}" ]; then warn "Empty or mismatched password; skipping."; continue; fi

  SUPER="$(ask "Grant SUPERUSER? (powerful, default no) [y/N]:" "n")"
  PRIV="LOGIN CREATEDB CREATEROLE"
  case "${SUPER}" in y|Y|yes) PRIV="SUPERUSER ${PRIV}"; warn "Granting SUPERUSER to ${ROLE}." ;; esac

  # escape single quotes in the password for the SQL string literal
  PW_ESC="${PW1//\'/\'\'}"
  if psql_super -c "CREATE ROLE \"${ROLE}\" WITH ${PRIV} PASSWORD '${PW_ESC}';" 2>/dev/null; then
    ok "Created role ${ROLE} (${PRIV})."
  else
    warn "Could not create ${ROLE} (already exists?). Trying to update password..."
    psql_super -c "ALTER ROLE \"${ROLE}\" WITH ${PRIV} PASSWORD '${PW_ESC}';" && ok "Updated role ${ROLE}." || err "Failed for ${ROLE}."
  fi
  unset PW1 PW2 PW_ESC
done

# ---- remote access (optional, security-sensitive) -----------------------
REMOTE="$(ask "Enable remote access (network listen + pg_hba)? [y/N]:" "n")"
case "${REMOTE}" in
  y|Y|yes)
    warn "Exposing PostgreSQL to the network. Restrict the source range whenever possible."
    CIDR="$(ask "Allowed source CIDR (e.g. 10.0.0.0/8; '0.0.0.0/0'=anywhere, NOT recommended):" "0.0.0.0/0")"
    PG_HBA="$(psql_super -tAc 'SHOW hba_file;')"
    PG_CONF="$(psql_super -tAc 'SHOW config_file;')"
    info "hba_file:    ${PG_HBA}"
    info "config_file: ${PG_CONF}"

    HBA_LINE="host    all             all             ${CIDR}            scram-sha-256"
    if ${SUDO} grep -qF "${CIDR}" "${PG_HBA}"; then
      info "pg_hba already has a rule for ${CIDR}."
    else
      echo "${HBA_LINE}" | ${SUDO} tee -a "${PG_HBA}" >/dev/null
      ok "Appended pg_hba rule for ${CIDR}."
    fi

    if ${SUDO} grep -qE "^[#[:space:]]*listen_addresses" "${PG_CONF}"; then
      ${SUDO} sed -i "s|^[#[:space:]]*listen_addresses.*|listen_addresses = '*'|" "${PG_CONF}"
    else
      echo "listen_addresses = '*'" | ${SUDO} tee -a "${PG_CONF}" >/dev/null
    fi
    ok "Set listen_addresses = '*'."

    ${SUDO} systemctl restart postgresql && ok "PostgreSQL restarted."

    if command -v ufw >/dev/null 2>&1; then
      if [ "${CIDR}" = "0.0.0.0/0" ]; then ${SUDO} ufw allow 5432/tcp
      else ${SUDO} ufw allow from "${CIDR}" to any port 5432 proto tcp; fi
      ok "Firewall: allowed 5432/tcp from ${CIDR}."
    else
      info "ufw not installed; open port 5432 manually if needed."
    fi
    ;;
  *) info "Remote access left disabled (local only)." ;;
esac

printf "\n%b✔ PostgreSQL setup complete.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
