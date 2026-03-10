#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANTISSH_SH="${SCRIPT_DIR}/antissh.sh"

CLEANUP_ONLY=0
BACKEND="${ANTISSH_PROXY_BACKEND:-gg}"
BACKEND_SOURCE="env/default"

usage() {
  cat <<'USAGE'
Usage: refresh_antissh.sh [--cleanup-only] [--backend gg|graftcp]

Options:
  --cleanup-only      only cleanup stale processes/files
  --backend, -b       rerun antissh.sh with the selected backend
  -h, --help          show this help

Examples:
  bash ~/antissh/refresh_antissh.sh
  bash ~/antissh/refresh_antissh.sh --backend gg
  bash ~/antissh/refresh_antissh.sh --backend graftcp
  bash ~/antissh/refresh_antissh.sh --cleanup-only
USAGE
}

normalize_backend() {
  case "$1" in
    gg|GG|go-graft|gograft)
      echo "gg"
      ;;
    graftcp|GRAFTCP)
      echo "graftcp"
      ;;
    *)
      echo ""
      ;;
  esac
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cleanup-only)
        CLEANUP_ONLY=1
        shift
        ;;
      --backend|-b)
        if [ "$#" -lt 2 ]; then
          echo "[ERROR] $1 requires a value: gg or graftcp"
          exit 2
        fi
        BACKEND="$(normalize_backend "$2")"
        if [ -z "${BACKEND}" ]; then
          echo "[ERROR] unsupported backend: $2"
          exit 2
        fi
        BACKEND_SOURCE="cli"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "[ERROR] unknown argument: $1"
        usage
        exit 2
        ;;
    esac
  done

  BACKEND="$(normalize_backend "${BACKEND}")"
  if [ -z "${BACKEND}" ]; then
    echo "[ERROR] unsupported backend in ANTISSH_PROXY_BACKEND"
    exit 2
  fi
}

if [ ! -f "${ANTISSH_SH}" ]; then
  echo "[ERROR] antissh.sh not found at: ${ANTISSH_SH}"
  exit 1
fi

log() {
  echo "[refresh-antissh] $*"
}

kill_patterns=()

collect_pids() {
  kill_patterns=()

  while IFS= read -r pid; do
    [ -n "$pid" ] && kill_patterns+=("$pid")
  done < <(pgrep -u "$USER" -x language_server 2>/dev/null || true)

  while IFS= read -r pid; do
    [ -n "$pid" ] && kill_patterns+=("$pid")
  done < <(pgrep -u "$USER" -f "$HOME/.antigravity-server/.*/language_server_linux_" 2>/dev/null || true)

  while IFS= read -r pid; do
    [ -n "$pid" ] && kill_patterns+=("$pid")
  done < <(pgrep -u "$USER" -f "graftcp-local" 2>/dev/null || true)

  while IFS= read -r pid; do
    [ -n "$pid" ] && kill_patterns+=("$pid")
  done < <(pgrep -u "$USER" -f "$HOME/.graftcp-antigravity/gg/gg" 2>/dev/null || true)

  while IFS= read -r pid; do
    [ -n "$pid" ] && kill_patterns+=("$pid")
  done < <(pgrep -u "$USER" -f "$HOME/.graftcp-antigravity/graftcp/graftcp" 2>/dev/null || true)

  if [ ${#kill_patterns[@]} -gt 0 ]; then
    mapfile -t kill_patterns < <(printf '%s\n' "${kill_patterns[@]}" | sort -u)
  fi
}

cleanup_processes() {
  collect_pids

  if [ ${#kill_patterns[@]} -eq 0 ]; then
    log "no stale antissh-related processes found"
    return 0
  fi

  log "found stale processes: ${kill_patterns[*]}"
  ps -fp "${kill_patterns[@]}" || true

  log "sending SIGTERM..."
  kill -TERM "${kill_patterns[@]}" 2>/dev/null || true

  for _ in $(seq 1 20); do
    sleep 0.2
    collect_pids
    [ ${#kill_patterns[@]} -eq 0 ] && break
  done

  if [ ${#kill_patterns[@]} -gt 0 ]; then
    log "still alive after SIGTERM, sending SIGKILL: ${kill_patterns[*]}"
    kill -KILL "${kill_patterns[@]}" 2>/dev/null || true
  fi

  collect_pids
  if [ ${#kill_patterns[@]} -gt 0 ]; then
    log "warning: some processes are still alive: ${kill_patterns[*]}"
  else
    log "process cleanup done"
  fi
}

cleanup_files() {
  local install_root="$HOME/.graftcp-antigravity"

  rm -f "$install_root"/graftcp-local-*.fifo 2>/dev/null || true
  rm -f /tmp/server_* 2>/dev/null || true

  log "removed stale fifo/temp markers (if any)"
}

show_context() {
  local root="$HOME/.antigravity-server/bin"
  local latest_name=""

  if [ ! -d "$root" ]; then
    log "no ~/.antigravity-server/bin directory found yet; connect once from client first"
    return 0
  fi

  latest_name="$(find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1 || true)"
  if [ -n "$latest_name" ]; then
    log "latest antigravity server dir (by version): $root/$latest_name"
  else
    log "no ~/.antigravity-server/bin/* found yet; connect once from client first"
  fi
}

parse_args "$@"

log "selected backend: ${BACKEND} (source: ${BACKEND_SOURCE})"
log "step 1/3: cleanup stale processes"
cleanup_processes

log "step 2/3: cleanup stale files"
cleanup_files

log "step 3/3: show current antigravity server version dir"
show_context

if [ "$CLEANUP_ONLY" -eq 1 ]; then
  log "cleanup-only mode complete"
  exit 0
fi

log "re-running antissh.sh with backend=${BACKEND} ..."
exec bash "$ANTISSH_SH" --backend "$BACKEND"
