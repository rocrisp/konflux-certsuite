#!/usr/bin/env bash
set -euo pipefail

# Acquires a Kubernetes Lease-based mutex on the shared test cluster.
# Waits up to LOCK_TIMEOUT seconds for the lock to become available.
# Sets a TTL annotation so stale leases from crashed runs auto-expire.

LOCK_NAME="${LOCK_NAME:?LOCK_NAME is required}"
LOCK_NAMESPACE="${LOCK_NAMESPACE:-certsuite-locks}"
OWNER="${OWNER:?OWNER is required}"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-1800}"
LEASE_TTL="${LEASE_TTL:-3600}"

echo "[$(date -u +%FT%T.%3NZ)] Attempting to acquire lock '${LOCK_NAME}' in namespace '${LOCK_NAMESPACE}'"
echo "[$(date -u +%FT%T.%3NZ)] Owner: ${OWNER}, Timeout: ${LOCK_TIMEOUT}s, TTL: ${LEASE_TTL}s"

oc create namespace "${LOCK_NAMESPACE}" 2>/dev/null || true

EXPIRY=$(date -u -d "+${LEASE_TTL} seconds" +%FT%T.%3NZ 2>/dev/null) \
  || EXPIRY=$(date -u -v "+${LEASE_TTL}S" +%FT%T.%3NZ 2>/dev/null) \
  || EXPIRY="unknown"

ELAPSED=0
POLL_INTERVAL=15

while true; do
  if oc create -f - <<EOF 2>/dev/null
apiVersion: coordination.k8s.io/v1
kind: Lease
metadata:
  name: ${LOCK_NAME}
  namespace: ${LOCK_NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: konflux-certsuite
    certsuite-lock/owner: "${OWNER}"
  annotations:
    certsuite-lock/expires-at: "${EXPIRY}"
    certsuite-lock/acquired-at: "$(date -u +%FT%T.%3NZ)"
spec:
  holderIdentity: "${OWNER}"
  leaseDurationSeconds: ${LEASE_TTL}
EOF
  then
    echo "[$(date -u +%FT%T.%3NZ)] Lock acquired successfully"
    exit 0
  fi

  EXISTING_OWNER=$(oc get lease "${LOCK_NAME}" -n "${LOCK_NAMESPACE}" \
    -o jsonpath='{.spec.holderIdentity}' 2>/dev/null || echo "unknown")
  EXISTING_EXPIRY=$(oc get lease "${LOCK_NAME}" -n "${LOCK_NAMESPACE}" \
    -o jsonpath='{.metadata.annotations.certsuite-lock/expires-at}' 2>/dev/null || echo "unknown")

  echo "[$(date -u +%FT%T.%3NZ)] Lock held by '${EXISTING_OWNER}' (expires: ${EXISTING_EXPIRY}). Waiting... (${ELAPSED}/${LOCK_TIMEOUT}s)"

  # Check if the existing lease has expired (stale lock from a crash)
  if [[ "${EXISTING_EXPIRY}" != "unknown" ]]; then
    NOW_EPOCH=$(date -u +%s)
    EXPIRY_EPOCH=$(date -u -d "${EXISTING_EXPIRY}" +%s 2>/dev/null) \
      || EXPIRY_EPOCH=$(date -u -j -f "%FT%T" "${EXISTING_EXPIRY%%.*}" +%s 2>/dev/null) \
      || EXPIRY_EPOCH=0

    if [[ ${NOW_EPOCH} -gt ${EXPIRY_EPOCH} && ${EXPIRY_EPOCH} -gt 0 ]]; then
      echo "[$(date -u +%FT%T.%3NZ)] Existing lease has expired. Deleting stale lock."
      oc delete lease "${LOCK_NAME}" -n "${LOCK_NAMESPACE}" --ignore-not-found
      continue
    fi
  fi

  if [[ ${ELAPSED} -ge ${LOCK_TIMEOUT} ]]; then
    echo "[$(date -u +%FT%T.%3NZ)] ERROR: Timed out waiting for lock after ${LOCK_TIMEOUT}s"
    exit 1
  fi

  sleep ${POLL_INTERVAL}
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
done
