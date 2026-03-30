#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-esmos}"
APP="${1:-moodle}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
DOT_DELAY_SECONDS="${DOT_DELAY_SECONDS:-1}"
USE_SUDO="${USE_SUDO:-1}"

case "$APP" in
  moodle|moodledb|uptimekuma)
    ;;
  *)
    echo "Usage: bash scripts/rollback-demo.sh [moodle|moodledb|uptimekuma]"
    exit 1
    ;;
esac

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required for this demo."
  exit 1
fi

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'
  RED=$'\033[31m'
  YELLOW=$'\033[33m'
  GREEN=$'\033[32m'
  CYAN=$'\033[36m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'
else
  BOLD=""
  RED=""
  YELLOW=""
  GREEN=""
  CYAN=""
  DIM=""
  RESET=""
fi

TERM_WIDTH="$(tput cols 2>/dev/null || echo 80)"
WAIT_WIDTH=12
WAIT_PAD=$(( (TERM_WIDTH - WAIT_WIDTH) / 2 ))
(( WAIT_PAD < 0 )) && WAIT_PAD=0

if [[ "$USE_SUDO" == "1" ]]; then
  KCTL=(sudo kubectl)
else
  KCTL=(kubectl)
fi

kctl() {
  "${KCTL[@]}" "$@"
}

center_text() {
  local text="$1"
  local color="${2:-}"
  local pad=$(( (TERM_WIDTH - ${#text}) / 2 ))
  (( pad < 0 )) && pad=0
  printf "%*s%b%s%b\n" "$pad" "" "$color" "$text" "$RESET"
}

print_stage() {
  local text="$1"
  local color="${2:-$CYAN}"
  echo
  center_text "$text" "${BOLD}${color}"
}

print_detail() {
  local label="$1"
  local value="$2"
  printf "%b%-10s%b %s\n" "$DIM" "$label" "$RESET" "$value"
}

if ! kctl -n "$NAMESPACE" get deployment "$APP" >/dev/null 2>&1; then
  echo "Deployment '$APP' was not found in namespace '$NAMESPACE'."
  exit 1
fi

pick_victim() {
  kctl -n "$NAMESPACE" get pods \
    -l "app=$APP" \
    --field-selector=status.phase=Running \
    --no-headers \
    -o custom-columns=":metadata.name" 2>/dev/null | head -n 1
}

render_wait_dots() {
  local tick="$1"
  local frame=""

  case $(( tick % 3 )) in
    0) frame="." ;;
    1) frame=". ." ;;
    2) frame=". . ." ;;
  esac

  printf "\r%*s%b%-12s%b" "$WAIT_PAD" "" "$CYAN" "$frame" "$RESET"
}

complete_wait_dots() {
  printf "\r%*s%b%-12s%b\n" "$WAIT_PAD" "" "$GREEN" ". . ." "$RESET"
}

pod_ready() {
  local pod_name="$1"
  kctl -n "$NAMESPACE" get pod "$pod_name" \
    -o jsonpath="{.status.containerStatuses[0].ready}" 2>/dev/null
}

victim="$(pick_victim)"

if [[ -z "$victim" ]]; then
  echo "No running pod found for app '$APP'."
  exit 1
fi

echo
center_text "LIVE DEMO" "${BOLD}${CYAN}"
center_text "Kubernetes Self-Healing in Action" "$DIM"
echo
print_detail "Namespace:" "$NAMESPACE"
print_detail "App:" "$APP"
print_detail "Victim:" "$victim"
print_detail "Kubectl:" "${KCTL[*]}"
print_stage "Uh oh, pod is being killed." "$YELLOW"
kctl -n "$NAMESPACE" get pods -l "app=$APP" -o wide
echo

kctl -n "$NAMESPACE" delete pod "$victim" --wait=false

print_stage "Waiting for Kubernetes to summon the replacement" "$CYAN"

deadline=$((SECONDS + TIMEOUT_SECONDS))
new_pod=""
start_time=$SECONDS

while (( SECONDS < deadline )); do
  candidate="$(pick_victim || true)"
  render_wait_dots $((SECONDS - start_time))

  if [[ -n "$candidate" && "$candidate" != "$victim" ]]; then
    new_pod="$candidate"
    break
  fi

  sleep "$DOT_DELAY_SECONDS"
done

if [[ -z "$new_pod" ]]; then
  echo
  echo "A replacement pod did not appear within ${TIMEOUT_SECONDS}s."
  exit 1
fi

complete_wait_dots
print_stage "Replacement pod spotted: $new_pod" "$GREEN"
print_stage "Pod in progress of coming back to life..." "$CYAN"
deadline=$((SECONDS + TIMEOUT_SECONDS))
start_time=$SECONDS

while (( SECONDS < deadline )); do
  ready_state="$(pod_ready "$new_pod" || true)"
  render_wait_dots $((SECONDS - start_time))

  if [[ "$ready_state" == "true" ]]; then
    break
  fi

  sleep "$DOT_DELAY_SECONDS"
done

if [[ "$(pod_ready "$new_pod" || true)" != "true" ]]; then
  echo
  echo "The replacement pod appeared, but it did not become Ready within ${TIMEOUT_SECONDS}s."
  exit 1
fi

complete_wait_dots

echo
print_stage "Pod recovered." "$GREEN"
echo "Current status:"
kctl -n "$NAMESPACE" get pods -l "app=$APP" -o wide

if [[ "$APP" == "moodle" ]]; then
  echo
  print_stage "Quick Moodle check" "$CYAN"
  curl -ksSI --max-time 10 "https://moodlestaging.centralindia.cloudapp.azure.com" | head -n 1
fi

print_stage "Demo complete. Kubernetes successfully recreated the pod." "$GREEN"
