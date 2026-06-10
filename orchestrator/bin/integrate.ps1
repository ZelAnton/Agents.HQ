#requires -Version 7
<#
.SYNOPSIS
  Последовательная интеграция изменений ОДНОГО репо в цепочку поверх main (фаза P5). Изменения
  исполнителей (из exec-one) rebase-ятся ПО ОДНОМУ; при jj-конфликте зовётся hq-merge (сохраняет обе
  стороны); build+test ПОСЛЕ КАЖДОЙ интеграции. Пишет summary.json, совместимый с land.ps1
  (поля change/range_base/conflicts_resolved/gate_*). Конфликты НЕ авто-land-ятся — это решает land (§11.2).
.EXAMPLE
  ./integrate.ps1 -TaskDirs ../_runs/p5/INTRA-A,../_runs/p5/INTRA-B -RunDir ../_runs/p5
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$TaskDirs,
  [Parameter(Mandatory)][string]$RunDir,
  [string]$Base = 'main',
  [string]$BuildCmd = 'cargo build',
  [string]$TestCmd = 'cargo test',
  [string]$Model = 'sonnet'
)
$ErrorActionPreference = 'Stop'
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent
$TaskDirs = @($TaskDirs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$RunDir = (New-Item -ItemType Directory -Force $RunDir).FullName

function Invoke-Claude {
  param([string]$Cwd, [string]$SpecFile, [string]$SchemaFile, [string]$InputText, [string]$Tools)
  $schema = Get-Content -Raw $SchemaFile
  $err = [IO.Path]::GetTempFileName()
  Push-Location $Cwd
  try {
    $raw = & claude -p $InputText --append-system-prompt-file $SpecFile --output-format json --json-schema $schema `
        --permission-mode acceptEdits --allowedTools $Tools --model $Model 2>$err | Out-String
  } finally { Pop-Location }
  $e = $null; try { $e = $raw | ConvertFrom-Json } catch {}
  if ($e.structured_output) { Remove-Item $err -EA SilentlyContinue; return $e.structured_output }
  if ($e.result) {
    $r = [string]$e.result; try { return ($r | ConvertFrom-Json) } catch {}
    $a = $r.IndexOf('{'); $b = $r.LastIndexOf('}'); if ($a -ge 0 -and $b -gt $a) { try { return ($r.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch {} }
  }
  $et = Get-Content -Raw $err -EA SilentlyContinue; Remove-Item $err -EA SilentlyContinue
  throw "claude -p без валидного JSON. stderr: $et"
}
# revset → короткий change_id или commit_id (из заданного репо)
function RevId([string]$repoPath, [string]$revset, [string]$which = 'change_id') {
  Push-Location $repoPath
  try { $v = (jj log --no-pager -r $revset --no-graph -T "$which.short()" 2>$null | Out-String).Trim() } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0 -or -not $v) { return $null }
  return ($v -split '\r?\n')[0]
}

# ---- собрать задачи в порядке интеграции ----
$tasks = @()
foreach ($d in $TaskDirs) {
  $sp = Join-Path $d 'summary.json'
  if (-not (Test-Path $sp)) { throw "нет summary.json в $d" }
  $s = Get-Content -Raw $sp | ConvertFrom-Json
  $er = Join-Path $d 'executor-result.json'
  $intent = if (Test-Path $er) { (Get-Content -Raw $er | ConvertFrom-Json).summary } else { $s.task }
  $tasks += [pscustomobject]@{ dir = $d; repo = $s.repo; ws = $s.workspace; dest = $s.dest; out_of_scope = @($s.out_of_scope); intent = $intent }
}
$repo = $tasks[0].repo
if (@($tasks.repo | Sort-Object -Unique).Count -gt 1) { throw "integrate рассчитан на ОДИН репо; получено: $($tasks.repo -join ', ')" }
$repoPath = Join-Path $Personal $repo
if (-not (Test-Path (Join-Path $repoPath '.jj'))) { throw "$repo не jj-репо" }

Write-Host "=== integrate repo=${repo}: $($tasks.Count) изменений на $Base ==="
$integTip = $Base
$conflictsResolved = @()
$priorIntents = @()
$outOfScope = @()
$ok = $true; $failReason = $null; $tests = 'skipped'

foreach ($t in $tasks) {
  $dest = $t.dest; $ws = $t.ws
  if (-not (Test-Path $dest)) { $ok = $false; $failReason = "workspace dest нет: $dest"; break }
  $outOfScope += $t.out_of_scope
  Push-Location $dest
  try {
    $change = (jj log --no-pager -r '@' --no-graph -T 'change_id.short()' 2>$null | Out-String).Trim()
    $change = ($change -split '\r?\n')[0]
    # rebase моего @ на текущий integ-tip, если он ещё не мой родитель
    # используем $change (change_id) а не '@', т.к. RevId работает в $repoPath (main workspace)
    $parent = RevId $repoPath "${change}-" 'commit_id'
    $tipCommit = RevId $repoPath $integTip 'commit_id'
    if ($parent -and $tipCommit -and ($parent -ne $tipCommit)) {
      jj rebase -s '@' -d $integTip 2>&1 | Out-String | Write-Verbose
      jj workspace update-stale 2>&1 | Out-Null   # на всякий: освежить рабочую копию
    }
    # конфликт? (change_id-based revset: работает в любом workspace-контексте)
    $hasConflict = [bool](RevId $repoPath "$change & conflicts()" 'change_id')
    if ($hasConflict) {
      $confFiles = (jj resolve --list 2>&1 | Out-String)
      Write-Host "  [$($t.ws)] КОНФЛИКТ при интеграции → hq-merge"
      $mInput = @"
В текущей рабочей копии — jj-конфликты после интеграции изменения.
Сторона «уже в integ» (предыдущие изменения): $((@($priorIntents) -join ' | '))
Сторона «текущее изменение»: $($t.intent)

Конфликтные файлы (jj resolve --list):
$confFiles

Сними конфликты, сохранив намерение ОБЕИХ сторон; не глуши тесты. Команды гейта: build='$BuildCmd'; test='$TestCmd'.
Верни ТОЛЬКО JSON по merge.schema.json.
"@
      $merge = $null; $mErr = $null
      try { $merge = Invoke-Claude -Cwd $dest -SpecFile (Join-Path $Orch 'agents/hq-merge.md') -SchemaFile (Join-Path $Orch 'schemas/merge.schema.json') -InputText $mInput -Tools 'Read,Edit,Write,Glob,Grep,Bash(jj:*),Bash(cargo:*)' }
      catch { $mErr = $_.Exception.Message }
      if ($merge) { $merge | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $t.dir 'merge.json') }
      $stillConflict = [bool](RevId $repoPath "$change & conflicts()" 'change_id')
      if ($mErr -or -not $merge -or $merge.needs_human -or -not $merge.integrated -or $stillConflict) {
        $ok = $false; $failReason = "конфликт не разрешён авто (needs_human=$($merge.needs_human) still=$stillConflict err=$mErr)"; break
      }
      $resolved = if (@($merge.conflicts_resolved).Count) { @($merge.conflicts_resolved) } else { @('(unspecified)') }
      $conflictsResolved += $resolved
    }
    # авторитетный гейт build+test ПОСЛЕ этой интеграции
    $bok = $false; $tok = $false
    Invoke-Expression $BuildCmd 2>&1 | Tee-Object (Join-Path $t.dir 'integ-build.log') | Out-Null; $bok = ($LASTEXITCODE -eq 0)
    if ($bok) { Invoke-Expression $TestCmd 2>&1 | Tee-Object (Join-Path $t.dir 'integ-test.log') | Out-Null; $tok = ($LASTEXITCODE -eq 0) }
    if (-not ($bok -and $tok)) { $ok = $false; $failReason = "гейт после интеграции $($t.ws): build=$bok test=$tok"; $tests = 'fail'; break }
    $integTip = $change          # продвинуть tip
    $priorIntents += $t.intent
    Write-Host "  [$($t.ws)] интегрировано (change=$change) build/test=$bok/$tok"
  } finally { Pop-Location }
}

if ($ok) { $tests = 'pass' }
$lastDest = $tasks[-1].dest; $lastWs = $tasks[-1].ws
$summary = [ordered]@{
  repo               = $repo
  workspace          = $lastWs
  dest               = $lastDest
  change             = $integTip            # land приземляет цепочку до этого change
  range_base         = $Base                # diff/Verifier берут диапазон Base..change
  gate_build         = $ok
  gate_tests         = ($tests -eq 'pass')
  out_of_scope       = @($outOfScope | Where-Object { $_ } | Select-Object -Unique)
  conflicts_resolved = @($conflictsResolved | Select-Object -Unique)
  integrated         = $ok
  fail_reason        = $failReason
}
$summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RunDir 'summary.json')
Write-Host ""
if ($ok) {
  Write-Host "=== integrate OK: integ_tip=$integTip; conflicts_resolved=[$($summary.conflicts_resolved -join ', ')] ==="
  Write-Host "Дальше: land.ps1 -RunDir $RunDir -Task <любая_спека_для_DoD> -Autonomy auto-low"
} else {
  Write-Host "=== integrate СТОП: $failReason → land заведёт DEC (или почини и перезапусти) ==="
}
$summary | ConvertTo-Json -Depth 8
