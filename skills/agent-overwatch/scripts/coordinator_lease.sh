#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Agent Overwatch — Coordinator Lease
#
# A small key=value lease file that tells a coordinator session whether another
# session has taken over the project (e.g. while it was rate-limited).
#
# Exit codes:
#   0  success / lease held by me
#   1  I/O or bus-append error
#   2  usage error
#   3  lease held by another, non-expired id
#   4  lease expired or absent (status, renew)
# -----------------------------------------------------------------------------
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTION=""
ID="${AO_COORDINATOR_ID:-}"
TTL=30
FILE="status/coordinator.lease"
BUS="./AGENT_BUS.md"
TAKEOVER=false

show_help() {
  cat <<'EOF'
Agent Overwatch — Coordinator Lease

Usage:
  coordinator_lease.sh claim|renew|release|status [--id ID] [--ttl MIN]
                       [--file PATH] [--takeover] [--bus PATH]

Actions:
  claim     Take the lease. Refuses (exit 3) if another id holds a live lease,
            unless --takeover, which also appends a TAKEOVER entry to the bus.
            Claiming a lease you already hold renews it.
  renew     Refresh last_seen on a lease you hold (exit 3 / 4 otherwise).
  release   Remove a lease you hold (exit 3 if another id holds it).
  status    Print the lease. Exit 0 = held by me, 3 = held by another live id,
            4 = expired or none. Never creates the file.

Options:
  --id ID      Holder id (default: $AO_COORDINATOR_ID, else <user>@<host>:<ppid>).
               Set AO_COORDINATOR_ID for a stable id: the <ppid> fallback
               changes whenever the calling shell changes.
  --ttl MIN    Minutes after last_seen before the lease expires (default 30;
               0 = already expired, useful in tests).
  --file PATH  Lease file (default: status/coordinator.lease).
  --takeover   With claim: take over a lease held by another id.
  --bus PATH   Bus for the TAKEOVER entry (default: ./AGENT_BUS.md).
  -h, --help   Show this help.

Lease file keys: id, since, last_seen (UTC), ttl_min, last_seen_epoch.
EOF
}

die_usage() { echo "[ERROR] $1" >&2; echo "Run '$0 --help' for usage." >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    claim|renew|release|status)
      [[ -z "$ACTION" ]] || die_usage "Only one action allowed"
      ACTION="$1"; shift ;;
    --takeover) TAKEOVER=true; shift ;;
    --id|--ttl|--file|--bus)
      [[ $# -ge 2 ]] || die_usage "$1 requires a value"
      case "$1" in
        --id) ID="$2" ;; --ttl) TTL="$2" ;; --file) FILE="$2" ;; --bus) BUS="$2" ;;
      esac
      shift 2 ;;
    *) die_usage "Unknown argument: $1" ;;
  esac
done

[[ -n "$ACTION" ]] || die_usage "An action is required (claim|renew|release|status)"
[[ "$TTL" =~ ^[0-9]+$ ]] || die_usage "--ttl must be a non-negative integer (minutes)"
if [[ -z "$ID" ]]; then
  ID="$(id -un 2>/dev/null || echo user)@$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host):${PPID}"
fi
# The id lands in a key=value file and a bus header: keep it to one safe line.
ID_RE='^[A-Za-z0-9@._:/+() -]{1,120}$'
[[ "$ID" =~ $ID_RE ]] || die_usage "--id may only contain letters, digits, spaces and @._:/+()- (max 120)"
[[ "$TAKEOVER" == false || "$ACTION" == claim ]] || die_usage "--takeover is only valid with claim"

# Same pattern family as overwatch_watch.sh / verify_atomic_branch.sh. The id is
# written to the lease file and the bus, so a credential-looking id is refused.
looks_like_secret() {
  local re
  for re in 'BEGIN[[:space:]]+([A-Za-z0-9_-]+[[:space:]]+)?PRIVATE KEY' 'tskey-auth-[a-zA-Z0-9_-]+' \
            'ghp_[a-zA-Z0-9]{20,}' 'github_pat_[a-zA-Z0-9_]{20,}' 'sk-[a-zA-Z0-9_-]{20,}' 'AKIA[0-9A-Z]{16}' \
            '(password|token|secret|api_?key)[[:space:]]*[:=][[:space:]]*[^[:space:]]{8,}'; do
    if printf '%s\n' "$1" | grep -qiE -- "$re"; then return 0; fi
  done
  return 1
}
if looks_like_secret "$ID"; then die_usage "--id matches a secret pattern; refusing (value not shown)"; fi

now_epoch() { date -u +%s; }
now_ts() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }

L_ID=""; L_SINCE=""; L_LAST=""; L_TTL=""; L_EPOCH=""
read_lease() {
  L_ID=""; L_SINCE=""; L_LAST=""; L_TTL=""; L_EPOCH=""
  [[ -f "$FILE" ]] || return 1
  local k v
  while IFS='=' read -r k v; do
    v="${v%$'\r'}"
    case "$k" in
      id) L_ID="$v" ;; since) L_SINCE="$v" ;; last_seen) L_LAST="$v" ;;
      ttl_min) L_TTL="$v" ;; last_seen_epoch) L_EPOCH="$v" ;;
    esac
  done < "$FILE"
  [[ -n "$L_ID" ]]
}

# "YYYY-MM-DD HH:MM:SS UTC" or ISO "YYYY-MM-DDTHH:MM:SSZ" -> epoch (GNU/busybox/BSD date)
ts_to_epoch() {
  local t="${1% UTC}" re='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(:[0-9]{2})?$'
  t="${t%Z}"; t="${t/T/ }"
  [[ "$t" =~ $re ]] || return 1
  [[ ${#t} -eq 16 ]] && t="$t:00"
  date -u -d "$t" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d %H:%M:%S' "$t" +%s 2>/dev/null
}

# 0 = live, 1 = expired. A lease with only the BRIEF keys (id/since/last_seen)
# gets its epoch from last_seen and ttl 30; an unparseable lease counts as expired.
lease_live() {
  local epoch="$L_EPOCH" ttl="$L_TTL"
  [[ "$epoch" =~ ^[0-9]+$ ]] || epoch="$(ts_to_epoch "$L_LAST" || true)"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=30
  [[ "$epoch" =~ ^[0-9]+$ ]] || return 1
  (( $(now_epoch) < epoch + ttl * 60 ))
}

write_lease() { # $1 = since
  local dir tmp
  dir="$(dirname "$FILE")"
  mkdir -p "$dir" || { echo "[ERROR] cannot create $dir" >&2; exit 1; }
  tmp="$(mktemp "$dir/.coordinator.lease.XXXXXX")" || { echo "[ERROR] mktemp failed in $dir" >&2; exit 1; }
  if ! printf 'id=%s\nsince=%s\nlast_seen=%s\nttl_min=%s\nlast_seen_epoch=%s\n' \
      "$ID" "$1" "$(now_ts)" "$TTL" "$(now_epoch)" > "$tmp" || ! mv -f "$tmp" "$FILE"; then
    rm -f "$tmp"; echo "[ERROR] failed to write $FILE" >&2; exit 1
  fi
}

print_lease() {
  printf 'id=%s\nsince=%s\nlast_seen=%s\nttl_min=%s\n' "$L_ID" "$L_SINCE" "$L_LAST" "$L_TTL"
}

append_takeover() { # $1 previous id, $2 previous last_seen, $3 live|expired
  local body
  # shellcheck disable=SC2016  # backticks are literal Markdown
  body="$(printf -- '- Previous holder: `%s` (last_seen %s, %s).\n- New holder: `%s`; lease file `%s`, ttl %s min.\n- If you were the previous holder: stop coordinating, read HANDOFF.md and the bus tail, then post before acting.' \
    "$1" "$2" "$3" "$ID" "$FILE" "$TTL")"
  if [[ -f "$SCRIPT_DIR/bus_append.sh" ]]; then
    printf '%s\n' "$body" | bash "$SCRIPT_DIR/bus_append.sh" --from "$ID" --to all \
      --type TAKEOVER --subject "coordinator lease" --bus "$BUS" \
      || { echo "[ERROR] lease taken, but bus_append.sh failed to record the TAKEOVER" >&2; return 1; }
    return 0
  fi
  # Fallback: same header format, one grouped append (flock when available).
  local header
  header="### [$(now_ts)] ${ID} -> all | TAKEOVER coordinator lease"
  {
    if command -v flock >/dev/null 2>&1; then flock -x 9; fi
    {
      printf '\n%s\n%s\n' "$header" "$body"
      cat <<'EOF'
- Recorded by coordinator_lease.sh (bus_append.sh fallback).
EOF
    } >> "$BUS"
  } 9>> "$BUS" || { echo "[ERROR] lease taken, but appending TAKEOVER to $BUS failed" >&2; return 1; }
}

do_status() {
  if ! read_lease; then echo "lease: none ($FILE)"; return 4; fi
  print_lease
  if ! lease_live; then echo "state: expired"; return 4; fi
  if [[ "$L_ID" == "$ID" ]]; then echo "state: held by me"; return 0; fi
  echo "state: held by another id"; return 3
}

do_claim() {
  if read_lease; then
    if [[ "$L_ID" == "$ID" ]]; then
      write_lease "${L_SINCE:-$(now_ts)}"; echo "[OK] lease renewed by $ID"; return 0
    fi
    local state=expired
    lease_live && state=live
    if [[ "$state" == live && "$TAKEOVER" != true ]]; then
      echo "[REFUSED] lease held by '$L_ID' (last_seen $L_LAST, ttl ${L_TTL} min). Use --takeover only if that session is gone." >&2
      return 3
    fi
    local prev_id="$L_ID" prev_last="$L_LAST"
    write_lease "$(now_ts)"
    echo "[OK] lease claimed by $ID (previous holder '$prev_id', $state)"
    if [[ "$TAKEOVER" == true ]]; then
      append_takeover "$prev_id" "$prev_last" "$state" || return 1
      echo "[OK] TAKEOVER recorded in $BUS"
    else
      echo "[NOTE] Took an expired lease from '$prev_id'; consider posting a TAKEOVER entry to the bus." >&2
    fi
    return 0
  fi
  write_lease "$(now_ts)"
  echo "[OK] lease claimed by $ID"
}

do_renew() {
  if ! read_lease; then echo "[ERROR] no lease to renew ($FILE); use claim" >&2; return 4; fi
  if [[ "$L_ID" != "$ID" ]]; then
    if lease_live; then echo "[REFUSED] lease held by '$L_ID'" >&2; return 3; fi
    echo "[ERROR] lease expired and held by '$L_ID'; use claim" >&2; return 4
  fi
  write_lease "${L_SINCE:-$(now_ts)}"
  echo "[OK] lease renewed by $ID"
}

do_release() {
  if ! read_lease; then echo "[OK] no lease to release ($FILE)"; return 0; fi
  if [[ "$L_ID" != "$ID" ]]; then
    echo "[REFUSED] lease held by '$L_ID', not '$ID'" >&2; return 3
  fi
  rm -f "$FILE" || return 1
  echo "[OK] lease released by $ID"
}

# Serialize read-modify-write between concurrent callers: flock when present,
# else an exclusive-create lock file (<file>.excl.lock, bash noclobber = O_EXCL)
# with a bounded wait and stale reaping. The mkdir command is not used: some
# coreutils builds (e.g. uutils mkdir) are not atomic under races.
LOCK_WAIT="${AO_LEASE_LOCK_WAIT:-10}"    # seconds to wait for the lock
LOCK_STALE=300                           # a lock older than this is stale even if its pid lives
LOCK_F=""
OWN_LOCK=false

# O_EXCL create with "<pid> <epoch>" as content; fails if the file exists.
excl_create() { # $1 = path
  ( set -o noclobber; printf '%s %s\n' "$$" "$(now_epoch)" > "$1" ) 2>/dev/null
}

# shellcheck disable=SC2329  # invoked via trap
release_excl_lock() {
  if [[ "$OWN_LOCK" == true ]]; then
    rm -f "$LOCK_F"
    OWN_LOCK=false
  fi
}

# kill -0 fails with EPERM for another user's live process: count that as alive.
pid_alive() {
  local err
  err="$(kill -0 "$1" 2>&1)" && return 0
  [[ "$err" == *ermit* ]]
}

# Stale if the owner pid is gone, or the lock is older than LOCK_STALE, or it is
# empty and over a minute old (holder died between create and write).
lock_is_stale() { # $1 = lock path; prints the owner line it judged, for re-checking
  local owner pid started
  [[ -f "$1" ]] || return 1
  owner="$(cat "$1" 2>/dev/null || true)"
  if [[ -z "$owner" ]]; then
    [[ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]] || return 1
    echo "empty"; return 0
  fi
  pid="${owner%% *}"; started="${owner#* }"
  [[ "$pid" =~ ^[0-9]+$ && "$started" =~ ^[0-9]+$ ]] || { echo "$owner"; return 0; }
  if ! pid_alive "$pid" || (( $(now_epoch) - started > LOCK_STALE )); then
    echo "$owner"; return 0
  fi
  return 1
}

# One reaper at a time (its own exclusive lock file). It re-checks that the
# owner line is unchanged before removing, so a lock a live process just took is
# never deleted: only the owner releases, and a dead owner cannot re-take it.
reap_stale_lock() {
  local reap="${LOCK_F}.reap" seen again
  seen="$(lock_is_stale "$LOCK_F")" || return 0
  if ! excl_create "$reap"; then
    # A reaper killed mid-reap leaves this behind; clear it once it is stale.
    if lock_is_stale "$reap" >/dev/null; then rm -f "$reap"; fi
    return 0
  fi
  if again="$(lock_is_stale "$LOCK_F")" && [[ "$again" == "$seen" ]]; then
    echo "[WARN] removing stale lease lock $LOCK_F (owner: $seen)" >&2
    rm -f "$LOCK_F"
  fi
  rm -f "$reap"
}

acquire_excl_lock() {
  local deadline
  LOCK_F="${FILE}.excl.lock"
  deadline=$(( $(now_epoch) + LOCK_WAIT ))
  while ! excl_create "$LOCK_F"; do
    if [[ ! -e "$LOCK_F" ]]; then
      # Released between our attempt and this check: retry, unless create cannot work.
      [[ -w "$(dirname "$LOCK_F")" ]] || { echo "[ERROR] cannot create lock $LOCK_F" >&2; exit 1; }
      continue
    fi
    reap_stale_lock
    if (( $(now_epoch) >= deadline )); then
      echo "[ERROR] timed out after ${LOCK_WAIT}s waiting for lock $LOCK_F (remove it if no lease command is running)" >&2
      exit 1
    fi
    sleep 0.05 2>/dev/null || sleep 1
  done
  OWN_LOCK=true
  trap release_excl_lock EXIT
  trap 'exit 1' INT TERM HUP
}

run_locked() {
  local dir
  dir="$(dirname "$FILE")"
  if [[ "$ACTION" != status ]]; then
    mkdir -p "$dir" || exit 1
    if command -v flock >/dev/null 2>&1; then
      exec 8> "${FILE}.lock" || exit 1
      flock -x 8
    else
      acquire_excl_lock
    fi
  fi
  case "$ACTION" in
    claim) do_claim ;; renew) do_renew ;; release) do_release ;; status) do_status ;;
  esac
}

run_locked
exit $?
