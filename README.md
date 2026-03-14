# Dev Trust Scanner — GitHub Action

Static analysis scanner for malicious patterns in developer tooling configurations. Detects supply chain attack techniques in npm lifecycle scripts and VS Code tasks before they reach your developers.

**Detects:**
- Malicious `postinstall`/`preinstall` scripts (eval, base64 payloads, credential exfiltration)
- VS Code tasks that auto-execute on folder open (Contagious Interview attack pattern)
- Obfuscated commands, high-entropy encoded payloads, suspicious network calls

---

## Quick Start

```yaml
# .github/workflows/dev-trust-scan.yml
name: Dev Trust Scanner
on:
  pull_request:
    paths:
      - 'package.json'
      - 'package-lock.json'
      - '.vscode/tasks.json'
  push:
    branches: [main]

jobs:
  scan:
    runs-on: ubuntu-latest
    permissions:
      security-events: write  # Required for SARIF upload
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Run Dev Trust Scanner
        id: scan
        uses: ymlsurgeon/dev-trust-scanner-action@v1

      - name: Upload to GitHub Security
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: ${{ steps.scan.outputs.sarif_file }}
```

Findings appear as inline annotations on pull requests via GitHub code scanning.

---

## MDR Integration (with Sumo Logic webhook)

```yaml
      - name: Run Dev Trust Scanner
        id: scan
        uses: ymlsurgeon/dev-trust-scanner-action@v1
        with:
          webhook_url: ${{ secrets.DTS_WEBHOOK_URL }}
          tenant_id: "acme-corp"
          severity_threshold: "medium"

      - name: Upload to GitHub Security
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: ${{ steps.scan.outputs.sarif_file }}

      - name: Summary
        if: always()
        run: |
          echo "### Dev Trust Scanner" >> $GITHUB_STEP_SUMMARY
          echo "- Findings: ${{ steps.scan.outputs.findings_count }}" >> $GITHUB_STEP_SUMMARY
          echo "- Critical: ${{ steps.scan.outputs.critical_count }}" >> $GITHUB_STEP_SUMMARY
```

**Setting up the Sumo Logic webhook:**
1. In Sumo Logic, create an **HTTP Source** under Manage Data → Collection
2. Copy the generated HTTP Source URL
3. Add it as a repository secret: `DTS_WEBHOOK_URL`
4. SARIF will be POSTed to that URL on every scan with the `X-Tenant-ID` header set to your `tenant_id`

---

## Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `scan_path` | No | `.` | Directory to scan |
| `webhook_url` | No | — | HTTP endpoint to POST SARIF results to |
| `tenant_id` | No | — | Customer identifier — injected into SARIF `run.properties.tenantId` and `X-Tenant-ID` webhook header |
| `severity_threshold` | No | `low` | Minimum severity to report: `low`, `medium`, `high`, `critical` |
| `format` | No | `sarif` | Output format: `sarif`, `json`, `text` |
| `fail_on_findings` | No | `false` | Exit code 1 if any findings at or above threshold are detected |

## Outputs

| Output | Description |
|---|---|
| `findings_count` | Total findings at or above `severity_threshold` |
| `critical_count` | Number of CRITICAL findings |
| `sarif_file` | Path to SARIF file (set when `format: sarif`) |

---

## Scheduled Weekly Scan

```yaml
on:
  pull_request:
    paths:
      - 'package.json'
      - '.vscode/tasks.json'
  schedule:
    - cron: '0 6 * * 1'  # Monday 6am UTC

jobs:
  scan:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      contents: read
    steps:
      - uses: actions/checkout@v4
      - uses: ymlsurgeon/dev-trust-scanner-action@v1
        with:
          webhook_url: ${{ secrets.DTS_WEBHOOK_URL }}
          tenant_id: ${{ vars.DTS_TENANT_ID }}
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: ${{ steps.scan.outputs.sarif_file }}
```

---

## Block PRs on Critical Findings

```yaml
      - uses: ymlsurgeon/dev-trust-scanner-action@v1
        with:
          severity_threshold: high
          fail_on_findings: 'true'
```

---

## What Gets Scanned

| File | What We Detect |
|---|---|
| `package.json` | `postinstall`, `preinstall`, `install`, `prepare` scripts with eval, base64, network calls, obfuscation, environment variable access |
| `.vscode/tasks.json` | Auto-execution on folder open (`runOn: folderOpen`), obfuscated commands, hidden output, suspicious shell patterns |

---

## Scanner Repository

[ymlsurgeon/dev-trust-scanner](https://github.com/ymlsurgeon/dev-trust-scanner)

<!-- ci: trigger test run -->
