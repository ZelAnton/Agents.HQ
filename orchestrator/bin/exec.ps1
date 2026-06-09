#requires -Version 7
<#
.SYNOPSIS
  Исполнительный шаг Дирижёра (фаза P2): исполнить ОДНУ подзадачу в ИЗОЛИРОВАННОЙ jj-workspace.
  Изоляция через `jj workspace add` (underlying-примитив; ws.exe пока stale 0.13.18 — адоптируем в P3+).
  Запускает hq-exec (claude -p) в workspace, прогоняет build+test как АВТОРИТЕТНЫЙ гейт, пишет результат+diff
  в _runs/. БЕЗ auto-land (P2): человек ревьюит и решает land (jj через main) или abandon.

.EXAMPLE
  ./exec.ps1 -Task ../_fixtures/sample-exec-task.md          # исполнить (создаёт workspace, не лендит)
  ./exec.ps1 -Repo ProcessKit-rs -Abandon hq-exec-XXXX        # откатить workspace
#>
[CmdletBinding()]
param(
  [string]$Task,                    # путь к спеке задачи (frontmatter: repo, scope_paths, build_cmd, test_cmd)
  [string]$Abandon,                 # имя workspace для отката (с -Repo)
  [string]$Repo,                    # имя репо (для -Abandon; иначе берётся из задачи)
  [string]$Model = 'sonnet',
  [int]$ExecTimeoutSec = 600
)
$ErrorActionPreference = 'Stop'
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent
$WtRoot = Join-Path $Personal '.hq-worktrees'   # scratch вне всех репо (D:, не в .git/.jj)
$LockFile = Join-Path $Orch '.lock'

function Enter-Lock {
  $a = 0
  while ($true) {
    try { $fs = [IO.File]::Open($LockFile, 'CreateNew', 'Write', 'None'); $sw = [IO.StreamWriter]::new($fs); $sw.WriteLine("$PID`t$(Get-Date -Format o)"); $sw.Dispose(); $fs.Dispose(); return }
    catch {
      if ($a -ge 1) { throw "Активен другой тик (lock: $LockFile)." }
      $a++; $stale = $true; $alive = $false
      try { $p = (Get-Content -Raw $LockFile) -split "`t"; $stale = ((Get-Date) - [datetime]$p[1]).TotalMinutes -gt 30; $alive = [bool](Get-Process -Id ([int]$p[0]) -ErrorAction SilentlyContinue) } catch {}
      if ($stale -or -not $alive) { Remove-Item -Force $LockFile -ErrorAction SilentlyContinue; continue }
      throw "Активен другой тик (lock: $LockFile)."
    }
  }
}
function Exit-Lock { Remove-Item -Force $LockFile -ErrorAction SilentlyContinue }

$LeakRx = @('[A-Za-z]:[\\/](?:GitHub|Users)', '/(?:GitHub|Users)/', 'ghp_[A-Za-z0-9]{20,}', 'xox[baprs]-', 'AKIA[0-9A-Z]{16}', 'BEGIN [A-Z ]*PRIVATE KEY')
function Find-Leaks([string]$t) { $h = @(); foreach ($rx in $LeakRx) { if ($t -match $rx) { $h += $rx } }; return $h }

function Invoke-Claude {
  param([string]$Cwd, [string]$SpecFile, [string]$SchemaFile, [string]$InputText)
  $schema = Get-Content -Raw $SchemaFile
  $err = [IO.Path]::GetTempFileName()
  Push-Location $Cwd
  try {
    $raw = & claude -p $InputText `
        --append-system-prompt-file $SpecFile `
        --output-format json --json-schema $schema `
        --permission-mode acceptEdits `
        --allowedTools 'Read,Edit,Write,Glob,Grep,Bash(cargo:*),Bash(jj:*)' `
        --model $Model 2>$err | Out-String
  } finally { Pop-Location }
  $e = $null; try { $e = $raw | ConvertFrom-Json } catch {}
  if ($e.structured_output) { Remove-Item $err -EA SilentlyContinue; return $e.structured_output }
  if ($e.result) {
    $r = [string]$e.result; try { return ($r | ConvertFrom-Json) } catch {}
    $a = $r.IndexOf('{'); $b = $r.LastIndexOf('}'); if ($a -ge 0 -and $b -gt $a) { try { return ($r.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch {} }
  }
  $et = Get-Content -Raw $err -EA SilentlyContinue; Remove-Item $err -EA SilentlyContinue
  throw "claude -p не дал валидный JSON. stderr: $et"
}

function Get-Fm([string]$text, [string]$key) {
  if ($text -match "(?m)^${key}:\s*\[([^\]]*)\]") { return @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  if ($text -match "(?m)^${key}:\s*(.+)$") { return @($Matches[1].Trim()) }
  return @()
}
# null-safe «первый элемент» (PowerShell разворачивает пустой массив из функции в $null → (Get-Fm)[0] падает)
function Fm1([string]$text, [string]$key) { $a = @(Get-Fm $text $key); if ($a.Count) { $a[0] } else { $null } }

# ---------- ABANDON ----------
if ($Abandon) {
  if (-not $Repo) { throw 'для -Abandon нужен -Repo' }
  $repoPath = Join-Path $Personal $Repo
  Push-Location $repoPath
  try {
    Write-Host "=== abandon workspace '$Abandon' в $Repo ==="
    jj workspace forget $Abandon 2>&1 | Write-Host
  } finally { Pop-Location }
  $dest = Join-Path $WtRoot "$Repo\$Abandon"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest; Write-Host "удалён каталог: $dest" }
  Write-Host "abandon выполнен. Проверь в ${Repo}: jj st / jj log (рабочая копия и main не затронуты)."
  return
}

# ---------- EXECUTE ----------
if (-not $Task) { throw 'нужен -Task <путь к спеке> (или -Abandon)' }
Enter-Lock
try {
  $taskText = Get-Content -Raw $Task
  $repo = Fm1 $taskText 'repo'; if (-not $repo) { $repo = Fm1 $taskText 'scope' }
  if (-not $repo) { throw "в задаче нет repo/scope" }
  $repoPath = Join-Path $Personal $repo
  if (-not (Test-Path (Join-Path $repoPath '.jj'))) { throw "$repo не jj-colocated ($repoPath)" }
  $scopePaths = @(Get-Fm $taskText 'scope_paths')
  $buildCmd = Fm1 $taskText 'build_cmd'; if (-not $buildCmd) { $buildCmd = 'cargo build' }
  $testCmd = Fm1 $taskText 'test_cmd';  if (-not $testCmd) { $testCmd = 'cargo test' }
  $body = ($taskText -split '(?m)^---\s*$', 3)[2]

  $runId = "exec-$(Get-Date -Format yyyyMMdd-HHmmss)-$PID"
  $wsName = "hq-$runId"
  $dest = Join-Path $WtRoot "$repo\$wsName"
  $runDir = Join-Path $Orch "_runs/$runId"; New-Item -ItemType Directory -Force $runDir | Out-Null
  New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null

  Write-Host "=== P2 exec: repo=$repo task=$(Split-Path $Task -Leaf) ==="
  # 1) изолированная workspace на базе main
  Push-Location $repoPath
  try {
    $base = 'main'; $null = jj log --no-pager -r 'main' 2>$null; if ($LASTEXITCODE -ne 0) { $base = '@-' }
    jj workspace add --name $wsName -r $base -m "hq-exec: $wsName" $dest 2>&1 | Write-Host
  } finally { Pop-Location }
  if (-not (Test-Path $dest)) { throw "workspace не создан: $dest" }
  Write-Host "workspace: $dest (name=$wsName)"

  # 2) исполнитель в workspace
  $inp = @"
Подзадача (исполни в ТЕКУЩЕЙ рабочей копии = корень workspace):
$body

Область (scope_paths), только эти пути: $($scopePaths -join ', ')
Команды гейта: build = '$buildCmd'; test = '$testCmd'.
Сделай изменение в пределах области, прогони build и test, выполни jj describe -m "<кратко>",
верни ТОЛЬКО JSON по executor-result.schema.json.
"@
  $res = $null
  try { $res = Invoke-Claude -Cwd $dest -SpecFile (Join-Path $Orch 'agents/hq-exec.md') -SchemaFile (Join-Path $Orch 'schemas/executor-result.schema.json') -InputText $inp }
  catch { Write-Host "ИСПОЛНИТЕЛЬ: $($_.Exception.Message)" }
  if ($res) { $res | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $runDir 'executor-result.json') }

  # 3) АВТОРИТЕТНЫЙ гейт: build+test сами (не доверяем self-report)
  Push-Location $dest
  $buildOk = $false; $testOk = $false
  try {
    Write-Host "--- gate: $buildCmd ---"; Invoke-Expression $buildCmd 2>&1 | Tee-Object (Join-Path $runDir 'build.log') | Select-Object -Last 5; $buildOk = ($LASTEXITCODE -eq 0)
    if ($buildOk) { Write-Host "--- gate: $testCmd ---"; Invoke-Expression $testCmd 2>&1 | Tee-Object (Join-Path $runDir 'test.log') | Select-Object -Last 8; $testOk = ($LASTEXITCODE -eq 0) }
    $diff = (jj diff --no-pager 2>&1 | Out-String); $diff | Set-Content (Join-Path $runDir 'diff.txt')
  } finally { Pop-Location }

  $leaks = Find-Leaks $diff
  $summary = [ordered]@{ run_id = $runId; repo = $repo; workspace = $wsName; dest = $dest
    executor_status = ($res.status); gate_build = $buildOk; gate_tests = $testOk
    out_of_scope = @($res.out_of_scope_touched); leaks = $leaks }
  $summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $runDir 'summary.json')

  Write-Host ""
  Write-Host "=== РЕЗУЛЬТАТ (P2, no-land) ==="
  Write-Host "executor.status : $($res.status)  | self build/tests: $($res.build)/$($res.tests)"
  Write-Host "ГЕЙТ (наш)      : build=$buildOk tests=$testOk"
  Write-Host "out_of_scope    : $(@($res.out_of_scope_touched) -join ', ')"
  Write-Host "leaks           : $(if($leaks.Count){$leaks -join ', '}else{'нет'})"
  Write-Host "Артефакты       : $runDir (diff.txt, build/test.log, executor-result.json)"
  Write-Host "Workspace       : $dest"
  Write-Host "Land (если ок)  : cd $repoPath ; jj bookmark move main --to $wsName@ ... (P4 автоматизирует; в P2 — вручную после ревью)"
  Write-Host "Abandon         : pwsh $($MyInvocation.MyCommand.Path) -Repo $repo -Abandon $wsName"
}
finally { Exit-Lock }
