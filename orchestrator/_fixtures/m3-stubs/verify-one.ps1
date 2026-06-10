#requires -Version 7
# STUB verify worker (M3a plumbing test — no LLM, no jj). Writes verify.json (hq-verify
# contract) + review-context.json (workspace facts the Rust risk() consumes). Branches on
# `test-scenario` in the task FM to drive: happy(pass+low), review-fail(fix-needed),
# risky(pass+sensitive→DEC), big(pass+oversize→DEC).
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Task,
  [string]$ExecRunDir = '',
  [Parameter(Mandatory)][string]$RunDir,
  [string]$Model = 'opus'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $RunDir | Out-Null
$txt = Get-Content -Raw $Task
$scn = if ($txt -match '(?m)^test-scenario:\s*(.+)$') { $Matches[1].Trim() } else { 'happy' }

$verdict  = ($scn -eq 'review-fail') ? 'fail' : 'pass'
$dod      = ($scn -ne 'review-fail')
$findings = ($scn -eq 'review-fail') ? @(@{ sev = 'high'; msg = 'stub: DoD не покрыт' }) : @()
@{ verdict = $verdict; dod_met = $dod; out_of_scope = @(); findings = $findings; summary = "stub verify ($scn)" } |
  ConvertTo-Json -Depth 6 | Set-Content (Join-Path $RunDir 'verify.json')

# workspace facts → risk() inputs
$changed = ($scn -eq 'risky') ? @('Cargo.toml', 'src/lib.rs') : @('src/lib.rs')
$lines   = ($scn -eq 'big') ? 500 : 12
@{ change = 'stubchange'; changed_files = $changed; diff_lines = $lines; has_conflict = $false; is_empty = $false; leaks = @() } |
  ConvertTo-Json -Depth 6 | Set-Content (Join-Path $RunDir 'review-context.json')
Write-Host "stub verify: $(Split-Path $Task -Leaf) verdict=$verdict scn=$scn"
exit 0
