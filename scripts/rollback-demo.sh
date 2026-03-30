#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-esmos}"
APP="${1:-moodle}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-180}"
DISPLAY_SECONDS="${DISPLAY_SECONDS:-8}"
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
    -o jsonpath="{.items[0].metadata.name}"
}

render_progress() {
  local elapsed="$1"
  local total="$2"
  local width=24
  local filled=0
  local percent=0

  if (( total > 0 )); then
    percent=$(( elapsed * 100 / total ))
    (( percent > 100 )) && percent=100
    filled=$(( elapsed * width / total ))
    (( filled > width )) && filled=width
  fi

  local empty=$(( width - filled ))
  printf "\r["
  printf "%${filled}s" "" | tr " " "#"
  printf "%${empty}s" "" | tr " " "-"
  printf "] %3d%%" "$percent"
}

complete_progress() {
  render_progress "$DISPLAY_SECONDS" "$DISPLAY_SECONDS"
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
echo "Thanos is here to wipe out a pod."
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
  elapsed=$((SECONDS - start_time))
  render_progress "$elapsed" "$DISPLAY_SECONDS"

  if [[ -n "$candidate" && "$candidate" != "$victim" ]]; then
    new_pod="$candidate"
    break
  fi

  sleep 1
done

if [[ -z "$new_pod" ]]; then
  echo
  echo "A replacement pod did not appear within ${TIMEOUT_SECONDS}s."
  exit 1
fi

complete_progress
echo "Replacement pod spotted: $new_pod"
echo "Waiting for it to become Ready..."
deadline=$((SECONDS + TIMEOUT_SECONDS))
start_time=$SECONDS

while (( SECONDS < deadline )); do
  ready_state="$(pod_ready "$new_pod" || true)"
  elapsed=$((SECONDS - start_time))
  render_progress "$elapsed" "$DISPLAY_SECONDS"

  if [[ "$ready_state" == "true" ]]; then
    break
  fi

  sleep 1
done

if [[ "$(pod_ready "$new_pod" || true)" != "true" ]]; then
  echo
  echo "The replacement pod appeared, but it did not become Ready within ${TIMEOUT_SECONDS}s."
  exit 1
fi

complete_progress

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
