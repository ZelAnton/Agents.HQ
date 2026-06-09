#requires -Version 7
<#
.SYNOPSIS
  Scheduler оркестратора (фаза P3): исполнить НЕСКОЛЬКО задач в РАЗНЫХ репо ПАРАЛЛЕЛЬНО через hq-spawn
  (processkit: ограниченный параллелизм + per-job таймаут + kill-on-drop дерева). Без auto-land.
  Держит lock (один активный тик); сами исполнители (exec-one.ps1) — lock-free.
.EXAMPLE
  ./tick.ps1 -Tasks ../_fixtures/sample-exec-task.md,../_fixtures/sample-exec-task-2.md -Limit 2
  ./tick.ps1 -AbandonRun tick-20260610-001122-1234     # откатить все workspace прогона
#>
[CmdletBinding()]
param(
  [string[]]$Tasks,
  [int]$Limit = 4,
  [int]$TimeoutSec = 900,
  [string]$Model = 'sonnet',
  [string]$AbandonRun
)
$ErrorActionPreference = 'Stop'
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent
$SpawnBin = Join-Path $Bin 'hq-spawn/target/release/hq-spawn.exe'
$ExecOne = Join-Path $Bin 'exec-one.ps1'
$LockFile = Join-Path $Orch '.lock'

function Enter-Lock {
  $a = 0
  while ($true) {
    try { $fs = [IO.File]::Open($LockFile, 'CreateNew', 'Write', 'None'); $sw = [IO.StreamWriter]::new($fs); $sw.WriteLine("$PID`t$(Get-Date -Format o)"); $sw.Dispose(); $fs.Dispose(); return }
    catch {
      if ($a -ge 1) { throw "Активен другой тик (lock: $LockFile)." }
      $a++; $stale = $true; $alive = $false
      try { $p = (Get-Content -Raw $LockFile) -split "`t"; $stale = ((Get-Date) - [datetime]$p[1]).TotalMinutes -gt 60; $alive = [bool](Get-Process -Id ([int]$p[0]) -ErrorAction SilentlyContinue) } catch {}
      if ($stale -or -not $alive) { Remove-Item -Force $LockFile -EA SilentlyContinue; continue }
      throw "Активен другой тик (lock: $LockFile)."
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

# ---------- EXECUTE (parallel) ----------
if (-not $Tasks -or $Tasks.Count -eq 0) { throw "нужен -Tasks <пути через запятую> (ready-set из QUEUE — позже)" }
Enter-Lock
try {
  $runId = "tick-$(Get-Date -Format yyyyMMdd-HHmmss)-$PID"
  $runDir = Join-Path $Orch "_runs/$runId"; New-Item -ItemType Directory -Force $runDir | Out-Null

  # собрать jobs + проверить кросс-репо
  $jobs = @(); $repos = @{}
  foreach ($t in $Tasks) {
    $tp = (Resolve-Path $t).Path
    $base = [IO.Path]::GetFileNameWithoutExtension($tp)
    $perRun = Join-Path $runDir $base
    $tt = Get-Content -Raw $tp
    $r = if ($tt -match '(?m)^repo:\s*(.+)$') { $Matches[1].Trim() } elseif ($tt -match '(?m)^scope:\s*(.+)$') { $Matches[1].Trim() } else { '?' }
    if ($repos.ContainsKey($r)) { Write-Host "ВНИМАНИЕ: две задачи в одном репо ($r) — P3 рассчитан на КРОСС-репо; внутри-репо параллель — P5." }
    $repos[$r] = $true
    $jobs += [ordered]@{ id = $base; program = 'pwsh'; args = @('-NoProfile', '-File', $ExecOne, '-Task', $tp, '-RunDir', $perRun, '-Model', $Model); timeout_sec = $TimeoutSec }
  }
  $jobsFile = Join-Path $runDir 'jobs.json'
  $jobs | ConvertTo-Json -Depth 8 -AsArray | Set-Content $jobsFile
  $resultsFile = Join-Path $runDir 'results.json'

  Write-Host "=== tick ${runId}: $($jobs.Count) задач, репо=[$((@($repos.Keys)) -join ', ')], limit=$Limit ==="
  $wall = Measure-Command { & $SpawnBin --jobs $jobsFile --limit $Limit --out $resultsFile 2>&1 | Out-Null }

  $results = if (Test-Path $resultsFile) { Get-Content -Raw $resultsFile | ConvertFrom-Json } else { @() }
  $sumMs = ($results | Measure-Object -Property ms -Sum).Sum
  Write-Host ""
  Write-Host "=== РЕЗУЛЬТАТ (P3, no-land) ==="
  foreach ($res in $results) {
    $sp = Join-Path $runDir "$($res.id)/summary.json"
    $s = if (Test-Path $sp) { Get-Content -Raw $sp | ConvertFrom-Json } else { $null }
    Write-Host ("  {0,-22} repo={1,-16} spawn(code={2} timed_out={3} {4}ms) gate(build/test)={5}/{6}" -f `
        $res.id, ($s.repo), $res.code, $res.timed_out, $res.ms, ($s.gate_build), ($s.gate_tests))
  }
  Write-Host ""
  Write-Host ("Параллелизм: сумма job-времён={0}ms, wall={1}ms → overlap≈{2:N2}x (limit={3})" -f $sumMs, [int]$wall.TotalMilliseconds, ($(if ($wall.TotalMilliseconds) { $sumMs / $wall.TotalMilliseconds } else { 0 })), $Limit)
  Write-Host "Артефакты: $runDir (jobs.json, results.json, <task>/{diff,build/test.log,summary.json})"
  Write-Host "Abandon all: pwsh $($MyInvocation.MyCommand.Path) -AbandonRun $runId"
}
finally { Exit-Lock }
