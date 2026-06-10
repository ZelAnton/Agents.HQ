#requires -Version 7
# STUB exec worker (M3a plumbing test — no LLM, no jj). Mimics exec-one.ps1's summary.json
# contract. Branches on `test-scenario` in the task FM. Exit 0 iff gates green + status done.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Task,
  [Parameter(Mandatory)][string]$RunDir,
  [string]$Model = 'sonnet'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $RunDir | Out-Null
$txt = Get-Content -Raw $Task
$scn = if ($txt -match '(?m)^test-scenario:\s*(.+)$') { $Matches[1].Trim() } else { 'happy' }
$repo = if ($txt -match '(?m)^scope:\s*(.+)$') { $Matches[1].Trim() } else { 'testrepo' }
$gateOk = ($scn -ne 'exec-fail')
$status = $gateOk ? 'done' : 'failed'
$summary = [ordered]@{
  task = (Split-Path $Task -Leaf); repo = $repo; workspace = 'ws-stub'; dest = (Join-Path $RunDir 'ws')
  executor_status = $status; self_build = 'ok'; self_tests = 'pass'
  gate_build = $gateOk; gate_tests = $gateOk; out_of_scope = @(); leaks = @(); exec_error = ($gateOk ? $null : 'stub exec-fail')
}
$summary | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $RunDir 'summary.json')
Write-Host "stub exec: $(Split-Path $Task -Leaf) repo=$repo gate=$gateOk status=$status"
if ($gateOk) { exit 0 } else { exit 1 }
