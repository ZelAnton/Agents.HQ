#requires -Version 7
<#
.SYNOPSIS
  Verify worker для одной in-review задачи. Вызывается hq-conductor tick (роль review).
  1) Собирает workspace-факты из jj (changed_files, diff_lines, conflict, leaks) → review-context.json.
  2) Вызывает Opus с hq-verify.md (состязательный ревьюер) → verify.json.
  Fail-safe: ошибка Claude → verdict=fail/high с reason (escalate, не теряем задачу).
.EXAMPLE
  ./verify-one.ps1 -Task ../tasks/TASK-0001.md -ExecRunDir ../_runs/tick-0001/exec-TASK-0001 -RunDir ../_runs/tick-0001/review-TASK-0001
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Task,
  [string]$ExecRunDir = '',
  [Parameter(Mandatory)][string]$RunDir,
  [string]$Model = 'opus'
)
$ErrorActionPreference = 'Stop'
$Bin      = $PSScriptRoot
$Orch     = Split-Path $Bin -Parent
$HQ       = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent

New-Item -ItemType Directory -Force $RunDir | Out-Null
$RunDir = (Resolve-Path $RunDir).Path

# Leak patterns (same as exec-one.ps1 / land.ps1)
$LeakRx = @(
  '[A-Za-z]:[\\/](?:GitHub|Users)',
  '/(?:GitHub|Users)/',
  'ghp_[A-Za-z0-9]{20,}',
  'xox[baprs]-',
  'AKIA[0-9A-Z]{16}',
  'BEGIN [A-Z ]*PRIVATE KEY'
)
function Find-Leaks([string]$t) {
  $h = @()
  foreach ($rx in $LeakRx) { if ($t -match $rx) { $h += $rx } }
  return $h
}

function FmList([string]$t, [string]$k) {
  if ($t -match "(?m)^${k}:\s*\[([^\]]*)\]") {
    return @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
  return @()
}

# ─── resolve exec workspace ───────────────────────────────────────────────────
if (-not $ExecRunDir) { throw 'ExecRunDir обязателен (задан hq-conductor из run-dir в FM задачи)' }
if (-not (Test-Path $ExecRunDir)) { throw "ExecRunDir не найден: $ExecRunDir" }
$summaryPath = Join-Path $ExecRunDir 'summary.json'
if (-not (Test-Path $summaryPath)) { throw "нет summary.json в ExecRunDir: $ExecRunDir" }

$sum    = Get-Content -Raw $summaryPath | ConvertFrom-Json
$dest   = $sum.dest
$repo   = $sum.repo
$wsName = $sum.workspace
$execStatus = if ($sum.PSObject.Properties['executor_status']) { [string]$sum.executor_status } else { 'unknown' }
$gateBuild  = if ($sum.PSObject.Properties['gate_build']) { [bool]$sum.gate_build }   else { $false }
$gateTests  = if ($sum.PSObject.Properties['gate_tests']) { [bool]$sum.gate_tests }   else { $false }

if (-not (Test-Path $dest)) { throw "workspace не найден: $dest (workspace=$wsName уже удалён?)" }

# ─── collect workspace facts via jj ──────────────────────────────────────────
$changeId    = ''
$changedFiles = @()
$diffLines   = 0
$hasConflict = $false
$isEmptyDiff = $false
$diffText    = ''
$leaks       = @()

Push-Location $dest
try {
  # Short change ID of workspace @ — used by land-only.ps1
  $changeId = (jj log --no-pager -r '@' --no-graph --template 'change_id.short()' 2>&1 | Out-String).Trim()

  # Conflict flag (jj template: 'true'/'false')
  $conflictStr = (jj log --no-pager -r '@' --no-graph --template 'conflict' 2>&1 | Out-String).Trim()
  $hasConflict = $conflictStr -eq 'true'

  # Use --git format: standard +/- unified diff Claude and most tools understand.
  # Without --git, jj uses a line-number format without +/- prefixes.
  $diffText = (jj diff --no-pager --git 2>&1 | Out-String)
  $isEmptyDiff = [string]::IsNullOrWhiteSpace($diffText)

  # Changed file paths from diff --stat (lines with ' | ')
  $statLines    = @(jj diff --no-pager --stat 2>&1)
  $changedFiles = @($statLines | Where-Object { $_ -match '\|' } | ForEach-Object {
    ($_ -split '\|')[0].Trim()
  } | Where-Object { $_ })

  # Diff line count (git-format: +/- prefixes on added/removed lines; not +++ / --- headers)
  $diffLines = ($diffText -split "`n" | Where-Object { $_ -match '^[+\-][^+\-]' } | Measure-Object).Count

  # Leak scan over full diff
  $leaks = @(Find-Leaks $diffText)
} finally { Pop-Location }

# ─── write review-context.json (consumed by Rust assess_risk()) ──────────────
@{
  change        = $changeId
  changed_files = $changedFiles
  diff_lines    = $diffLines
  has_conflict  = $hasConflict
  is_empty      = $isEmptyDiff
  leaks         = $leaks
} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $RunDir 'review-context.json') -Encoding utf8

# ─── prepare Claude input ─────────────────────────────────────────────────────
$taskText   = Get-Content -Raw $Task
$scopePaths = @(FmList $taskText 'scope_paths')

# Extract DoD section from task body (after second ---)
$taskParts = $taskText -split '(?m)^---\s*$', 3
$taskBody  = if ($taskParts.Count -ge 3) { $taskParts[2] } else { $taskText }
# Prefer the DoD section; fall back to full body
$dodSection = if ($taskBody -match '(?s)(## Критерии готовности[^\n]*\n.+?)(?=\n##|\z)') { $Matches[1] } else { $taskBody }

# Cap diff size: very large diffs still get a summary (Claude context limits)
$diffForClaude = if ($diffText.Length -gt 60000) {
  $diffText.Substring(0, 60000) + "`n[... diff truncated at 60000 chars ...]"
} else { $diffText }

$gBuild = if ($gateBuild) { 'pass' } else { 'fail' }
$gTests = if ($gateTests) { 'pass' } else { 'fail' }

$inp = @"
## Задача
Репо: $repo
scope_paths: $($scopePaths -join ', ')

## Результаты exec-гейтов (уже выполнены исполнителем)
executor_status: $execStatus
gate_build: $gBuild
gate_tests: $gTests

ВАЖНО: сборка и тесты уже выполнены исполнителем и их результаты указаны выше.
НЕ запускай cargo build, cargo test или другие команды — allowedTools ограничен Read/Glob/Grep.
Твоя задача — проверить diff и читаемые файлы на соответствие DoD и качество кода.

## DoD (критерии готовности)
$dodSection

## diff (изменения исполнителя)
``````diff
$diffForClaude
``````
"@

# ─── call hq-verify (Opus, adversarial reviewer) ─────────────────────────────
$schema    = Get-Content -Raw (Join-Path $Orch 'schemas/verify.schema.json')
$specFile  = Join-Path $Orch 'agents/hq-verify.md'
$err       = [IO.Path]::GetTempFileName()
$result    = $null
$claudeErr = $null

# Run from exec workspace ($dest) so Claude reads the CHANGED files, not the baseline.
# The workspace is a full jj-colocated working directory with the exec agent's changes applied.
$cwd = $dest

try {
  Push-Location $cwd
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
  # Fail-safe: fail verdict so conductor can escalate (not silently drop)
  @{
    verdict            = 'fail'
    dod_met            = $false
    findings           = @(@{ sev = 'high'; msg = ("verify-one: ошибка Claude — $claudeErr $et").Trim() })
    out_of_scope       = @()
    both_sides_present = $null
    summary            = 'verify-one crashed — escalate'
  } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $RunDir 'verify.json') -Encoding utf8
  Write-Warning "verify-one: ошибка Claude — $claudeErr"
  exit 1
}
Remove-Item $err -EA SilentlyContinue

$result | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $RunDir 'verify.json') -Encoding utf8
Write-Host ("verify-one: repo={0} ws={1} verdict={2} dod={3}" -f $repo, $wsName, $result.verdict, $result.dod_met)

# Exit 0 only on pass+dod (lets hq-spawn record accurate success)
if ($result.verdict -eq 'pass' -and $result.dod_met) { exit 0 } else { exit 1 }
