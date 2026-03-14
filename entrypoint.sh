#!/bin/bash
set -e

SCAN_PATH="${INPUT_SCAN_PATH:-.}"
FORMAT="${INPUT_FORMAT:-sarif}"
SEVERITY="${INPUT_SEVERITY_THRESHOLD:-low}"
SARIF_FILE="/tmp/dev-trust-scanner-results.sarif"

# Build command as array to avoid shell injection via eval
CMD_ARGS=("${SCAN_PATH}" "--format" "${FORMAT}" "--severity" "${SEVERITY}")

[ -n "${INPUT_WEBHOOK_URL}" ]  && CMD_ARGS+=("--webhook-url" "${INPUT_WEBHOOK_URL}")
[ -n "${INPUT_TENANT_ID}" ]    && CMD_ARGS+=("--tenant-id"   "${INPUT_TENANT_ID}")

# Always write to a file so GitHub upload-sarif can find it
[ "${FORMAT}" = "sarif" ] && CMD_ARGS+=("--output" "${SARIF_FILE}")

# Run the scanner
# Use || to capture exit code without triggering set -e:
#   exit 0 = no findings, exit 1 = findings detected, exit 2 = scan error
echo "::group::Dev Trust Scanner"
dev-trust-scan "${CMD_ARGS[@]}" || SCAN_EXIT=$?
SCAN_EXIT="${SCAN_EXIT:-0}"
echo "::endgroup::"

# Parse output file for action outputs (sarif format only)
FINDINGS=0
CRITICAL=0

if [ "${FORMAT}" = "sarif" ] && [ -f "${SARIF_FILE}" ]; then
    FINDINGS=$(python3 -c "
import json, sys
try:
    d = json.load(open('${SARIF_FILE}'))
    print(len(d.get('runs', [{}])[0].get('results', [])))
except Exception:
    print(0)
")
    CRITICAL=$(python3 -c "
import json, sys
try:
    d = json.load(open('${SARIF_FILE}'))
    results = d.get('runs', [{}])[0].get('results', [])
    print(sum(1 for r in results if r.get('level') == 'error'))
except Exception:
    print(0)
")
    echo "sarif_file=${SARIF_FILE}" >> "${GITHUB_OUTPUT}"
fi

echo "findings_count=${FINDINGS}" >> "${GITHUB_OUTPUT}"
echo "critical_count=${CRITICAL}" >> "${GITHUB_OUTPUT}"

echo "Dev Trust Scanner: ${FINDINGS} finding(s) detected (${CRITICAL} critical)"

# Fail if configured and findings exist
if [ "${INPUT_FAIL_ON_FINDINGS}" = "true" ] && [ "${FINDINGS}" -gt "0" ]; then
    echo "::error::Dev Trust Scanner found ${FINDINGS} finding(s) — failing build"
    exit 1
fi

exit 0
