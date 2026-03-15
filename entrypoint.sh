#!/bin/bash
set -e

SCAN_PATH="${INPUT_SCAN_PATH:-.}"
FORMAT="${INPUT_FORMAT:-sarif}"
SEVERITY="${INPUT_SEVERITY_THRESHOLD:-low}"

# Write SARIF to the mounted workspace so it persists after the container exits.
# /github/workspace is the Docker mount point for the runner workspace.
# Output a relative filename — Node.js actions (upload-sarif) and run: steps both
# resolve relative paths from $GITHUB_WORKSPACE on the host.
SARIF_FILENAME="ex-ray-results.sarif"
SARIF_CONTAINER_PATH="/github/workspace/${SARIF_FILENAME}"

# Build command as array to avoid shell injection via eval
CMD_ARGS=("${SCAN_PATH}" "--format" "${FORMAT}" "--severity" "${SEVERITY}")

[ -n "${INPUT_WEBHOOK_URL}" ]  && CMD_ARGS+=("--webhook-url" "${INPUT_WEBHOOK_URL}")
[ -n "${INPUT_TENANT_ID}" ]    && CMD_ARGS+=("--tenant-id"   "${INPUT_TENANT_ID}")

# Always write SARIF to file so GitHub upload-sarif can find it
[ "${FORMAT}" = "sarif" ] && CMD_ARGS+=("--output" "${SARIF_CONTAINER_PATH}")

# Run the scanner
# Use || to capture exit code without triggering set -e:
#   exit 0 = no findings, exit 1 = findings detected, exit 2 = scan error
echo "::group::Ex-Ray"
exray "${CMD_ARGS[@]}" || SCAN_EXIT=$?
SCAN_EXIT="${SCAN_EXIT:-0}"
echo "::endgroup::"

# Parse output file for action outputs (sarif format only)
FINDINGS=0
CRITICAL=0
FILES_SCANNED=0

if [ "${FORMAT}" = "sarif" ] && [ -f "${SARIF_CONTAINER_PATH}" ]; then
    FINDINGS=$(python3 -c "
import json, sys
try:
    d = json.load(open('${SARIF_CONTAINER_PATH}'))
    print(len(d.get('runs', [{}])[0].get('results', [])))
except Exception:
    print(0)
")
    CRITICAL=$(python3 -c "
import json, sys
try:
    d = json.load(open('${SARIF_CONTAINER_PATH}'))
    results = d.get('runs', [{}])[0].get('results', [])
    print(sum(1 for r in results if r.get('level') == 'error'))
except Exception:
    print(0)
")
    FILES_SCANNED=$(python3 -c "
import json, sys
try:
    d = json.load(open('${SARIF_CONTAINER_PATH}'))
    props = d.get('runs', [{}])[0].get('properties', {})
    print(len(props.get('scannedFiles', [])))
except Exception:
    print(0)
")
    # Output relative filename — resolved from $GITHUB_WORKSPACE by downstream steps
    echo "sarif_file=${SARIF_FILENAME}" >> "${GITHUB_OUTPUT}"
fi

echo "findings_count=${FINDINGS}" >> "${GITHUB_OUTPUT}"
echo "critical_count=${CRITICAL}" >> "${GITHUB_OUTPUT}"
echo "files_scanned=${FILES_SCANNED}" >> "${GITHUB_OUTPUT}"

echo "Ex-Ray: ${FINDINGS} finding(s) detected (${CRITICAL} critical) — ${FILES_SCANNED} file(s) examined"

# Write GitHub Actions step summary
if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
    python3 -c "
import json, sys

sarif_file = '${SARIF_CONTAINER_PATH}'
scan_path  = '${SCAN_PATH}'
findings   = ${FINDINGS}
critical   = ${CRITICAL}

try:
    d = json.load(open(sarif_file))
    props = d.get('runs', [{}])[0].get('properties', {})
    scanned = props.get('scannedFiles', [])
except Exception:
    scanned = []

lines = []
lines.append('## Ex-Ray')
lines.append('')
lines.append('| | |')
lines.append('|---|---|')
lines.append(f'| **Scan target** | \`{scan_path}\` |')
lines.append(f'| **Files examined** | {len(scanned)} |')
lines.append(f'| **Findings** | {findings} |')
lines.append(f'| **Critical** | {critical} |')
lines.append('')

if scanned:
    lines.append('### Files examined')
    for f in scanned:
        lines.append(f'- \`{f}\`')
else:
    lines.append('> No supported files found — nothing to scan.')

print('\n'.join(lines))
" >> "${GITHUB_STEP_SUMMARY}" 2>/dev/null || true
fi

# Fail if configured and findings exist
if [ "${INPUT_FAIL_ON_FINDINGS}" = "true" ] && [ "${FINDINGS}" -gt "0" ]; then
    echo "::error::Ex-Ray found ${FINDINGS} finding(s) — failing build"
    exit 1
fi

exit 0
