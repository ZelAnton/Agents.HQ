#requires -Version 7
<#
.SYNOPSIS
  P5 driver: ready-набор задач ОДНОГО репо → plan-waves → фаза 1 (exec): все волны последовательно,
  внутри волны — параллельно; фаза 2 (integrate): один вызов integrate.ps1 по всем dirs в порядке волн;
  фаза 3 (land): один вызов land.ps1. Lock (.lock5, отдельно от P3/.lock).
  Конфликт между волнами возникает именно потому, что exec у всех волн — с одной базы main до первого land.
  Непустой conflicts_resolved → land заведёт DEC (§11.2).
.EXAMPLE
  ./tick5.ps1 -Tasks ../_fixtures/sample-intra-disjoint-a.md,../_fixtures/sample-intra-disjoint-b.md -Autonomy auto-low
  ./tick5.ps1 -AbandonRun tick5-20260610-001122-1234
#>
[CmdletBinding()]
param(
  [string[]]$Tasks,
  [int]$Limit = 4,
  [int]$TimeoutSec = 900,
  [string]$Model = 'sonnet',
  [ValidateSet('propose', 'assist', 'auto-low')][string]$Autonomy = 'propose',
  [string]$BuildCmd = 'cargo build',
  [string]$TestCmd = 'cargo test',
  [string]$AbandonRun
)
$ErrorActionPreference = 'Stop'
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent
$SpawnBin = Join-Path $Bin 'hq-spawn/target/release/hq-spawn.exe'
$ExecOne = Join-Path $Bin 'exec-one.ps1'
$LockFile = Join-Path $Orch '.lock5'

function Enter-Lock {
  $a = 0
  while ($true) {
    try { $fs = [IO.File]::Open($LockFile, 'CreateNew', 'Write', 'None'); $sw = [IO.StreamWriter]::new($fs); $sw.WriteLine("$PID`t$(Get-Date -Format o)"); $sw.Dispose(); $fs.Dispose(); return }
    catch {
      if ($a -ge 1) { throw "Активен другой tick5 (lock: $LockFile)." }
      $a++; $stale = $true; $alive = $false
      try { $p = (Get-Content -Raw $LockFile) -split "`t"; $stale = ((Get-Date) - [datetime]$p[1]).TotalMinutes -gt 60; $alive = [bool](Get-Process -Id ([int]$p[0]) -ErrorAction SilentlyContinue) } catch {}
      if ($stale -or -not $alive) { Remove-Item -Force $LockFile -EA SilentlyContinue; continue }
      throw "Активен другой tick5 (lock: $LockFile)."
    }
  }
}
function Exit-Lock { Remove-Item -Force $LockFile -EA SilentlyContinue }

# ---------- ABANDON ALL workspaces прогона ----------
if ($AbandonRun) {
  $runDir = Join-Path $Orch "_runs/$AbandonRun"
  if (-not (Test-Path $runDir)) { throw "нет прогона: $runDir" }
  $summaries = Get-ChildItem $runDir -Recurse -Filter 'summary.json' -EA SilentlyContinue
  foreach ($s in $summaries) {
    $j = Get-Content -Raw $s.FullName | ConvertFrom-Json
    if (-not $j.repo -or -not $j.workspace) { continue }
    Write-Host "abandon $($j.repo)/$($j.workspace)"
    Push-Location (Join-Path $Personal $j.repo); try { jj workspace forget $j.workspace 2>&1 | Out-Null } finally { Pop-Location }
    if ($j.dest -and (Test-Path $j.dest)) { Remove-Item -Recurse -Force $j.dest }
  }
  Write-Host "AbandonAll выполнен для $AbandonRun. Проверь репо: jj workspace list."
  return
}

# ---------- EXECUTE (plan-waves → exec all waves → integrate → land) ----------
if (-not $Tasks -or $Tasks.Count -eq 0) { throw "нужен -Tasks <пути>" }
$Tasks = @($Tasks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# все задачи — один репо
$repos = @()
foreach ($t in $Tasks) {
  $tp = (Resolve-Path $t).Path
  $txt = Get-Content -Raw $tp
  $r = if ($txt -match '(?m)^repo:\s*(.+)$') { $Matches[1].Trim() } else { $null }
  if (-not $r) { throw "нет `repo:` в задаче $t" }
  $repos += $r
}
$uniqueRepos = @($repos | Sort-Object -Unique)
if ($uniqueRepos.Count -gt 1) { throw "tick5 рассчитан на ОДИН репо; получено: $($uniqueRepos -join ', ')" }
$repo = $uniqueRepos[0]

Enter-Lock
try {
  $runId = "tick5-$(Get-Date -Format yyyyMMdd-HHmmss)-$PID"
  $runDir = Join-Path $Orch "_runs/$runId"; New-Item -ItemType Directory -Force $runDir | Out-Null

  # авторитетный расчёт волн (Дирижёр §11.6)
  Write-Host "=== tick5 ${runId}: repo=${repo}, задач=$($Tasks.Count) → plan-waves ==="
  $wavesFile = Join-Path $runDir 'waves.json'
  & (Join-Path $Bin 'plan-waves.ps1') -Tasks ($Tasks -join ',') -Repo $repo -Out $wavesFile | Out-Null
  $wavePlan = Get-Content -Raw $wavesFile | ConvertFrom-Json
  $waves = @($wavePlan.waves)
  Write-Host "=== волн=$($waves.Count), autonomy=$Autonomy ==="

  # ─── Фаза 1: EXEC всех волн (последовательно между волнами, параллельно внутри) ───
  # Все exec-one запускаются с одной базы (текущий main до первого land), чтобы
  # inter-wave конфликты возникли при интеграции, а не «исчезли» из-за раннего land.
  Write-Host ""
  Write-Host "=== Фаза 1: exec всех $($waves.Count) волн ==="
  $allTaskDirs = @()    # порядок: сначала волна 1, потом волна 2, … (для integrate)
  $allTaskPaths = @()   # оригинальные пути спек (для combined wave-task)
  $allOk = $true

  for ($wi = 0; $wi -lt $waves.Count; $wi++) {
    $waveNum = $wi + 1
    $waveTasks = @($waves[$wi])
    $waveExecDir = Join-Path $runDir "wave-$waveNum/exec"; New-Item -ItemType Directory -Force $waveExecDir | Out-Null
    Write-Host ""
    Write-Host "--- exec волна $waveNum/$($waves.Count): $($waveTasks.Count) задач ---"

    $jobs = @()
    foreach ($tp in $waveTasks) {
      $base = [IO.Path]::GetFileNameWithoutExtension($tp)
      $perRun = Join-Path $waveExecDir $base
      $jobs += [ordered]@{ id = $base; program = 'pwsh'; args = @('-NoProfile', '-File', $ExecOne, '-Task', $tp, '-RunDir', $perRun, '-Model', $Model); timeout_sec = $TimeoutSec }
    }
    $jobsFile = Join-Path $waveExecDir 'jobs.json'
    $jobs | ConvertTo-Json -Depth 8 -AsArray | Set-Content $jobsFile
    $resultsFile = Join-Path $waveExecDir 'results.json'
    & $SpawnBin --jobs $jobsFile --limit $Limit --out $resultsFile 2>&1 | Out-Null

    $results = if (Test-Path $resultsFile) { @(Get-Content -Raw $resultsFile | ConvertFrom-Json) } else { @() }
    foreach ($res in $results) {
      $sp = Join-Path $waveExecDir "$($res.id)/summary.json"
      $s = if (Test-Path $sp) { Get-Content -Raw $sp | ConvertFrom-Json } else { $null }
      Write-Host ("  {0,-22} spawn(code={1} timed_out={2} {3}ms) gate={4}/{5}" -f `
          $res.id, $res.code, $res.timed_out, $res.ms, ($s.gate_build), ($s.gate_tests))
    }

    $allTaskDirs += @($jobs | ForEach-Object { Join-Path $waveExecDir $_.id })
    $allTaskPaths += $waveTasks
  }

  # ─── Фаза 2: INTEGRATE всех задач в порядке волн (один вызов) ───
  Write-Host ""
  Write-Host "=== Фаза 2: integrate ($($allTaskDirs.Count) задач, порядок волн) ==="
  $integDir = Join-Path $runDir 'integ'; New-Item -ItemType Directory -Force $integDir | Out-Null
  & (Join-Path $Bin 'integrate.ps1') -TaskDirs ($allTaskDirs -join ',') -RunDir $integDir `
      -Base 'main' -BuildCmd $BuildCmd -TestCmd $TestCmd -Model $Model
  $integSumPath = Join-Path $integDir 'summary.json'
  if (-not (Test-Path $integSumPath)) { $allOk = $false; Write-Host "=== tick5 СТОП: нет integ/summary.json ===" }
  else {
    $integSum = Get-Content -Raw $integSumPath | ConvertFrom-Json
    if (-not $integSum.integrated) {
      Write-Host "=== tick5 СТОП: интеграция не пройдена — $($integSum.fail_reason) ==="
      $allOk = $false
    }
  }

  # ─── Фаза 3: LAND (один раз; combined task = union scope_paths + all DoDs) ───
  if ($allOk) {
    Write-Host ""
    Write-Host "=== Фаза 3: land ==="
    $allScopePaths = @(); $allDods = @()
    foreach ($tp in $allTaskPaths) {
      $txt = Get-Content -Raw $tp
      $fm = if ($txt -match '(?m)^scope_paths:\s*\[([^\]]*)\]') { @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @() }
      $allScopePaths += $fm
      $title = if ($txt -match '(?m)^title:\s*(.+)$') { $Matches[1].Trim() } else { [IO.Path]::GetFileNameWithoutExtension($tp) }
      $body = ($txt -split '(?m)^---\s*$', 3)[2]
      $allDods += "### $title`n$body"
    }
    $combinedScope = ($allScopePaths | Select-Object -Unique) -join ', '
    $waveTaskFile = Join-Path $runDir 'combined-task.md'
    $nTasks = $allTaskPaths.Count
    $waveTaskContent = @"
---
id: run-combined
repo: $repo
scope_paths: [$combinedScope]
---

## DoD ($nTasks задач)

$($allDods -join "`n---`n")
"@
    Set-Content $waveTaskFile $waveTaskContent
    & (Join-Path $Bin 'land.ps1') -RunDir $integDir -Task $waveTaskFile -Autonomy $Autonomy -Model $Model
  }

  Write-Host ""
  if ($allOk) { Write-Host "=== tick5 OK: $($waves.Count) волн, $($allTaskPaths.Count) задач ===" }
  Write-Host "Артефакты: $runDir"
  Write-Host "Abandon all: pwsh $($MyInvocation.MyCommand.Path) -AbandonRun $runId"
}
finally { Exit-Lock }
