#!/usr/bin/env bash
set -euo pipefail

# Deploys an OLM-managed operator on the shared cluster.
# Adapted from the deploy-fbc-operator pipeline in tekton-integration-catalog.

FBC_FRAGMENT="${FBC_FRAGMENT:?FBC_FRAGMENT is required}"
BUNDLE_IMAGE="${BUNDLE_IMAGE:?BUNDLE_IMAGE is required}"
PACKAGE_NAME="${PACKAGE_NAME:?PACKAGE_NAME is required}"
CHANNEL_NAME="${CHANNEL_NAME:?CHANNEL_NAME is required}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/workspace/konflux-artifacts}"

mkdir -p "${ARTIFACT_DIR}"

echo "[$(date -u +%FT%T.%3NZ)] Deploying operator: package=${PACKAGE_NAME}, channel=${CHANNEL_NAME}"
echo "[$(date -u +%FT%T.%3NZ)] FBC Fragment: ${FBC_FRAGMENT}"
echo "[$(date -u +%FT%T.%3NZ)] Bundle Image: ${BUNDLE_IMAGE}"

oc whoami || { echo "ERROR: Failed to connect to cluster"; exit 1; }

if ! bundle_render_out=$(opm render "${BUNDLE_IMAGE}"); then
  echo "ERROR: Failed to render the bundle image" >&2
  exit 1
fi

# Determine install namespace from bundle metadata
INSTALL_NAMESPACE=$(echo "${bundle_render_out}" | \
  jq -r 'select(.schema == "olm.bundle") | .properties[]? |
  select(.type == "olm.bundle.object") | .value.data' 2>/dev/null | \
  base64 -d 2>/dev/null | \
  jq -r 'select(.kind == "ClusterServiceVersion") |
  .metadata.annotations["operatorframework.io/suggested-namespace"] // empty' 2>/dev/null | \
  head -1)

if [[ -z "${INSTALL_NAMESPACE}" || "${INSTALL_NAMESPACE}" == "null" ]]; then
  echo "[$(date -u +%FT%T.%3NZ)] No suggested namespace found, creating a new one"
  INSTALL_NAMESPACE=$(oc create -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: v1
kind: Namespace
metadata:
  generateName: oo-
EOF
  )
elif ! oc get namespace "${INSTALL_NAMESPACE}" &>/dev/null; then
  echo "[$(date -u +%FT%T.%3NZ)] Creating suggested namespace '${INSTALL_NAMESPACE}'"
  oc create namespace "${INSTALL_NAMESPACE}"
fi

echo "[$(date -u +%FT%T.%3NZ)] Using install namespace: ${INSTALL_NAMESPACE}"

# Store namespace for downstream tasks
echo -n "${INSTALL_NAMESPACE}" > /workspace/install-namespace

# Determine target namespaces (install mode)
TARGET_NAMESPACES=$(echo "${bundle_render_out}" | \
  jq -r 'select(.schema == "olm.bundle") | .properties[]? |
  select(.type == "olm.bundle.object") | .value.data' 2>/dev/null | \
  base64 -d 2>/dev/null | \
  jq -r 'select(.kind == "ClusterServiceVersion") |
  .spec.installModes[] | select(.supported == true) | .type' 2>/dev/null || echo "AllNamespaces")

TARGET_NAMESPACES_FINAL=""
if echo "${TARGET_NAMESPACES}" | grep -q "AllNamespaces"; then
  TARGET_NAMESPACES_FINAL=""
elif echo "${TARGET_NAMESPACES}" | grep -q "SingleNamespace"; then
  TARGET_NAMESPACES_FINAL="default"
elif echo "${TARGET_NAMESPACES}" | grep -q "OwnNamespace"; then
  TARGET_NAMESPACES_FINAL="${INSTALL_NAMESPACE}"
elif echo "${TARGET_NAMESPACES}" | grep -q "MultiNamespace"; then
  TARGET_NAMESPACES_FINAL="openshift-marketplace,default"
fi

# Create OperatorGroup
OPERATORGROUP=$(oc -n "${INSTALL_NAMESPACE}" get operatorgroup -o jsonpath="{.items[*].metadata.name}" 2>/dev/null || true)

if [[ $(echo "${OPERATORGROUP}" | wc -w) -gt 1 ]]; then
  echo "ERROR: Multiple OperatorGroups in namespace '${INSTALL_NAMESPACE}'" >&2
  exit 1
elif [[ -n "${OPERATORGROUP}" ]]; then
  OG_OPERATION=apply
  OG_NAMESTANZA="name: ${OPERATORGROUP}"
else
  OG_OPERATION=create
  OG_NAMESTANZA="generateName: oo-"
fi

OPERATORGROUP=$(oc ${OG_OPERATION} -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  ${OG_NAMESTANZA}
  namespace: ${INSTALL_NAMESPACE}
spec:
  targetNamespaces: [$(echo "${TARGET_NAMESPACES_FINAL}" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/' | sed 's/""//' )]
EOF
)
echo "[$(date -u +%FT%T.%3NZ)] OperatorGroup: ${OPERATORGROUP}"

# Create CatalogSource
CATSRC=$(oc create -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  generateName: oo-
  namespace: ${INSTALL_NAMESPACE}
spec:
  sourceType: grpc
  image: ${FBC_FRAGMENT}
  displayName: "Certsuite Test Catalog"
  publisher: "konflux-certsuite"
EOF
)
echo "[$(date -u +%FT%T.%3NZ)] CatalogSource: ${CATSRC}"

# Wait for CatalogSource to be ready
echo "[$(date -u +%FT%T.%3NZ)] Waiting for CatalogSource to be ready..."
for i in $(seq 1 60); do
  STATE=$(oc get catalogsource "${CATSRC}" -n "${INSTALL_NAMESPACE}" \
    -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null || echo "")
  if [[ "${STATE}" == "READY" ]]; then
    echo "[$(date -u +%FT%T.%3NZ)] CatalogSource is ready"
    break
  fi
  if [[ ${i} -eq 60 ]]; then
    echo "ERROR: CatalogSource did not become ready" >&2
    oc get catalogsource "${CATSRC}" -n "${INSTALL_NAMESPACE}" -o yaml > "${ARTIFACT_DIR}/catalogsource-${CATSRC}.yaml"
    exit 1
  fi
  sleep 10
done

DEPLOYMENT_START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "[$(date -u +%FT%T.%3NZ)] Deployment start time: ${DEPLOYMENT_START_TIME}"

# Get bundle name
BUNDLE_NAME=$(echo "${bundle_render_out}" | \
  jq -r 'select(.schema == "olm.bundle") | .name' 2>/dev/null | head -1)

# Create Subscription
SUB=$(oc create -f - -o jsonpath='{.metadata.name}' <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  generateName: oo-
  namespace: ${INSTALL_NAMESPACE}
spec:
  channel: ${CHANNEL_NAME}
  installPlanApproval: Automatic
  name: ${PACKAGE_NAME}
  source: ${CATSRC}
  sourceNamespace: ${INSTALL_NAMESPACE}
  startingCSV: ${BUNDLE_NAME}
EOF
)
echo "[$(date -u +%FT%T.%3NZ)] Subscription: ${SUB}"

# Wait for CSV to become ready
echo "[$(date -u +%FT%T.%3NZ)] Waiting for CSV to become ready..."
for i in $(seq 1 90); do
  CSV=$(oc get subscription "${SUB}" -n "${INSTALL_NAMESPACE}" \
    -o jsonpath='{.status.installedCSV}' 2>/dev/null || echo "")

  if [[ -n "${CSV}" ]]; then
    PHASE=$(oc get csv "${CSV}" -n "${INSTALL_NAMESPACE}" \
      -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "${PHASE}" == "Succeeded" ]]; then
      echo "[$(date -u +%FT%T.%3NZ)] CSV '${CSV}' is ready (phase: Succeeded)"

      # Store operator metadata for downstream tasks
      echo -n "${CATSRC}" > /workspace/catalogsource-name
      echo -n "${SUB}" > /workspace/subscription-name
      echo -n "${CSV}" > /workspace/csv-name
      echo -n "${OPERATORGROUP}" > /workspace/operatorgroup-name

      exit 0
    fi
    echo "[$(date -u +%FT%T.%3NZ)] CSV '${CSV}' phase: ${PHASE}"
  fi

  sleep 10
done

echo "[$(date -u +%FT%T.%3NZ)] ERROR: Timed out waiting for CSV to become ready"

# Dump artifacts for debugging
oc get subscription "${SUB}" -n "${INSTALL_NAMESPACE}" -o yaml > "${ARTIFACT_DIR}/subscription-${SUB}.yaml" 2>/dev/null || true
oc get catalogsource "${CATSRC}" -n "${INSTALL_NAMESPACE}" -o yaml > "${ARTIFACT_DIR}/catalogsource-${CATSRC}.yaml" 2>/dev/null || true
if [[ -n "${CSV:-}" ]]; then
  oc get csv "${CSV}" -n "${INSTALL_NAMESPACE}" -o yaml > "${ARTIFACT_DIR}/csv-${CSV}.yaml" 2>/dev/null || true
fi

exit 1
