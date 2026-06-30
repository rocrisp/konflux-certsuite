#!/usr/bin/env bash
set -euo pipefail

# Validates a certsuite test bundle directory for correctness.
#
# Usage:
#   ./validate-test-bundle.sh /path/to/certsuite-test-bundle

BUNDLE_DIR="${1:-}"
ERRORS=0
WARNINGS=0

if [[ -z "${BUNDLE_DIR}" ]]; then
  echo "Usage: $(basename "$0") <bundle-directory>"
  exit 1
fi

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  WARN: $1"; WARNINGS=$((WARNINGS + 1)); }

echo "Validating test bundle: ${BUNDLE_DIR}"
echo "============================================"

# ── Structure checks ──────────────────────────────────────────────────
echo ""
echo "Structure:"

if [[ ! -d "${BUNDLE_DIR}" ]]; then
  fail "Directory does not exist: ${BUNDLE_DIR}"
  echo ""
  echo "RESULT: ${ERRORS} error(s), ${WARNINGS} warning(s)"
  exit 1
fi

if [[ -f "${BUNDLE_DIR}/certsuite-test-bundle.yaml" ]]; then
  pass "certsuite-test-bundle.yaml exists"
else
  fail "certsuite-test-bundle.yaml not found"
fi

if [[ -f "${BUNDLE_DIR}/certsuite_config.yml" ]]; then
  pass "certsuite_config.yml exists"
else
  fail "certsuite_config.yml not found"
fi

if [[ -d "${BUNDLE_DIR}/operands" ]]; then
  MANIFEST_COUNT=$(find "${BUNDLE_DIR}/operands" -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l | tr -d ' ')
  if [[ ${MANIFEST_COUNT} -gt 0 ]]; then
    pass "operands/ contains ${MANIFEST_COUNT} manifest(s)"
  else
    fail "operands/ directory is empty (no .yaml/.yml files)"
  fi
else
  fail "operands/ directory not found"
fi

# ── Bundle manifest checks ────────────────────────────────────────────
echo ""
echo "Bundle manifest:"

if [[ -f "${BUNDLE_DIR}/certsuite-test-bundle.yaml" ]]; then
  # Check required fields
  if grep -q "kind: TestBundle" "${BUNDLE_DIR}/certsuite-test-bundle.yaml"; then
    pass "kind: TestBundle"
  else
    fail "Missing 'kind: TestBundle'"
  fi

  if grep -q "packageName:" "${BUNDLE_DIR}/certsuite-test-bundle.yaml"; then
    pass "operator.packageName is set"
  else
    fail "Missing operator.packageName"
  fi

  if grep -q "name:" "${BUNDLE_DIR}/certsuite-test-bundle.yaml" | head -1; then
    pass "metadata.name is set"
  fi
fi

# ── Certsuite config checks ───────────────────────────────────────────
echo ""
echo "Certsuite config:"

if [[ -f "${BUNDLE_DIR}/certsuite_config.yml" ]]; then
  # Validate YAML syntax
  if python3 -c "import yaml; yaml.safe_load(open('${BUNDLE_DIR}/certsuite_config.yml'))" 2>/dev/null; then
    pass "Valid YAML syntax"
  elif ruby -e "require 'yaml'; YAML.load_file('${BUNDLE_DIR}/certsuite_config.yml')" 2>/dev/null; then
    pass "Valid YAML syntax"
  else
    warn "Could not validate YAML syntax (python3/ruby not available)"
  fi

  if grep -q "targetNameSpaces:" "${BUNDLE_DIR}/certsuite_config.yml"; then
    pass "targetNameSpaces is configured"
  else
    fail "Missing targetNameSpaces"
  fi

  if grep -q "podsUnderTestLabels:" "${BUNDLE_DIR}/certsuite_config.yml"; then
    pass "podsUnderTestLabels is configured"
  else
    warn "Missing podsUnderTestLabels (certsuite may not discover any pods)"
  fi
fi

# ── Operand manifest checks ───────────────────────────────────────────
echo ""
echo "Operand manifests:"

if [[ -d "${BUNDLE_DIR}/operands" ]]; then
  CERTSUITE_LABEL="redhat-best-practices-for-k8s.com/generic"
  HAS_LABEL=false

  for f in "${BUNDLE_DIR}/operands"/*.yaml "${BUNDLE_DIR}/operands"/*.yml; do
    [[ -f "${f}" ]] || continue
    BASENAME=$(basename "${f}")

    # Check for certsuite discovery labels
    if grep -q "${CERTSUITE_LABEL}" "${f}" 2>/dev/null; then
      HAS_LABEL=true
    fi

    if grep -q "nodeSelector:" "${f}" 2>/dev/null; then
      warn "${BASENAME}: has nodeSelector (may not match test cluster nodes)"
    fi
  done

  if ${HAS_LABEL}; then
    pass "At least one manifest has certsuite discovery label"
  else
    fail "No manifest has the '${CERTSUITE_LABEL}' label"
    echo "        Pods must be labeled for certsuite to discover them."
    echo "        Add: redhat-best-practices-for-k8s.com/generic: target"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "============================================"
if [[ ${ERRORS} -eq 0 ]]; then
  echo "RESULT: PASS (${WARNINGS} warning(s))"
  exit 0
else
  echo "RESULT: FAIL (${ERRORS} error(s), ${WARNINGS} warning(s))"
  exit 1
fi
