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
[[ "$ID" =~ ^[A-Za-z0-9@._:/+()\ -]{1,120}$ ]] || die_usage "--id may only contain letters, digits, spaces and @._:/+()- (max 120)"
[[ "$TAKEOVER" == false || "$ACTION" == claim ]] || die_usage "--takeover is only valid with claim"

now_epoch() { date -u +%s; }
now_ts() { date -u '+%Y-%m-%d %H:%M:%S UTC'; }

L_ID=""; L_SINCE=""; L_LAST=""; L_TTL=""; L_EPOCH=""
read_lease() {
  L_ID=""; L_SINCE=""; L_LAST=""; L_TTL=""; L_EPOCH=""
  [[ -f "$FILE" ]] || return 1
  local k v
  while IFS='=' read -r k v; do
    case "$k" in
      id) L_ID="$v" ;; since) L_SINCE="$v" ;; last_seen) L_LAST="$v" ;;
      ttl_min) L_TTL="$v" ;; last_seen_epoch) L_EPOCH="$v" ;;
    esac
  done < "$FILE"
  [[ -n "$L_ID" ]]
}

# 0 = live, 1 = expired (a malformed lease counts as expired)
lease_live() {
  [[ "$L_EPOCH" =~ ^[0-9]+$ && "$L_TTL" =~ ^[0-9]+$ ]] || return 1
  (( $(now_epoch) < L_EPOCH + L_TTL * 60 ))
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

# Serialize read-modify-write between concurrent callers.
run_locked() {
  local dir lock
  dir="$(dirname "$FILE")"
  if [[ "$ACTION" != status ]]; then mkdir -p "$dir" || exit 1; fi
  lock="${FILE}.lock"
  if [[ "$ACTION" != status ]] && command -v flock >/dev/null 2>&1; then
    exec 8> "$lock" || exit 1
    flock -x 8
  fi
  case "$ACTION" in
    claim) do_claim ;; renew) do_renew ;; release) do_release ;; status) do_status ;;
  esac
}

run_locked
exit $?
