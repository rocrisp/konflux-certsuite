#!/usr/bin/env bash
set -euo pipefail

# Validates a certsuite test bundle directory for correctness.
#
# The test bundle is responsible for deploying operator operands and
# verifying the operator is properly deployed. It does NOT contain
# certsuite configuration (that is managed separately).
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
  if grep -q "kind: TestBundle" "${BUNDLE_DIR}/certsuite-test-bundle.yaml"; then
    pass "kind: TestBundle"
  else
    fail "Missing 'kind: TestBundle'"
  fi

  if grep -q "name:" "${BUNDLE_DIR}/certsuite-test-bundle.yaml" | head -1; then
    pass "metadata.name is set"
  fi

  if grep -q "readiness:" "${BUNDLE_DIR}/certsuite-test-bundle.yaml"; then
    pass "readiness checks defined"
  else
    warn "No readiness checks defined (pipeline may not wait for operands)"
  fi
fi

# ── Operand manifest checks ───────────────────────────────────────────
echo ""
echo "Operand manifests:"

if [[ -d "${BUNDLE_DIR}/operands" ]]; then
  HAS_CR=false

  for f in "${BUNDLE_DIR}/operands"/*.yaml "${BUNDLE_DIR}/operands"/*.yml; do
    [[ -f "${f}" ]] || continue
    BASENAME=$(basename "${f}")
    HAS_CR=true

    # Validate YAML syntax
    if command -v python3 &>/dev/null; then
      if ! python3 -c "import yaml; yaml.safe_load(open('${f}'))" 2>/dev/null; then
        warn "${BASENAME}: invalid YAML syntax"
      fi
    fi
  done

  if ${HAS_CR}; then
    pass "Operand manifests found"
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
