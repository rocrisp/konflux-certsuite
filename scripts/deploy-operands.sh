#!/usr/bin/env bash
set -euo pipefail

# Deploys operand manifests from a certsuite test bundle.
# The test bundle is a directory containing:
#   certsuite-test-bundle.yaml  -- bundle metadata
#   operands/                   -- Kubernetes manifests to apply
#   certsuite_config.yml        -- certsuite configuration

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR is required}"
INSTALL_NAMESPACE="${INSTALL_NAMESPACE:?INSTALL_NAMESPACE is required}"
READINESS_TIMEOUT="${READINESS_TIMEOUT:-300}"

echo "[$(date -u +%FT%T.%3NZ)] Deploying operands from test bundle: ${BUNDLE_DIR}"

if [[ ! -f "${BUNDLE_DIR}/certsuite-test-bundle.yaml" ]]; then
  echo "ERROR: certsuite-test-bundle.yaml not found in ${BUNDLE_DIR}" >&2
  exit 1
fi

# Parse bundle metadata
BUNDLE_NAME=$(yq e '.metadata.name' "${BUNDLE_DIR}/certsuite-test-bundle.yaml")
BUNDLE_NAMESPACE=$(yq e '.spec.namespace // ""' "${BUNDLE_DIR}/certsuite-test-bundle.yaml")
TARGET_NS="${BUNDLE_NAMESPACE:-${INSTALL_NAMESPACE}}"

echo "[$(date -u +%FT%T.%3NZ)] Test bundle: ${BUNDLE_NAME}"
echo "[$(date -u +%FT%T.%3NZ)] Target namespace: ${TARGET_NS}"

# Create target namespace if it differs from install namespace
if [[ "${TARGET_NS}" != "${INSTALL_NAMESPACE}" ]]; then
  oc create namespace "${TARGET_NS}" 2>/dev/null || true
fi

# Apply pre-requisites (secrets, configmaps, etc.) if specified
PRE_REQS_DIR="${BUNDLE_DIR}/prerequisites"
if [[ -d "${PRE_REQS_DIR}" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] Applying prerequisites..."
  for f in "${PRE_REQS_DIR}"/*.yaml "${PRE_REQS_DIR}"/*.yml; do
    [[ -f "${f}" ]] || continue
    echo "  Applying: $(basename "${f}")"
    oc apply -n "${TARGET_NS}" -f "${f}"
  done
fi

# Apply operand manifests
OPERANDS_DIR="${BUNDLE_DIR}/operands"
if [[ ! -d "${OPERANDS_DIR}" ]]; then
  echo "ERROR: operands/ directory not found in ${BUNDLE_DIR}" >&2
  exit 1
fi

echo "[$(date -u +%FT%T.%3NZ)] Applying operand manifests..."
for f in "${OPERANDS_DIR}"/*.yaml "${OPERANDS_DIR}"/*.yml; do
  [[ -f "${f}" ]] || continue
  echo "  Applying: $(basename "${f}")"
  oc apply -n "${TARGET_NS}" -f "${f}"
done

# Wait for all Deployments to be ready
echo "[$(date -u +%FT%T.%3NZ)] Waiting for Deployments to become ready (timeout: ${READINESS_TIMEOUT}s)..."
DEPLOYMENTS=$(oc get deployments -n "${TARGET_NS}" \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

for DEP in ${DEPLOYMENTS}; do
  echo "  Waiting for deployment/${DEP}..."
  if ! oc rollout status "deployment/${DEP}" -n "${TARGET_NS}" --timeout="${READINESS_TIMEOUT}s"; then
    echo "WARNING: deployment/${DEP} did not become ready within ${READINESS_TIMEOUT}s"
  fi
done

# Wait for all StatefulSets to be ready
STATEFULSETS=$(oc get statefulsets -n "${TARGET_NS}" \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

for SS in ${STATEFULSETS}; do
  echo "  Waiting for statefulset/${SS}..."
  if ! oc rollout status "statefulset/${SS}" -n "${TARGET_NS}" --timeout="${READINESS_TIMEOUT}s"; then
    echo "WARNING: statefulset/${SS} did not become ready within ${READINESS_TIMEOUT}s"
  fi
done

# Store target namespace for downstream
echo -n "${TARGET_NS}" > /workspace/operand-namespace

echo "[$(date -u +%FT%T.%3NZ)] Operand deployment complete"
