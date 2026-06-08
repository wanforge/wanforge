#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# clpctl-manager.sh — interactive wrapper around the CloudPanel CLI (clpctl).
# Covers the documented v2 commands: basic-auth, cloudflare, database,
# Let's Encrypt, sites, users, vhost-templates, permissions, varnish cache.
#
# Reference: https://www.cloudpanel.io/docs/v2/cloudpanel-cli/
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/wanforge/wanforge/master/.shell/clpctl-manager.sh | bash
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Sugeng Sulistiyawan
#
set -euo pipefail
TASK="clpctl-manager"

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
  printf "%b        wanforge.asia · %s • MIT © 2026 Sugeng Sulistiyawan%b\n\n" "${C_DIM}" "${TASK}" "${C_RESET}" >&2
}
info() { printf "    %b•%b %s\n" "${C_DIM}" "${C_RESET}" "$1" >&2; }
ok()   { printf "    %b✔%b %s\n" "${C_GREEN}" "${C_RESET}" "$1" >&2; }
warn() { printf "    %b!%b %s\n" "${C_YELLOW}" "${C_RESET}" "$1" >&2; }
err()  { printf "    %b✖%b %s\n" "${C_RED}" "${C_RESET}" "$1" >&2; }
if [ -e /dev/tty ]; then exec 3</dev/tty; else exec 3<&0; fi
ask()  { local p="$1" d="${2:-}" a; printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${p}" >&2; read -r a <&3 || a=""; echo "${a:-$d}"; }
asks() { local p="$1" a; printf "%b?%b %s " "${C_YELLOW}" "${C_RESET}" "${p}" >&2; read -rs a <&3 || a=""; printf "\n" >&2; echo "${a}"; }
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# run clpctl with args; never echoes secret values
runclp() {
  printf "\n%b▶ clpctl %s%b\n" "${C_BOLD}${C_CYAN}" "$1" "${C_RESET}" >&2
  if ${SUDO} clpctl "$@"; then ok "Done."; else err "Command failed."; fi
}
req() { # req VALUE NAME — abort action if empty
  [ -n "$1" ] || { err "$2 is required."; return 1; }
}

# ---- actions ------------------------------------------------------------
a_basic_auth_enable() { local u p; u="$(ask 'Username:')"; req "$u" username || return; p="$(asks 'Password:')"; req "$p" password || return; runclp cloudpanel:enable:basic-auth --userName="$u" --password="$p"; }
a_basic_auth_disable() { runclp cloudpanel:disable:basic-auth; }
a_cloudflare_ips() { runclp cloudflare:update:ips; }

a_db_master() { runclp db:show:master-credentials; }
a_db_add() { local d n u p; d="$(ask 'Domain (site):')"; n="$(ask 'Database name:')"; u="$(ask 'DB user name:')"; p="$(asks 'DB user password:')"; req "$d" domain || return; req "$n" db || return; req "$u" user || return; req "$p" pass || return; runclp db:add --domainName="$d" --databaseName="$n" --databaseUserName="$u" --databaseUserPassword="$p"; }
a_db_export() { local n f; n="$(ask 'Database name:')"; f="$(ask 'Output file:' 'dump.sql.gz')"; req "$n" db || return; runclp db:export --databaseName="$n" --file="$f"; }
a_db_import() { local n f; n="$(ask 'Database name:')"; f="$(ask 'Input file:' 'dump.sql.gz')"; req "$n" db || return; req "$f" file || return; runclp db:import --databaseName="$n" --file="$f"; }

a_le_cert() { local d s; d="$(ask 'Domain:')"; req "$d" domain || return; s="$(ask 'Subject Alternative Names (comma-sep, Enter to skip):')"; if [ -n "$s" ]; then runclp lets-encrypt:install:certificate --domainName="$d" --subjectAlternativeName="$s"; else runclp lets-encrypt:install:certificate --domainName="$d"; fi; }

a_site_php() { local d v t u p; d="$(ask 'Domain:')"; v="$(ask 'PHP version:' '8.4')"; t="$(ask 'vHost template:' 'Generic')"; u="$(ask 'Site user:')"; p="$(asks 'Site user password:')"; req "$d" domain || return; req "$u" user || return; req "$p" pass || return; runclp site:add:php --domainName="$d" --phpVersion="$v" --vhostTemplate="$t" --siteUser="$u" --siteUserPassword="$p"; }
a_site_nodejs() { local d v port u p; d="$(ask 'Domain:')"; v="$(ask 'Node.js version:' '22')"; port="$(ask 'App port:' '3000')"; u="$(ask 'Site user:')"; p="$(asks 'Site user password:')"; req "$d" domain || return; req "$u" user || return; req "$p" pass || return; runclp site:add:nodejs --domainName="$d" --nodejsVersion="$v" --appPort="$port" --siteUser="$u" --siteUserPassword="$p"; }
a_site_python() { local d v port u p; d="$(ask 'Domain:')"; v="$(ask 'Python version:' '3.11')"; port="$(ask 'App port:' '8080')"; u="$(ask 'Site user:')"; p="$(asks 'Site user password:')"; req "$d" domain || return; req "$u" user || return; req "$p" pass || return; runclp site:add:python --domainName="$d" --pythonVersion="$v" --appPort="$port" --siteUser="$u" --siteUserPassword="$p"; }
a_site_static() { local d u p; d="$(ask 'Domain:')"; u="$(ask 'Site user:')"; p="$(asks 'Site user password:')"; req "$d" domain || return; req "$u" user || return; req "$p" pass || return; runclp site:add:static --domainName="$d" --siteUser="$u" --siteUserPassword="$p"; }
a_site_proxy() { local d url u p; d="$(ask 'Domain:')"; url="$(ask 'Reverse proxy URL:' 'http://127.0.0.1:3000')"; u="$(ask 'Site user:')"; p="$(asks 'Site user password:')"; req "$d" domain || return; req "$u" user || return; req "$p" pass || return; runclp site:add:reverse-proxy --domainName="$d" --reverseProxyUrl="$url" --siteUser="$u" --siteUserPassword="$p"; }
a_site_cert() { local d k c ch; d="$(ask 'Domain:')"; k="$(ask 'Private key path:')"; c="$(ask 'Certificate path:')"; ch="$(ask 'Certificate chain path (Enter to skip):')"; req "$d" domain || return; req "$k" key || return; req "$c" cert || return; if [ -n "$ch" ]; then runclp site:install:certificate --domainName="$d" --privateKey="$k" --certificate="$c" --certificateChain="$ch"; else runclp site:install:certificate --domainName="$d" --privateKey="$k" --certificate="$c"; fi; }
a_site_delete() { local d f; d="$(ask 'Domain to DELETE:')"; req "$d" domain || return; f="$(ask 'Force (skip confirmation)? [y/N]:' 'n')"; if [[ "$f" =~ ^(y|Y|yes)$ ]]; then runclp site:delete --domainName="$d" --force; else runclp site:delete --domainName="$d"; fi; }

a_user_add() { local u e fn ln p r tz s sites; u="$(ask 'Username:')"; e="$(ask 'Email:')"; fn="$(ask 'First name:')"; ln="$(ask 'Last name:')"; p="$(asks 'Password:')"; r="$(ask 'Role (admin/site-manager/user):' 'admin')"; tz="$(ask 'Timezone:' 'Asia/Jakarta')"; s="$(ask 'Status (1=active,0=inactive):' '1')"; req "$u" user || return; req "$e" email || return; req "$p" pass || return; if [ "$r" = "user" ]; then sites="$(ask 'Sites (comma-sep, e.g. domain.com,domain.io):')"; runclp user:add --userName="$u" --email="$e" --firstName="$fn" --lastName="$ln" --password="$p" --role="$r" --sites="$sites" --timezone="$tz" --status="$s"; else runclp user:add --userName="$u" --email="$e" --firstName="$fn" --lastName="$ln" --password="$p" --role="$r" --timezone="$tz" --status="$s"; fi; }
a_user_delete() { local u; u="$(ask 'Username to delete:')"; req "$u" user || return; runclp user:delete --userName="$u"; }
a_user_list() { runclp user:list; }
a_user_reset() { local u p; u="$(ask 'Username:')"; p="$(asks 'New password:')"; req "$u" user || return; req "$p" pass || return; runclp user:reset:password --userName="$u" --password="$p"; }
a_user_mfa_off() { local u; u="$(ask 'Username:')"; req "$u" user || return; runclp user:disable:mfa --userName="$u"; }

a_vht_list() { runclp vhost-templates:list; }
a_vht_import() { runclp vhost-templates:import; }
a_vht_add() { local n f; n="$(ask 'Template name:')"; f="$(ask 'File path or URL:')"; req "$n" name || return; req "$f" file || return; runclp vhost-template:add --name="$n" --file="$f"; }
a_vht_delete() { local n; n="$(ask 'Template name:')"; req "$n" name || return; runclp vhost-template:delete --name="$n"; }
a_vht_view() { local n; n="$(ask 'Template name:')"; req "$n" name || return; runclp vhost-template:view --name="$n"; }

a_perms_reset() { local d f path; d="$(ask 'Directory perms:' '770')"; f="$(ask 'File perms:' '660')"; path="$(ask 'Path:' '.')"; runclp system:permissions:reset --directories="$d" --files="$f" --path="$path"; }
a_varnish_purge() { local v; v="$(ask "Purge target ('all', 'tag1,tag2', or a URL):" 'all')"; runclp varnish-cache:purge --purge="$v"; }

# ---- menu ---------------------------------------------------------------
hdr() { printf "  %b— %s —%b\n" "${C_DIM}" "$1" "${C_RESET}" >&2; }
menu() {
  printf "%bCloudPanel CLI — choose an action (q to quit):%b\n" "${C_BOLD}" "${C_RESET}" >&2
  hdr "CloudPanel"
  printf "   1) basic-auth enable        2) basic-auth disable      3) cloudflare update IPs\n" >&2
  hdr "Database"
  printf "   4) show master credentials  5) db add                  6) db export\n   7) db import\n" >&2
  hdr "Certificates"
  printf "   8) Let's Encrypt install    9) install custom cert\n" >&2
  hdr "Sites"
  printf "  10) add PHP                 11) add Node.js            12) add Python\n  13) add Static             14) add Reverse Proxy      15) delete site\n" >&2
  hdr "Users"
  printf "  16) add user               17) delete user            18) list users\n  19) reset password         20) disable MFA\n" >&2
  hdr "vHost Templates"
  printf "  21) list                   22) import                 23) add\n  24) delete                 25) view\n" >&2
  hdr "System"
  printf "  26) reset permissions      27) purge varnish cache\n" >&2
}

# ---- run ----------------------------------------------------------------
banner
if ! command -v clpctl >/dev/null 2>&1; then
  err "clpctl not found. Install CloudPanel first (install-cloudpanel.sh)."
  exit 1
fi
warn "Passwords are passed to clpctl as flags (CloudPanel's interface) and may briefly appear in the process list."

while true; do
  printf "\n" >&2
  menu
  CH="$(ask 'Action number:' '')"
  case "${CH}" in
    1) a_basic_auth_enable ;;  2) a_basic_auth_disable ;; 3) a_cloudflare_ips ;;
    4) a_db_master ;;          5) a_db_add ;;             6) a_db_export ;;
    7) a_db_import ;;          8) a_le_cert ;;            9) a_site_cert ;;
    10) a_site_php ;;          11) a_site_nodejs ;;       12) a_site_python ;;
    13) a_site_static ;;       14) a_site_proxy ;;        15) a_site_delete ;;
    16) a_user_add ;;          17) a_user_delete ;;       18) a_user_list ;;
    19) a_user_reset ;;        20) a_user_mfa_off ;;
    21) a_vht_list ;;          22) a_vht_import ;;         23) a_vht_add ;;
    24) a_vht_delete ;;        25) a_vht_view ;;
    26) a_perms_reset ;;       27) a_varnish_purge ;;
    q|Q|quit|"") info "Bye."; break ;;
    *) warn "Unknown choice: ${CH}" ;;
  esac
done

printf "\n%b✔ clpctl-manager finished.%b\n\n" "${C_BOLD}${C_GREEN}" "${C_RESET}" >&2
