#!/bin/sh
set -eu

repository="${VAR_SCOPE_REPOSITORY:-dorta/var-scope}"
channel="${VAR_SCOPE_VERSION:-main}"
image="${VAR_SCOPE_IMAGE:-var-scope:local}"
default_raw="https://raw.githubusercontent.com/${repository}/${channel}"
raw_base="${VAR_SCOPE_RAW_BASE:-${default_raw}}"
install_dir="${VAR_SCOPE_INSTALL_DIR:-/opt/var-scope}"
config_file="/etc/default/var-scope"
log_dir="${VAR_SCOPE_LOG_DIR:-/var/log/var-scope}"
log_file="$log_dir/install.log"
step_total=8
step_number=0
progress_drawn=false

setup_style() {
  interactive=false
  bold=''
  dim=''
  green=''
  red=''
  reset=''
  if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
    interactive=true
    bold='\033[1m'
    dim='\033[2m'
    green='\033[32m'
    red='\033[31m'
    reset='\033[0m'
  fi
}

fail() {
  printf '\n%bInstallation failed%b\n' "$red" "$reset" >&2
  printf '  %s\n' "$*" >&2
  if [ -s "${log_file:-}" ]; then
    printf '\n  Last log entries:\n' >&2
    tail -n 12 "$log_file" | sed 's/^/    /' >&2
    printf '\n  Full log: %s\n' "$log_file" >&2
  fi
  exit 1
}

render_progress() {
  marker="$1"
  marker_color="${2:-}"
  elapsed=$(($(date +%s) - started))
  minutes=$((elapsed / 60))
  seconds=$((elapsed % 60))
  if [ "$progress_drawn" = true ]; then
    printf '\r\033[1A'
  fi
  printf '\r\033[2K  '
  position=1
  while [ "$position" -le "$step_total" ]; do
    if [ "$position" -lt "$step_number" ]; then
      printf '%b%02d%b  ' "$green" "$position" "$reset"
    elif [ "$position" -eq "$step_number" ]; then
      printf '%b[%02d]%b  ' "$bold" "$position" "$reset"
    else
      printf '%b%02d%b  ' "$dim" "$position" "$reset"
    fi
    position=$((position + 1))
  done
  printf '\n'
  printf '\r\033[2K  %-40s %b%-6s%b %02d:%02d' \
    "$label" "$marker_color" "$marker" "$reset" \
    "$minutes" "$seconds"
  progress_drawn=true
}

clear_progress() {
  if [ "$interactive" = true ] && [ "$progress_drawn" = true ]; then
    printf '\r\033[2K\033[1A\r\033[2K'
    progress_drawn=false
  fi
}

run_step() {
  label="$1"
  shift
  step_number=$((step_number + 1))
  started="$(date +%s)"
  if [ "$interactive" = false ]; then
    printf '  [%s/%s] %-34s' "$step_number" "$step_total" "$label"
  fi
  "$@" >>"$log_file" 2>&1 &
  task_pid=$!
  frame=0
  while [ "$interactive" = true ] && \
    kill -0 "$task_pid" 2>/dev/null; do
    case "$frame" in
      0) marker='|' ;;
      1) marker='/' ;;
      2) marker='-' ;;
      *) marker='\' ;;
    esac
    render_progress "$marker"
    frame=$(((frame + 1) % 4))
    sleep 1
  done
  if wait "$task_pid"; then
    if [ "$interactive" = true ]; then
      render_progress 'OK' "$green"
    else
      elapsed=$(($(date +%s) - started))
      printf ' %bDONE%b  %ss\n' "$green" "$reset" "$elapsed"
    fi
  else
    result=$?
    if [ "$interactive" = true ]; then
      render_progress 'FAILED' "$red"
      printf '\n'
    else
      printf ' %bFAILED%b\n' "$red" "$reset"
    fi
    fail "$label returned exit code $result"
  fi
}

recover_system_time() {
  clock_url="https://github.com"
  if curl -fsSI "$clock_url" >/dev/null 2>&1; then
    return 0
  fi
  header="$(curl -kfsSIL "$clock_url" | tr -d '\r' | \
    sed -n 's/^[Dd]ate: //p' | head -n 1)"
  set -- $header
  case "${3:-}" in
    Jan) month=01 ;; Feb) month=02 ;; Mar) month=03 ;;
    Apr) month=04 ;; May) month=05 ;; Jun) month=06 ;;
    Jul) month=07 ;; Aug) month=08 ;; Sep) month=09 ;;
    Oct) month=10 ;; Nov) month=11 ;; Dec) month=12 ;;
    *) return 1 ;;
  esac
  date -u -s "$4-$month-$2 $5" >/dev/null
}

check_platform() {
  [ "$(id -u)" -eq 0 ] || return 10
  command -v curl >/dev/null 2>&1 || return 11
  command -v docker >/dev/null 2>&1 || return 12
  command -v systemctl >/dev/null 2>&1 || return 13
  command -v tar >/dev/null 2>&1 || return 14
  case "$(uname -m)" in
    aarch64 | arm64 | armv7l) return 0 ;;
    *) return 15 ;;
  esac
}

fetch_deployment() {
  for file in VERSION scripts/var-scope scripts/var-scope-stack \
    packaging/var-scope-stack.service \
    packaging/var-scope-demo-runner.service \
    packaging/var-scope-camera-runner.service; do
    destination="$temporary/$(basename "$file")"
    curl -fsSL "$raw_base/$file" -o "$destination" || return 1
  done
}

prepare_runtime() {
  systemctl enable --now docker.service
  systemctl enable --now systemd-timesyncd.service || true
}

fetch_source() {
  mkdir -p "$source_dir"
  curl -fsSL "$archive_url" -o "$archive" || return 1
  tar -xzf "$archive" -C "$source_dir" --strip-components=1
}

build_image() {
  if docker buildx version >/dev/null 2>&1; then
    printf 'Builder: Docker Buildx\n'
    docker buildx build --load --pull \
      --build-arg TARGETARCH="$target_arch" \
      -t "$image" "$source_dir"
  else
    printf 'Builder: Docker legacy compatibility mode\n'
    docker build --pull \
      --build-arg TARGETARCH="$target_arch" \
      -t "$image" "$source_dir"
  fi
}

write_config() {
  {
    printf 'VAR_SCOPE_IMAGE=%s\n' "$image"
    printf 'VAR_SCOPE_VERSION=%s\n' "$release"
    printf 'VAR_SCOPE_REPOSITORY=%s\n' "$repository"
    printf 'VAR_SCOPE_CHANNEL=%s\n' "$channel"
    printf 'VAR_SCOPE_RAW_BASE=%s\n' "$raw_base"
    printf 'VAR_SCOPE_PORT=9090\n'
  } >"$config_file"
}

install_files() {
  mkdir -p "$install_dir/bin" /usr/bin
  cp "$temporary/var-scope" /usr/bin/var-scope
  cp "$temporary/var-scope-stack" \
    "$install_dir/bin/var-scope-stack"
  cp "$temporary/var-scope-stack.service" \
    /etc/systemd/system/var-scope-stack.service
  cp "$temporary/var-scope-demo-runner.service" \
    /etc/systemd/system/var-scope-demo-runner.service
  cp "$temporary/var-scope-camera-runner.service" \
    /etc/systemd/system/var-scope-camera-runner.service
  chmod 0755 /usr/bin/var-scope \
    "$install_dir/bin/var-scope-stack"
  chmod 0644 /etc/systemd/system/var-scope-stack.service \
    /etc/systemd/system/var-scope-demo-runner.service \
    /etc/systemd/system/var-scope-camera-runner.service
  printf '%s\n' "$release" >"$install_dir/VERSION"
  write_config
  docker create --name "$container" "$image" >/dev/null
  docker cp "$container:/var-scope" \
    "$install_dir/bin/var-scope-server"
  chmod 0755 "$install_dir/bin/var-scope-server"
  docker rm "$container" >/dev/null
}

enable_services() {
  systemctl daemon-reload
  systemctl enable var-scope-demo-runner.service \
    var-scope-camera-runner.service var-scope-stack.service
  systemctl restart var-scope-demo-runner.service \
    var-scope-camera-runner.service
  systemctl restart var-scope-stack.service
}

wait_for_dashboard() {
  attempt=0
  while [ "$attempt" -lt 30 ]; do
    if curl -fsS http://127.0.0.1:9090/api/v1/snapshot \
      >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done
  return 1
}

setup_style
printf '\n%bVAR-Scope%b\n' "$bold" "$reset"
printf 'Board Diagnostics Setup\n'
printf '%b(c) 2026 Variscite Ltd.%b\n\n' "$dim" "$reset"
printf '  %-10s %s (%s)\n' 'Device' "$(hostname)" "$(uname -m)"
printf '  %-10s %s\n\n' 'Method' 'Local Docker build'

[ "$(id -u)" -eq 0 ] || fail 'run this installer as root'

mkdir -p "$log_dir"
: >"$log_file"
printf 'Started: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  >>"$log_file"

recover_system_time >>"$log_file" 2>&1 || fail \
  'unable to establish a valid system clock'

check_platform || fail \
  'requires root, Docker, curl, systemd, tar, and a supported ARM CPU'
case "$(uname -m)" in
  aarch64 | arm64) target_arch=arm64 ;;
  armv7l) target_arch=arm ;;
esac

temporary="$(mktemp -d)"
container="var-scope-installer-$$"
archive="$temporary/source.tar.gz"
source_dir="$temporary/source"
archive_url="https://codeload.github.com/${repository}/tar.gz/"
archive_url="${archive_url}refs/heads/${channel}"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  rm -rf "$temporary"
}
trap cleanup EXIT INT TERM

run_step 'Checking board and runtime' check_platform
run_step 'Downloading deployment files' fetch_deployment
release="$(tr -d '[:space:]' <"$temporary/VERSION")"
[ -n "$release" ] || fail 'downloaded VERSION is empty'
run_step 'Preparing Docker runtime' prepare_runtime
run_step 'Downloading source code' fetch_source
run_step 'Building container image' build_image
run_step 'Installing system files' install_files
run_step 'Starting system services' enable_services
run_step 'Verifying dashboard' wait_for_dashboard
clear_progress

dashboard_url="$(/usr/bin/var-scope url | awk '
  $1 == "Network" { print $2; exit }
')"
printf '\n%bVAR-Scope %s installed%b\n\n' \
  "$green" "$release" "$reset"
printf '  %-12s %b%s%b\n' 'Status' "$green" 'RUNNING' "$reset"
printf '  %-12s %s\n' 'Dashboard' "$dashboard_url"
printf '  %-12s %s\n' 'Command' 'var-scope status'
printf '\n'
trap - EXIT INT TERM
cleanup
