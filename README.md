# Ex-Ray — GitHub Action

Static analysis scanner for malicious patterns in developer tooling configurations. Detects supply chain attack techniques in npm lifecycle scripts, VS Code tasks, and GitHub Actions workflows before they reach your developers.

**Detects:**
- Malicious `postinstall`/`preinstall` scripts (eval, base64 payloads, credential exfiltration)
- VS Code tasks that auto-execute on folder open (Contagious Interview attack pattern)
- GitHub Actions workflows with runner abuse, secret exfiltration, or Shai-Hulud campaign markers
- Obfuscated commands, high-entropy encoded payloads, suspicious network calls

---

## Quick Start

```yaml
# .github/workflows/ex-ray.yml
name: Ex-Ray
on:
  pull_request:
    paths:
      - 'package.json'
      - 'package-lock.json'
      - '.vscode/tasks.json'
      - '.github/workflows/**'
  push:
    branches: [main]

jobs:
  scan:
    runs-on: ubuntu-latest
    permissions:
      security-events: write  # Required for SARIF upload
      contents: read
      actions: read
    steps:
      - uses: actions/checkout@v4

      - name: Run Ex-Ray
        id: scan
        uses: ymlsurgeon/ex-ray-action@v1

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
      - name: Run Ex-Ray
        id: scan
        uses: ymlsurgeon/ex-ray-action@v1
        with:
          webhook_url: ${{ secrets.EXRAY_WEBHOOK_URL }}
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
          echo "### Ex-Ray" >> $GITHUB_STEP_SUMMARY
          echo "- Findings: ${{ steps.scan.outputs.findings_count }}" >> $GITHUB_STEP_SUMMARY
          echo "- Critical: ${{ steps.scan.outputs.critical_count }}" >> $GITHUB_STEP_SUMMARY
```

**Setting up the Sumo Logic webhook:**
1. In Sumo Logic, create an **HTTP Source** under Manage Data → Collection
2. Copy the generated HTTP Source URL
3. Add it as a repository secret: `EXRAY_WEBHOOK_URL`
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
| `files_scanned` | Number of files examined during the scan |
| `sarif_file` | Relative path to SARIF file in the workspace (set when `format: sarif`). Use `${GITHUB_WORKSPACE}/${{ steps.scan.outputs.sarif_file }}` in `run:` steps. |

---

## Scheduled Weekly Scan

```yaml
on:
  pull_request:
    paths:
      - 'package.json'
      - '.vscode/tasks.json'
      - '.github/workflows/**'
  schedule:
    - cron: '0 6 * * 1'  # Monday 6am UTC

jobs:
  scan:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      contents: read
      actions: read
    steps:
      - uses: actions/checkout@v4
      - uses: ymlsurgeon/ex-ray-action@v1
        with:
          webhook_url: ${{ secrets.EXRAY_WEBHOOK_URL }}
          tenant_id: ${{ vars.EXRAY_TENANT_ID }}
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: ${{ steps.scan.outputs.sarif_file }}
```

---

## Block PRs on Critical Findings

```yaml
      - uses: ymlsurgeon/ex-ray-action@v1
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
| `.github/workflows/*.yml` | Workflow injection, self-hosted runner abuse/registration, secret exfiltration, suspicious triggers, Shai-Hulud campaign markers |

### GitHub Actions Rules

| Rule ID | Severity | Description |
|---|---|---|
| GHA-001 | CRITICAL | Known malicious workflow filename (Shai-Hulud campaign) |
| GHA-002 | HIGH | Suspicious trigger combination (`workflow_dispatch` + `schedule` — persistence pattern) |
| GHA-003 | HIGH | External script download and execution (`curl \| bash`, `wget \| sh`) |
| GHA-004 | HIGH | Environment variable / secret dumping (`secrets.*`, `$GITHUB_TOKEN`) |
| GHA-005 | MEDIUM | Self-hosted runner usage (`runs-on: self-hosted`) |
| GHA-006 | CRITICAL | Self-hosted runner registration in workflow |
| GHA-007 | CRITICAL | Runner service installation (`svc.sh install`, `systemctl`) |

---

## Scanner Repository

[ymlsurgeon/ex-ray](https://github.com/ymlsurgeon/ex-ray)
