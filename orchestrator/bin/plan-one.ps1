#requires -Version 7
<#
.SYNOPSIS
  DoR-гейт для ОДНОЙ intake-задачи. Вызывается hq-conductor tick (роль plan).
  Читает спеку задачи, спрашивает Opus, пишет plan-result.json {decision, reason} в RunDir.
  Fail-safe: ошибка Claude → decision=escalate (задача не теряется).
.EXAMPLE
  ./plan-one.ps1 -Task ../orchestrator/tasks/TASK-0042-foo.md -RunDir ../_runs/tick-0001/plan-TASK-0042
  ./plan-one.ps1 -Task ../orchestrator/tasks/TASK-0042-foo.md -RunDir ../_runs/tick-0001/plan-TASK-0042 -Model sonnet
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Task,
  [Parameter(Mandatory)][string]$RunDir,
  [string]$Model = 'opus'
)
$ErrorActionPreference = 'Stop'
$Bin        = $PSScriptRoot
$Orch       = Split-Path $Bin -Parent
$HQ         = Split-Path $Orch -Parent

New-Item -ItemType Directory -Force $RunDir | Out-Null
$RunDir     = (Resolve-Path $RunDir).Path
$resultFile = Join-Path $RunDir 'plan-result.json'
$taskText   = Get-Content -Raw $Task
$taskName   = Split-Path $Task -Leaf

# Pass the full spec so Claude can assess every DoR criterion
$inp = @"
Проверь DoR (Definition of Ready) для следующей задачи и верни решение по схеме.

## Задача: $taskName

$taskText
"@

# Call Claude with DoR-check agent
$schema   = Get-Content -Raw (Join-Path $Orch 'schemas/plan-result.schema.json')
$specFile = Join-Path $Orch 'agents/hq-dor.md'
$err      = [IO.Path]::GetTempFileName()
$result   = $null
$claudeErr = $null

try {
  Push-Location $HQ
  try {
    $raw = & claude -p $inp `
        --append-system-prompt-file $specFile `
        --output-format json `
        --json-schema $schema `
        --permission-mode acceptEdits `
        --allowedTools 'Read,Glob,Grep' `
        --model $Model 2>$err | Out-String
  } finally { Pop-Location }

  $e = $null; try { $e = $raw | ConvertFrom-Json } catch {}
  if ($e.structured_output) {
    $result = $e.structured_output
  } elseif ($e.result) {
    $r = [string]$e.result
    try { $result = ($r | ConvertFrom-Json) } catch {}
    if (-not $result) {
      $a = $r.IndexOf('{'); $b = $r.LastIndexOf('}')
      if ($a -ge 0 -and $b -gt $a) { try { $result = ($r.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch {} }
    }
  }
} catch {
  $claudeErr = $_.Exception.Message
}

if (-not $result) {
  $et = (Get-Content $err -Raw -EA SilentlyContinue) ?? ''
  Remove-Item $err -EA SilentlyContinue
  # Fail-safe: escalate rather than silently drop the task
  @{ decision = 'escalate'; reason = ("plan-one: ошибка Claude — $claudeErr $et").Trim() } |
    ConvertTo-Json | Set-Content $resultFile -Encoding utf8
  Write-Warning "plan-one: $taskName → escalate (ошибка)"
  exit 1
}
Remove-Item $err -EA SilentlyContinue

$result | ConvertTo-Json | Set-Content $resultFile -Encoding utf8
Write-Host "plan-one: $taskName → $($result.decision) — $($result.reason)"
# exit 1 on reject so hq-spawn records failure in job results (conductor still reads plan-result.json)
if ($result.decision -eq 'reject') { exit 1 }
exit 0
