#!/usr/bin/env bash
# ume-account-migrate.sh — rename this computer's login account to the UME
# standard name (the part of your UME work email before the '@'), so that
# JumpCloud takes over your existing account when you enroll, instead of
# creating a second, empty one.
#
# Works on Linux and macOS. Paste the SAME command up to 3 times; the script
# figures out which step you are on:
#   Check   (always)            compares your login name with your email.
#                               If it already matches, it says so and stops.
#   Run 1   (as yourself)       creates a temporary helper admin account
#                               "UME Migration" and asks you to log in to it.
#   Run 2   (as UME Migration)  renames your account. Your files, apps and
#                               password stay exactly the same. It opens by
#                               itself in a Terminal window at that login.
#   Run 3   (as your new name)  checks everything, removes the helper account.
#
# Usage (Terminal app, logged in as your normal account, no sudo):
#   f=$(mktemp) && curl -fsSL <url-of-this-file> -o "$f" && bash "$f"
#
# Options:
#   --email <address>  your UME work email (otherwise you are asked)
#   --check            only run the check; never changes anything
#   --cancel           after run 1 only: remove the helper account, stop
#   --version, --help
#
# Safety design (do not remove):
#   - Nothing changes before a plain-language explanation and a typed "yes".
#   - Prompts read from the keyboard (/dev/tty), never from a pipe.
#   - The account is renamed in place: same internal user ID, so files,
#     keychain/keyring, disk encryption and app permissions are untouched.
#   - No file inside the home folder is edited. A link from the old home
#     path to the new one keeps old hardcoded paths working.
#   - Every action is logged under /var/log/ume-account-migrate/, together
#     with the command that undoes it (lines starting with "UNDO:").
#   - No user data is ever deleted. The only account ever deleted is the
#     temporary helper account this script created itself.
#   - Compatible with macOS /bin/bash 3.2: no associative arrays, no
#     empty-array expansion under set -u.

set -euo pipefail

VERSION="2026.11.03.2"
SOURCE_URL="https://raw.githubusercontent.com/ScudraServicos/ume-device-setup/v${VERSION}/ume-account-migrate.sh"
RUN_CMD="f=\$(mktemp) && curl -fsSL ${SOURCE_URL} -o \"\$f\" && bash \"\$f\""
TEMP_ADMIN="ume-migrate"
TEMP_ADMIN_FULLNAME="UME Migration"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
OS="$(uname -s)"

case "${OS}" in
  Linux)  STATE_DIR="/var/lib/ume-account-migrate" ;;
  Darwin) STATE_DIR="/var/db/ume-account-migrate" ;;
  *) echo "Sorry, this computer type (${OS}) is not supported. Please contact your InfraSec team." >&2; exit 1 ;;
esac
STATE_FILE="${STATE_DIR}/state"
# Root-owned copy of this script + launcher, started at the helper's login (run 2).
RUN2_COPY="${STATE_DIR}/ume-account-migrate.sh"
RUN2_LAUNCHER="${STATE_DIR}/run2.command"
LOG_DIR="/var/log/ume-account-migrate"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'; else B=; G=; Y=; R=; N=; fi
say()   { printf '%s\n' "$*"; }
title() { printf '\n%s== %s ==%s\n\n' "${B}" "$*" "${N}"; }
ok()    { printf '%s[OK] %s%s\n' "${G}" "$*" "${N}"; }
warn()  { printf '%s[!] %s%s\n' "${Y}" "$*" "${N}"; }
die()   {
  printf '\n%s[X] %s%s\n' "${R}" "$*" "${N}" >&2
  printf '    Nothing else was changed. If you need help, contact your InfraSec team and share this message.\n' >&2
  [[ -n "${LOGFILE:-}" ]] && printf '    Details: %s\n' "${LOGFILE}" >&2
  exit 1
}
next_box() {
  printf '\n%s+-- WHAT TO DO NOW ----------------------------------------------%s\n' "${B}" "${N}"
  local line; for line in "$@"; do printf '%s|%s %s\n' "${B}" "${N}" "${line}"; done
  printf '%s+----------------------------------------------------------------%s\n\n' "${B}" "${N}"
}
SAME_CMD_1="   Paste the SAME command again in Terminal:"
SAME_CMD_2="     ${RUN_CMD}"

# Next steps after the name is right: install JumpCloud (no keys/URLs here: they
# come from the person's own activation email and portal).
jumpcloud_box() {
  next_box "${1}" \
           "Next: install JumpCloud on this computer." \
           " 1. Open the JumpCloud activation email from the company, follow it and set" \
           "    your new password." \
           " 2. Sign in to the JumpCloud User Portal (link in that email)." \
           " 3. Go to Security > Device Enrollment and follow the steps there to" \
           "    download and install the JumpCloud agent." \
           " 4. If asked to TAKE OVER an existing account, accept: it must be '${2}'." \
           "    If it wants to create a new account instead, stop and contact InfraSec." \
           " 5. Afterwards your login password is your JumpCloud password." \
           "${3:-}"
}

# Prompts always read the keyboard, even when the script itself came from a pipe.
ask() {
  local prompt="$1" reply=""
  # The device node can exist without a usable terminal: actually try to open it.
  if ! { : < /dev/tty; } 2>/dev/null; then
    die "This step needs you to type an answer, but there is no keyboard/terminal. Run the command in the Terminal app."
  fi
  printf '%s' "${prompt}" > /dev/tty
  IFS= read -r reply < /dev/tty || reply=""
  printf '%s' "${reply}"
}
confirm_yes() {
  local reply
  reply="$(ask "$1 Type ${B}yes${N} to continue: ")"
  [[ "${reply}" == "yes" ]]
}

LOGFILE=""
log() {
  [[ -n "${LOGFILE}" ]] || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "${LOGFILE}"
}
run() { # privileged command: log it and its output; fail loudly
  log "RUN: $*"
  if ! "$@" >> "${LOGFILE}" 2>&1; then
    log "FAILED: $*"
    die "A step failed: $*"
  fi
}
undo_note() { log "UNDO: $*"; }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
EMAIL=""
CHECK_ONLY=0
CANCEL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --email) EMAIL="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
    --email=*) EMAIL="${1#*=}"; shift ;;
    --check) CHECK_ONLY=1; shift ;;
    --cancel) CANCEL=1; shift ;;
    --version) say "ume-account-migrate ${VERSION}"; exit 0 ;;
    -h|--help) sed -n '2,38p' "${SCRIPT_PATH}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Who is really running this (also when re-run under sudo)
# ---------------------------------------------------------------------------
if [[ "${EUID}" -eq 0 ]]; then
  INVOKER="${SUDO_USER:-}"
  if [[ -z "${INVOKER}" || "${INVOKER}" == "root" ]]; then
    die "Please run this as your normal account, without 'sudo'. The script asks for your password itself when needed."
  fi
else
  INVOKER="$(id -un)"
fi

user_exists() { id "$1" >/dev/null 2>&1; }
homes_root()  { if [[ "${OS}" == "Darwin" ]]; then echo "/Users"; else echo "/home"; fi; }
home_of() {
  if [[ "${OS}" == "Darwin" ]]; then
    dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
  else
    getent passwd "$1" | cut -d: -f6
  fi
}
owner_of() {
  if [[ "${OS}" == "Darwin" ]]; then stat -f %Su "$1"; else stat -c %U "$1"; fi
}
is_admin() {
  if [[ "${OS}" == "Darwin" ]]; then
    dseditgroup -o checkmember -m "$1" admin >/dev/null 2>&1
  else
    id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qxE 'sudo|wheel|admin'
  fi
}

# True if the user still has a real login (desktop or terminal), as opposed to
# leftovers after logout. Desktop logins (GNOME/Wayland) are often missing from
# `who` or listed by numeric UID, so on Linux ask systemd-logind first.
is_logged_in() {
  local u="$1" uid s cls st
  uid="$(id -u "${u}" 2>/dev/null)" || return 1
  if [[ "${OS}" == "Linux" ]] && command -v loginctl >/dev/null 2>&1 \
     && loginctl show-user "${u}" >/dev/null 2>&1; then
    for s in $(loginctl show-user "${u}" -p Sessions --value 2>/dev/null); do
      cls="$(loginctl show-session "${s}" -p Class --value 2>/dev/null)"
      st="$(loginctl show-session "${s}" -p State --value 2>/dev/null)"
      # "user" = a desktop or terminal login; "manager" = background service
      # manager (kept alive by linger), not a login.
      if [[ "${cls}" == "user" && ( "${st}" == "active" || "${st}" == "online" ) ]]; then return 0; fi
    done
    return 1
  fi
  who | awk '{print $1}' | grep -qxE "${u}|${uid}"
}

# Stop everything still running as a user (after they logged out).
end_user_processes() {
  local u="$1"
  if [[ "${OS}" == "Linux" ]] && command -v loginctl >/dev/null 2>&1; then
    log "RUN: loginctl terminate-user ${u}"
    loginctl terminate-user "${u}" >> "${LOGFILE}" 2>&1 || true
    sleep 2
  fi
  log "RUN: pkill -TERM/-KILL -u ${u}"
  pkill -TERM -u "${u}" 2>/dev/null || true
  sleep 3
  pkill -KILL -u "${u}" 2>/dev/null || true
  sleep 2
}

# How to log out / open Terminal, per OS (shown in the WHAT TO DO NOW boxes).
if [[ "${OS}" == "Darwin" ]]; then
  HOW_LOGOUT="Apple menu (top-left) > Log Out. Do NOT restart, do NOT use 'switch user'."
  HOW_TERMINAL="Press Cmd+Space, type Terminal, press Enter."
else
  HOW_LOGOUT="Top-right menu > Power > Log Out (not Lock, not 'Switch User')."
  HOW_TERMINAL="Press Ctrl+Alt+T (or open the app list and search Terminal)."
fi
FIND_AGAIN="Lost the command? It is on https://github.com/ScudraServicos/ume-device-setup"

# Re-run this same script with admin rights (one password prompt).
ensure_root() {
  [[ "${EUID}" -eq 0 ]] && return 0
  [[ -f "${SCRIPT_PATH}" ]] || die "Please use the full command from the instructions (it saves the script to a file first)."
  is_admin "${INVOKER}" || die "The account '${INVOKER}' does not have admin rights on this computer, so it cannot make this change."
  say ""
  say "The next part needs admin rights. Your computer may ask for ${B}the password of '${INVOKER}'${N}"
  say "(the one you use to log in). Typing it shows nothing on screen - that is normal."
  if [[ ${CANCEL} -eq 1 ]]; then
    exec sudo -- bash "${SCRIPT_PATH}" --cancel
  elif [[ -n "${EMAIL}" ]]; then
    exec sudo -- bash "${SCRIPT_PATH}" --email "${EMAIL}"
  else
    exec sudo -- bash "${SCRIPT_PATH}"
  fi
}

# ---------------------------------------------------------------------------
# State file: KEY=VALUE lines, root-owned, parsed (never sourced)
# ---------------------------------------------------------------------------
S_PHASE=0; S_OLD_USER=""; S_NEW_USER=""; S_OLD_HOME=""; S_NEW_HOME=""; S_OLD_ADMIN=0; S_TEMP_CREATED=0
load_state() {
  [[ -f "${STATE_FILE}" ]] || return 0
  local k v
  while IFS='=' read -r k v; do
    case "${k}" in
      PHASE) S_PHASE="${v}" ;;
      OLD_USER) S_OLD_USER="${v}" ;;
      NEW_USER) S_NEW_USER="${v}" ;;
      OLD_HOME) S_OLD_HOME="${v}" ;;
      NEW_HOME) S_NEW_HOME="${v}" ;;
      OLD_ADMIN) S_OLD_ADMIN="${v}" ;;
      TEMP_CREATED) S_TEMP_CREATED="${v}" ;;
    esac
  done < "${STATE_FILE}"
}
save_state() {
  mkdir -p "${STATE_DIR}"; chmod 755 "${STATE_DIR}"
  local tmp; tmp="$(mktemp "${STATE_DIR}/.state.XXXXXX")"
  {
    printf 'PHASE=%s\n' "${S_PHASE}"
    printf 'OLD_USER=%s\n' "${S_OLD_USER}"
    printf 'NEW_USER=%s\n' "${S_NEW_USER}"
    printf 'OLD_HOME=%s\n' "${S_OLD_HOME}"
    printf 'NEW_HOME=%s\n' "${S_NEW_HOME}"
    printf 'OLD_ADMIN=%s\n' "${S_OLD_ADMIN}"
    printf 'TEMP_CREATED=%s\n' "${S_TEMP_CREATED}"
  } > "${tmp}"
  chmod 644 "${tmp}"; mv "${tmp}" "${STATE_FILE}"
}

start_log() {
  mkdir -p "${LOG_DIR}"; chmod 755 "${LOG_DIR}"
  LOGFILE="${LOG_DIR}/$(date +%Y%m%d-%H%M%S)-$1.log"
  touch "${LOGFILE}"; chmod 644 "${LOGFILE}"
  log "ume-account-migrate ${VERSION} os=${OS} invoker=${INVOKER} step=$1"
}

# ---------------------------------------------------------------------------
# Check (read-only)
# ---------------------------------------------------------------------------
TARGET=""; CUR_USER=""; CUR_HOME=""; NEED_RENAME=0; NEED_HOME=0
get_email() {
  if [[ -z "${EMAIL}" ]]; then
    say "Hi! This tool checks whether your computer login name matches your UME work email."
    say ""
    EMAIL="$(ask "Type your UME work email (for example maria.silva@company.com): ")"
  fi
  EMAIL="$(printf '%s' "${EMAIL}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  [[ "${EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]] || die "'${EMAIL}' does not look like an email address."
  TARGET="${EMAIL%@*}"
  if ! [[ "${TARGET}" =~ ^[a-z_][a-z0-9._-]*$ ]] || [[ ${#TARGET} -gt 31 ]]; then
    die "The part before '@' ('${TARGET}') cannot be used as a login name on this computer. Please contact your InfraSec team."
  fi
}

check() {
  get_email
  CUR_USER="${INVOKER}"
  CUR_HOME="$(home_of "${CUR_USER}")"
  [[ "${CUR_USER}" == "${TARGET}" ]] || NEED_RENAME=1
  [[ "${CUR_HOME}" == "$(homes_root)/${TARGET}" ]] || NEED_HOME=1

  title "Check"
  say "  UME email        : ${EMAIL}"
  say "  Standard name    : ${B}${TARGET}${N}"
  say "  Your login name  : ${CUR_USER}"
  say "  Your home folder : ${CUR_HOME}"
  say ""

  if [[ ${NEED_RENAME} -eq 0 && ${NEED_HOME} -eq 0 ]]; then
    ok "All good! Your computer already uses the UME standard name '${TARGET}'."
    jumpcloud_box "Nothing to change on this computer." "${TARGET}"
    exit 0
  fi
  if [[ ${NEED_RENAME} -eq 1 ]] && user_exists "${TARGET}"; then
    die "An account named '${TARGET}' already exists on this computer (maybe JumpCloud created it already). Please contact your InfraSec team before going on."
  fi
  if [[ ${NEED_HOME} -eq 1 && -e "$(homes_root)/${TARGET}" ]]; then
    die "A folder $(homes_root)/${TARGET} already exists. Please contact your InfraSec team before going on."
  fi
  warn "Your login name and/or home folder do not match the UME standard yet."
}

explain_plan() {
  title "What will happen"
  say "Your computer login will change from ${B}${CUR_USER}${N} to ${B}${TARGET}${N}."
  [[ ${NEED_HOME} -eq 1 ]] && say "Your home folder will move from ${CUR_HOME} to $(homes_root)/${TARGET}."
  say ""
  say "What stays the same:"
  say "  - all your files, apps, settings and saved passwords"
  say "  - your login password"
  say ""
  say "What you will do (about 15 minutes):"
  say "  1. Now: this tool creates a temporary helper account called '${TEMP_ADMIN_FULLNAME}'."
  say "     You choose its password (you only need it today)."
  say "  2. Log out, log in as '${TEMP_ADMIN_FULLNAME}'. A Terminal window opens by itself"
  say "     (if not, paste the same command again). That renames your account."
  say "  3. Log out, log in with your NEW name '${TARGET}' (same password as always),"
  say "     paste the same command one last time. It checks everything and removes"
  say "     the helper account."
  say ""
  say "Before you continue:"
  say "  - Save your work and close your apps - you will be logged out."
  say "  - Keep your laptop plugged in."
  [[ "${OS}" == "Darwin" ]] && say "  - ${B}Do NOT restart the Mac${N} until all 3 runs are done. Only log out / log in."
  say "  - Keep this command at hand (for example in a note on your phone):"
  say "      ${RUN_CMD}"
  say ""
}

# ---------------------------------------------------------------------------
# Run 1: create the temporary helper admin (run by the user being migrated)
# ---------------------------------------------------------------------------
create_temp_admin_linux() {
  local grp="" g
  for g in sudo wheel admin; do
    if getent group "${g}" >/dev/null; then grp="${g}"; break; fi
  done
  [[ -n "${grp}" ]] || die "Could not find the admin group (sudo/wheel) on this computer."
  run useradd -m -s /bin/bash -c "${TEMP_ADMIN_FULLNAME}" -G "${grp}" "${TEMP_ADMIN}"
  undo_note "userdel -r ${TEMP_ADMIN}"
  # Skip the GNOME "Welcome" wizard on the helper's first desktop login.
  install -d -o "${TEMP_ADMIN}" -g "$(id -gn "${TEMP_ADMIN}")" -m 0700 "/home/${TEMP_ADMIN}/.config"
  printf 'yes' > "/home/${TEMP_ADMIN}/.config/gnome-initial-setup-done"
  chown "${TEMP_ADMIN}:$(id -gn "${TEMP_ADMIN}")" "/home/${TEMP_ADMIN}/.config/gnome-initial-setup-done"
  say "Choose a password for the temporary '${TEMP_ADMIN_FULLNAME}' account (you only need it today):"
  local attempt
  for attempt in 1 2 3; do
    if passwd "${TEMP_ADMIN}" < /dev/tty > /dev/tty 2>&1; then return 0; fi
    log "passwd attempt ${attempt} failed"
    warn "That did not work, let's try again."
  done
  run userdel -r "${TEMP_ADMIN}"
  die "Could not set the password. The temporary account was removed again."
}

create_temp_admin_macos() {
  local pw1="" pw2="" attempt
  for attempt in 1 2 3; do
    printf 'Choose a password for the temporary "%s" account (you only need it today): ' "${TEMP_ADMIN_FULLNAME}" > /dev/tty
    IFS= read -rs pw1 < /dev/tty; printf '\n' > /dev/tty
    printf 'Type it again: ' > /dev/tty
    IFS= read -rs pw2 < /dev/tty; printf '\n' > /dev/tty
    if [[ -n "${pw1}" && "${pw1}" == "${pw2}" ]]; then break; fi
    log "password attempt ${attempt} mismatch/empty"
    warn "The passwords were empty or did not match, let's try again."
    pw1=""
  done
  [[ -n "${pw1}" ]] || die "Could not set the password."
  # "-password -" reads the password from stdin: never on the command line or in the log.
  log "RUN: sysadminctl -addUser ${TEMP_ADMIN} -fullName '${TEMP_ADMIN_FULLNAME}' -admin -password <hidden>"
  sysadminctl -addUser "${TEMP_ADMIN}" -fullName "${TEMP_ADMIN_FULLNAME}" -admin -password - <<< "${pw1}" >> "${LOGFILE}" 2>&1 \
    || die "Could not create the temporary account."
  pw1=""; pw2=""
  undo_note "sysadminctl -deleteUser ${TEMP_ADMIN}"
  user_exists "${TEMP_ADMIN}" || die "The temporary account was not created."
}

# Make run 2 start by itself when the helper logs in: a root-owned copy of this
# exact script, a launcher that keeps the window open, and a login item in the
# helper's (temporary) home. Best effort: pasting the command still works.
install_run2_autostart() {
  local home grp
  home="$(home_of "${TEMP_ADMIN}")"; grp="$(id -gn "${TEMP_ADMIN}")"
  [[ -n "${home}" ]] || return 1
  install -m 0755 "${SCRIPT_PATH}" "${RUN2_COPY}" || return 1
  cat > "${RUN2_LAUNCHER}" <<EOF || return 1
#!/bin/bash
# UME account migration, run 2: opened at the '${TEMP_ADMIN}' login.
[ "\$(id -un)" = "${TEMP_ADMIN}" ] || exit 0
bash "${RUN2_COPY}"
echo
read -r -p "Press Enter to close this window. " _
EOF
  chmod 0755 "${RUN2_LAUNCHER}" || return 1
  undo_note "rm -f ${RUN2_COPY} ${RUN2_LAUNCHER}"

  if [[ "${OS}" == "Darwin" ]]; then
    [[ -d "${home}" ]] || createhomedir -c -u "${TEMP_ADMIN}" >> "${LOGFILE}" 2>&1 || return 1
    install -d -o "${TEMP_ADMIN}" -g "${grp}" -m 0700 "${home}/Library" || return 1
    install -d -o "${TEMP_ADMIN}" -g "${grp}" -m 0755 "${home}/Library/LaunchAgents" || return 1
    cat > "${home}/Library/LaunchAgents/ume.account-migrate.plist" <<EOF || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>ume.account-migrate</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/open</string><string>-a</string><string>Terminal</string><string>${RUN2_LAUNCHER}</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
    chown "${TEMP_ADMIN}:${grp}" "${home}/Library/LaunchAgents/ume.account-migrate.plist" || return 1
    chmod 0644 "${home}/Library/LaunchAgents/ume.account-migrate.plist" || return 1
    # Double-click fallback if the window was closed.
    install -d -o "${TEMP_ADMIN}" -g "${grp}" -m 0700 "${home}/Desktop" || return 1
    ln -sf "${RUN2_LAUNCHER}" "${home}/Desktop/Continue UME migration.command" || return 1
  else
    # Prefer the desktop's own terminal; else let the desktop pick one (Terminal=true).
    local exec_line="" terminal=false t
    for t in gnome-terminal ptyxis kgx konsole xfce4-terminal mate-terminal xterm; do
      command -v "${t}" >/dev/null 2>&1 || continue
      case "${t}" in
        gnome-terminal|ptyxis|kgx) exec_line="${t} -- /bin/bash ${RUN2_LAUNCHER}" ;;
        xfce4-terminal|mate-terminal) exec_line="${t} -x /bin/bash ${RUN2_LAUNCHER}" ;;
        *) exec_line="${t} -e /bin/bash ${RUN2_LAUNCHER}" ;;
      esac
      break
    done
    if [[ -z "${exec_line}" ]]; then exec_line="/bin/bash ${RUN2_LAUNCHER}"; terminal=true; fi
    install -d -o "${TEMP_ADMIN}" -g "${grp}" -m 0700 "${home}/.config/autostart" || return 1
    cat > "${home}/.config/autostart/ume-account-migrate.desktop" <<EOF || return 1
[Desktop Entry]
Type=Application
Name=UME account migration
Exec=${exec_line}
Terminal=${terminal}
X-GNOME-Autostart-enabled=true
EOF
    chown "${TEMP_ADMIN}:${grp}" "${home}/.config/autostart/ume-account-migrate.desktop" || return 1
  fi
  log "run 2 autostart installed for ${TEMP_ADMIN}"
}

remove_run2_copy() { rm -f "${RUN2_COPY}" "${RUN2_LAUNCHER}"; }

run1() {
  explain_plan
  if ! confirm_yes "Ready to start?"; then
    say "OK, nothing was changed. Paste the command again whenever you are ready."
    exit 0
  fi
  start_log run1
  user_exists "${TEMP_ADMIN}" && die "A '${TEMP_ADMIN}' account already exists from an earlier attempt. Please contact your InfraSec team."

  title "Run 1 of 3 - creating the temporary helper account"
  if [[ "${OS}" == "Darwin" ]]; then create_temp_admin_macos; else create_temp_admin_linux; fi
  ok "Temporary account '${TEMP_ADMIN_FULLNAME}' created."
  mkdir -p "${STATE_DIR}"; chmod 755 "${STATE_DIR}"
  if ! install_run2_autostart; then
    log "WARN: could not set up the run 2 autostart"
    warn "Could not set up the automatic start; you will paste the command yourself in run 2."
  fi

  S_PHASE=1
  S_OLD_USER="${CUR_USER}"
  S_NEW_USER="${TARGET}"
  S_OLD_HOME="${CUR_HOME}"
  S_NEW_HOME="$(homes_root)/${TARGET}"
  if is_admin "${CUR_USER}"; then S_OLD_ADMIN=1; else S_OLD_ADMIN=0; fi
  S_TEMP_CREATED=1
  save_state
  log "state saved: run 1 complete old=${S_OLD_USER} new=${S_NEW_USER}"

  next_box "1. Save your work and close your apps." \
           "2. Log out: ${HOW_LOGOUT}" \
           "3. On the login screen choose '${TEMP_ADMIN_FULLNAME}' and use the password you just chose." \
           "   (Linux: if it is not listed, click 'Not listed?' and type ${TEMP_ADMIN})" \
           "   If welcome/setup screens appear, skip them all (Skip / Set Up Later)." \
           "4. A Terminal window opens by itself and continues. Follow it." \
           "   If it does not open: ${HOW_TERMINAL}" \
           "${SAME_CMD_1}" "${SAME_CMD_2}" \
           "   ${FIND_AGAIN}" \
           "" \
           "Changed your mind? Paste the command with ' --cancel' at the end, here, now."
}

cancel_run1() {
  [[ "${S_PHASE}" == "1" ]] || die "--cancel only works right after run 1."
  [[ "${INVOKER}" != "${TEMP_ADMIN}" ]] || die "Log in as '${S_OLD_USER}' to cancel."
  ensure_root
  start_log cancel
  if user_exists "${TEMP_ADMIN}" && [[ "${S_TEMP_CREATED}" == "1" ]]; then
    pgrep -u "${TEMP_ADMIN}" >/dev/null 2>&1 && die "'${TEMP_ADMIN_FULLNAME}' is still logged in. Log it out first."
    if [[ "${OS}" == "Darwin" ]]; then run sysadminctl -deleteUser "${TEMP_ADMIN}"; else run userdel -r "${TEMP_ADMIN}"; fi
  fi
  remove_run2_copy
  rm -f "${STATE_FILE}"
  log "cancelled; state cleared"
  ok "Cancelled. The helper account was removed; your account was not changed."
  exit 0
}

# ---------------------------------------------------------------------------
# Run 2: rename (run by the temporary helper admin)
# ---------------------------------------------------------------------------
stop_user_processes() {
  local u="$1"
  if pgrep -u "${u}" >/dev/null 2>&1; then
    warn "Some programs of '${u}' are still running in the background."
    confirm_yes "They will be closed now (unsaved work in them is lost)." || die "Stopped. Log out of '${u}' fully and try again."
    end_user_processes "${u}"
    if pgrep -u "${u}" >/dev/null 2>&1; then
      die "Programs of '${u}' are still running and could not be closed."
    fi
  fi
  log "no processes left for ${u}"
}

rename_linux() {
  local old="$1" new="$2" old_home="$3" new_home="$4" f p tmp
  if [[ -d "/home/.ecryptfs/${old}" ]]; then
    die "Your home folder uses an older encryption type (eCryptfs) that this tool does not handle. Please contact your InfraSec team."
  fi
  if command -v homectl >/dev/null 2>&1 && homectl inspect "${old}" >/dev/null 2>&1; then
    die "Your account is managed by systemd-homed, which this tool does not handle. Please contact your InfraSec team."
  fi

  if [[ "${old}" != "${new}" ]]; then
    run usermod -l "${new}" "${old}"
    undo_note "usermod -l ${old} ${new}"
    if getent group "${old}" >/dev/null; then
      run groupmod -n "${new}" "${old}"
      undo_note "groupmod -n ${old} ${new}"
    fi
    for f in /etc/subuid /etc/subgid; do
      if [[ -f "${f}" ]] && grep -q "^${old}:" "${f}"; then
        run cp -p "${f}" "${f}.ume-migrate.bak"
        run sed -i "s/^${old}:/${new}:/" "${f}"
        undo_note "cp -p ${f}.ume-migrate.bak ${f}"
      fi
    done
    for p in /var/lib/AccountsService/users /var/lib/AccountsService/icons /var/lib/systemd/linger \
             /var/mail /var/spool/mail /var/spool/cron/crontabs /var/spool/cron; do
      if [[ -f "${p}/${old}" && ! -e "${p}/${new}" ]]; then
        run mv "${p}/${old}" "${p}/${new}"
        undo_note "mv ${p}/${new} ${p}/${old}"
      fi
    done
    # sudoers.d: whole-word matches only, validated with visudo before replacing.
    for f in /etc/sudoers.d/*; do
      [[ -f "${f}" ]] || continue
      grep -qw -- "${old}" "${f}" || continue
      tmp="$(mktemp)"
      sed "s/\\b${old}\\b/${new}/g" "${f}" > "${tmp}"
      if visudo -c -f "${tmp}" >/dev/null 2>&1; then
        run cp -p "${f}" "/root/$(basename "${f}").ume-migrate.bak"
        chmod 0440 "${tmp}"; mv "${tmp}" "${f}"
        log "updated ${f}"
        undo_note "cp -p /root/$(basename "${f}").ume-migrate.bak ${f}"
      else
        rm -f "${tmp}"
        warn "Could not safely update ${f}; your InfraSec team may need to check it."
        log "WARN: visudo rejected edit of ${f}"
      fi
    done
  fi

  if [[ "${old_home}" != "${new_home}" ]]; then
    run usermod -d "${new_home}" -m "${new}"
    undo_note "usermod -d ${old_home} -m ${new}"
    if command -v restorecon >/dev/null 2>&1; then run restorecon -R "${new_home}"; fi
  fi
}

rename_macos() {
  local old="$1" new="$2" old_home="$3" new_home="$4" groups g
  if [[ "${old}" != "${new}" ]]; then
    # Group memberships are stored by short name: move them to the new name.
    groups="$(dscl . -list /Groups GroupMembership 2>/dev/null \
      | awk -v u="${old}" '{for(i=2;i<=NF;i++) if($i==u){print $1; break}}')"
    run dscl . -change "/Users/${old}" RecordName "${old}" "${new}"
    undo_note "dscl . -change /Users/${new} RecordName ${new} ${old}"
    for g in ${groups}; do
      run dseditgroup -o edit -a "${new}" -t user "${g}"
      dseditgroup -o edit -d "${old}" -t user "${g}" >> "${LOGFILE}" 2>&1 || true
      undo_note "dseditgroup -o edit -a ${old} -t user ${g} && dseditgroup -o edit -d ${new} -t user ${g}"
    done
  fi
  if [[ "${old_home}" != "${new_home}" ]]; then
    run mv "${old_home}" "${new_home}"
    undo_note "mv ${new_home} ${old_home}"
    run dscl . -change "/Users/${new}" NFSHomeDirectory "${old_home}" "${new_home}"
    undo_note "dscl . -change /Users/${old} NFSHomeDirectory ${new_home} ${old_home}"
  fi
  # Refresh the FileVault unlock screen with the new name (harmless if FileVault is off).
  log "RUN: diskutil apfs updatePreboot /"
  diskutil apfs updatePreboot / >> "${LOGFILE}" 2>&1 || warn "Could not refresh the startup screen info (not critical)."
}

run2() {
  local old="${S_OLD_USER}" new="${S_NEW_USER}" old_home="${S_OLD_HOME}" new_home="${S_NEW_HOME}"
  title "Run 2 of 3 - renaming your account"
  say "  login name : ${old}  ->  ${new}"
  [[ "${old_home}" != "${new_home}" ]] && say "  home folder: ${old_home}  ->  ${new_home}"
  say ""
  user_exists "${old}" || die "The account '${old}' was not found."
  if [[ "${old}" != "${new}" ]] && user_exists "${new}"; then die "An account '${new}' already exists."; fi
  if [[ "${old_home}" != "${new_home}" && -e "${new_home}" ]]; then die "${new_home} already exists."; fi
  if is_logged_in "${old}"; then
    die "'${old}' is still logged in (maybe with 'Switch User'). Go back to it, log out completely (${HOW_LOGOUT}), log in here again and paste the command."
  fi
  if ! confirm_yes "Rename now?"; then say "OK, nothing was changed."; exit 0; fi
  start_log run2
  stop_user_processes "${old}"

  if [[ "${OS}" == "Darwin" ]]; then rename_macos "${old}" "${new}" "${old_home}" "${new_home}"
  else rename_linux "${old}" "${new}" "${old_home}" "${new_home}"; fi

  # The old path keeps working for anything that remembered it.
  if [[ "${old_home}" != "${new_home}" && ! -e "${old_home}" ]]; then
    run ln -s "${new_home}" "${old_home}"
    undo_note "rm ${old_home}"
  fi

  user_exists "${new}" || die "Check failed after rename: '${new}' not found."
  [[ "$(home_of "${new}")" == "${new_home}" && -d "${new_home}" ]] || die "Check failed after rename: home folder is not ${new_home}."
  S_PHASE=2; save_state
  log "state saved: run 2 complete"
  ok "Your account is now '${new}'."

  next_box "1. Log out of '${TEMP_ADMIN_FULLNAME}': ${HOW_LOGOUT}" \
           "2. Log in with your NEW name: ${new}" \
           "   Use the SAME password as always." \
           "   (Login screens often show your full name instead - pick that.)" \
           "   (Linux: if it is not listed, click 'Not listed?' and type ${new})" \
           "3. Open Terminal: ${HOW_TERMINAL}" \
           "${SAME_CMD_1}" "${SAME_CMD_2}" \
           "   ${FIND_AGAIN}"
}

# ---------------------------------------------------------------------------
# Run 3: verify and clean up (run by the renamed user)
# ---------------------------------------------------------------------------
run3() {
  local new="${S_NEW_USER}" new_home="${S_NEW_HOME}" problems=0
  title "Run 3 of 3 - final checks"
  start_log run3
  if [[ "${INVOKER}" == "${new}" ]]; then ok "You are logged in as '${new}'."
  else warn "You are logged in as '${INVOKER}', expected '${new}'."; problems=1; fi
  if [[ "$(home_of "${new}")" == "${new_home}" ]]; then ok "Your home folder is ${new_home}."
  else warn "Your home folder is not ${new_home}."; problems=1; fi
  if [[ "$(owner_of "${new_home}")" == "${new}" ]]; then ok "Your files belong to you."
  else warn "The home folder owner looks wrong."; problems=1; fi
  if [[ "${S_OLD_ADMIN}" == "1" ]]; then
    if is_admin "${new}"; then ok "Admin rights kept."
    else warn "Admin rights were lost."; problems=1; fi
  fi

  if [[ ${problems} -ne 0 ]]; then
    log "run3: problems found; helper account kept"
    die "Something does not look right, so the helper account was kept for safety. Please contact your InfraSec team."
  fi

  say ""
  say "Please take one minute to check, in your normal apps, that things look as usual:"
  say "  - your browser opens with your tabs and saved logins"
  say "  - your files and desktop are there"
  say "  - email, chat, VPN and other work apps open normally"
  say ""
  if ! confirm_yes "Everything looks fine and the helper account can be removed?"; then
    log "run3: user did not confirm; helper account kept"
    say "OK - the helper account was kept. Tell your InfraSec team what looks wrong and share ${LOGFILE}."
    exit 0
  fi

  if user_exists "${TEMP_ADMIN}" && [[ "${S_TEMP_CREATED}" == "1" ]]; then
    if is_logged_in "${TEMP_ADMIN}"; then
      die "'${TEMP_ADMIN_FULLNAME}' is still logged in (maybe with 'Switch User'). Log out of it, then paste the command again here."
    fi
    end_user_processes "${TEMP_ADMIN}"
    if [[ "${OS}" == "Darwin" ]]; then
      sysadminctl -deleteUser "${TEMP_ADMIN}" >> "${LOGFILE}" 2>&1 || true
    else
      userdel -r "${TEMP_ADMIN}" >> "${LOGFILE}" 2>&1 || true
    fi
    if user_exists "${TEMP_ADMIN}"; then
      warn "Could not remove the helper account; your InfraSec team can remove it later."
      log "WARN: could not delete ${TEMP_ADMIN}"
    else
      ok "Helper account '${TEMP_ADMIN_FULLNAME}' removed."
      log "deleted ${TEMP_ADMIN}"
    fi
  fi
  remove_run2_copy
  rm -f "${STATE_FILE}"
  log "run3: done, state cleared"
  ok "Migration finished."
  jumpcloud_box "Your login name is now '${new}'." "${new}" "A record of what was done is in ${LOG_DIR}/"
}

# ---------------------------------------------------------------------------
# Main: decide which step we are on
# ---------------------------------------------------------------------------
say "${B}UME account migration${N} (version ${VERSION})"
load_state

if [[ ${CANCEL} -eq 1 ]]; then cancel_run1; fi

if [[ "${S_PHASE}" == "0" ]]; then
  [[ "${INVOKER}" != "${TEMP_ADMIN}" ]] || die "The helper account is only used while a migration is in progress, and none was found."
  check
  if [[ ${CHECK_ONLY} -eq 1 ]]; then
    say "Check only (--check): nothing was changed. Run without --check to start."
    exit 0
  fi
  ensure_root
  run1
  exit 0
fi

if [[ ${CHECK_ONLY} -eq 1 ]]; then
  say "A migration is in progress: '${S_OLD_USER}' -> '${S_NEW_USER}' (run ${S_PHASE} of 3 done)."
  exit 0
fi

case "${S_PHASE}" in
  1)
    if [[ "${INVOKER}" == "${TEMP_ADMIN}" ]]; then ensure_root; run2
    else next_box "Run 1 is already done." \
                  "Log out (${HOW_LOGOUT})," \
                  "log in as '${TEMP_ADMIN_FULLNAME}', open Terminal (${HOW_TERMINAL})." \
                  "${SAME_CMD_1}" "${SAME_CMD_2}"
    fi ;;
  2)
    if [[ "${INVOKER}" == "${S_NEW_USER}" ]]; then ensure_root; run3
    else next_box "Run 2 is already done." \
                  "Log out (${HOW_LOGOUT})," \
                  "log in as '${S_NEW_USER}' (same password as always), open Terminal." \
                  "${SAME_CMD_1}" "${SAME_CMD_2}"
    fi ;;
  *) die "Unexpected state in ${STATE_FILE}. Please contact your InfraSec team." ;;
esac
