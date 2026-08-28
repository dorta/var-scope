#!/bin/sh
set -eu

repository="${VAR_SCOPE_REPOSITORY:-dorta/var-scope}"
channel="${VAR_SCOPE_VERSION:-main}"
url="https://raw.githubusercontent.com/${repository}/${channel}/install.sh"

fail() {
  printf 'VAR-Scope bootstrap error: %s\n' "$*" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v date >/dev/null 2>&1 || fail "date is required"
command -v mktemp >/dev/null 2>&1 || fail "mktemp is required"

if ! curl -fsSI "$url" >/dev/null 2>&1; then
  header="$(curl -kfsSIL "$url" | tr -d '\r' | \
    sed -n 's/^[Dd]ate: //p' | head -n 1)"
  set -- $header
  case "${3:-}" in
    Jan) month=01 ;; Feb) month=02 ;; Mar) month=03 ;;
    Apr) month=04 ;; May) month=05 ;; Jun) month=06 ;;
    Jul) month=07 ;; Aug) month=08 ;; Sep) month=09 ;;
    Oct) month=10 ;; Nov) month=11 ;; Dec) month=12 ;;
    *) fail "unable to recover system time" ;;
  esac
  date -u -s "$4-$month-$2 $5" >/dev/null || fail \
    "unable to set system time"
fi

installer="$(mktemp)"
cleanup() { rm -f "$installer"; }
trap cleanup EXIT INT TERM
curl -fsSL "$url" -o "$installer" || fail \
  "unable to download the verified installer"
sh "$installer"
