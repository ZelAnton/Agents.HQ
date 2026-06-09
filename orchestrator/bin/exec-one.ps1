#requires -Version 7
<#
.SYNOPSIS
  Исполнение ОДНОЙ подзадачи в изолированной jj-workspace — БЕЗ lock (его держит scheduler tick.ps1).
  Используется и одиночно, и как job под hq-spawn (параллельно). Пишет всё в -RunDir; не лендит, не abandon-ит.
.EXAMPLE
  ./exec-one.ps1 -Task ../_fixtures/sample-exec-task.md -RunDir ../_runs/tick-XXXX/proc
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Task,
  [Parameter(Mandatory)][string]$RunDir,
  [string]$Model = 'sonnet'
)
$ErrorActionPreference = 'Stop'
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent
$WtRoot = Join-Path $Personal '.hq-worktrees'

function Get-Fm([string]$text, [string]$key) {
  if ($text -match "(?m)^${key}:\s*\[([^\]]*)\]") { return @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  if ($text -match "(?m)^${key}:\s*(.+)$") { return @($Matches[1].Trim()) }
  return @()
}
function Fm1([string]$t, [string]$k) { $a = @(Get-Fm $t $k); if ($a.Count) { $a[0] } else { $null } }
$LeakRx = @('[A-Za-z]:[\\/](?:GitHub|Users)', '/(?:GitHub|Users)/', 'ghp_[A-Za-z0-9]{20,}', 'xox[baprs]-', 'AKIA[0-9A-Z]{16}', 'BEGIN [A-Z ]*PRIVATE KEY')
function Find-Leaks([string]$t) { $h = @(); foreach ($rx in $LeakRx) { if ($t -match $rx) { $h += $rx } }; return $h }

function Invoke-Claude {
  param([string]$Cwd, [string]$SpecFile, [string]$SchemaFile, [string]$InputText)
  $schema = Get-Content -Raw $SchemaFile
  $err = [IO.Path]::GetTempFileName()
  Push-Location $Cwd
  try {
    $raw = & claude -p $InputText --append-system-prompt-file $SpecFile --output-format json --json-schema $schema `
        --permission-mode acceptEdits --allowedTools 'Read,Edit,Write,Glob,Grep,Bash(cargo:*),Bash(jj:*)' --model $Model 2>$err | Out-String
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

New-Item -ItemType Directory -Force $RunDir | Out-Null
$taskText = Get-Content -Raw $Task
$repo = Fm1 $taskText 'repo'; if (-not $repo) { $repo = Fm1 $taskText 'scope' }
if (-not $repo) { throw "в задаче нет repo/scope" }
$repoPath = Join-Path $Personal $repo
if (-not (Test-Path (Join-Path $repoPath '.jj'))) { throw "$repo не jj-colocated" }
$scopePaths = @(Get-Fm $taskText 'scope_paths')
$buildCmd = Fm1 $taskText 'build_cmd'; if (-not $buildCmd) { $buildCmd = 'cargo build' }
$testCmd = Fm1 $taskText 'test_cmd';  if (-not $testCmd) { $testCmd = 'cargo test' }
$body = ($taskText -split '(?m)^---\s*$', 3)[2]

$wsName = "hq-" + (Split-Path $RunDir -Leaf)
$dest = Join-Path $WtRoot "$repo\$wsName"
New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null

# 1) изолированная workspace на базе main
Push-Location $repoPath
try {
  $base = 'main'; $null = jj log --no-pager -r 'main' 2>$null; if ($LASTEXITCODE -ne 0) { $base = '@-' }
  jj workspace add --name $wsName -r $base -m "hq-exec: $wsName" $dest 2>&1 | Out-Null
} finally { Pop-Location }
if (-not (Test-Path $dest)) { throw "workspace не создан: $dest" }

# 2) исполнитель
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
catch { $execErr = $_.Exception.Message }
if ($res) { $res | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $RunDir 'executor-result.json') }

# 3) АВТОРИТЕТНЫЙ гейт
Push-Location $dest
$buildOk = $false; $testOk = $false; $diff = ''
try {
  Invoke-Expression $buildCmd 2>&1 | Tee-Object (Join-Path $RunDir 'build.log') | Out-Null; $buildOk = ($LASTEXITCODE -eq 0)
  if ($buildOk) { Invoke-Expression $testCmd 2>&1 | Tee-Object (Join-Path $RunDir 'test.log') | Out-Null; $testOk = ($LASTEXITCODE -eq 0) }
  $diff = (jj diff --no-pager 2>&1 | Out-String); $diff | Set-Content (Join-Path $RunDir 'diff.txt')
} finally { Pop-Location }

$leaks = Find-Leaks $diff
$summary = [ordered]@{ task = (Split-Path $Task -Leaf); repo = $repo; workspace = $wsName; dest = $dest
  executor_status = ($res.status); self_build = ($res.build); self_tests = ($res.tests)
  gate_build = $buildOk; gate_tests = $testOk; out_of_scope = @($res.out_of_scope_touched); leaks = $leaks
  exec_error = $execErr }
$summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RunDir 'summary.json')
Write-Host ("[{0}] repo={1} status={2} gate(build/test)={3}/{4} ws={5}" -f (Split-Path $RunDir -Leaf), $repo, $res.status, $buildOk, $testOk, $wsName)
if ($buildOk -and $testOk -and -not $leaks.Count -and ($res.status -eq 'done')) { exit 0 } else { exit 1 }
