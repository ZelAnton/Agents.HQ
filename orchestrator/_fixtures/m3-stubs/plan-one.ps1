#requires -Version 7
# STUB plan worker (M3a plumbing test — no LLM). Mimics the plan-one.ps1 output contract:
# writes plan-result.json {decision, reason}. Branches on `test-scenario` in the task FM.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Task,
  [Parameter(Mandatory)][string]$RunDir,
  [string]$Model = 'opus'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $RunDir | Out-Null
$txt = Get-Content -Raw $Task
$scn = if ($txt -match '(?m)^test-scenario:\s*(.+)$') { $Matches[1].Trim() } else { 'happy' }
$decision = switch ($scn) {
  'plan-reject'   { 'reject' }
  'plan-escalate' { 'escalate' }
  default         { 'accept' }
}
@{ decision = $decision; reason = "stub plan ($scn)" } | ConvertTo-Json | Set-Content (Join-Path $RunDir 'plan-result.json')
Write-Host "stub plan: $(Split-Path $Task -Leaf) -> $decision"
exit 0
