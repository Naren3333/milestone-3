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

if [[ "$USE_SUDO" == "1" ]]; then
  KCTL=(sudo kubectl)
else
  KCTL=(kubectl)
fi

kctl() {
  "${KCTL[@]}" "$@"
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

  printf "\r%-12s" "$frame"
}

complete_wait_dots() {
  printf "\r. . .       \n"
  echo
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
echo "=== Kubernetes Rollback Demo ==="
echo "Namespace : $NAMESPACE"
echo "App       : $APP"
echo "Victim    : $victim"
echo "Kubectl   : ${KCTL[*]}"
echo
echo "Uh oh, pod is being killed."
kctl -n "$NAMESPACE" get pods -l "app=$APP" -o wide
echo

kctl -n "$NAMESPACE" delete pod "$victim" --wait=false

echo
echo "Waiting for Kubernetes to summon the replacement..."

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
echo "Replacement pod spotted: $new_pod"
echo "Pod in progress of coming back to life..."
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
echo "Pod recovered. Current status:"
kctl -n "$NAMESPACE" get pods -l "app=$APP" -o wide

if [[ "$APP" == "moodle" ]]; then
  echo
  echo "Quick Moodle check:"
  curl -ksSI --max-time 10 "https://moodlestaging.centralindia.cloudapp.azure.com" | head -n 1
fi

echo
echo "Demo complete. Kubernetes successfully recreated the pod."
