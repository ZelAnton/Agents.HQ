#requires -Version 7
<#
.SYNOPSIS
  Один тик диспетчера .hq с лимитами из automation.json. Headless-эквивалент /hq-tick;
  тело для `/loop /hq-tick`. Без LLM сам по себе — запускает hq-conductor tick (детерминированный).
.DESCRIPTION
  Приоритет лимитов: CLI-аргумент > automation.json > встроенный дефолт.
  Если automation.json paused=true — пропуск (conductor проверяет это и сам, здесь — ранний выход
  с понятным сообщением). Пути выводятся из расположения скрипта, без захардкоженных абсолютов.
.EXAMPLE
  ./hq-tick.ps1                       # auto-low, лимиты из automation.json
  ./hq-tick.ps1 -Mode assist          # сухой прогон (показывает план, не спавнит)
  ./hq-tick.ps1 -MaxExec 0            # тик без exec-фазы
#>
[CmdletBinding()]
param(
  [ValidateSet('mock', 'assist', 'auto-low')]
  [string]$Mode = 'auto-low',
  # -1 = «не задано» → берём из automation.json, иначе дефолт. 0 — валидно (отключить роль).
  [int]$MaxPlan = -1,
  [int]$MaxExec = -1,
  [int]$MaxReview = -1
)
$ErrorActionPreference = 'Stop'
$Bin  = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ   = Split-Path $Orch -Parent

$autoPath = Join-Path $Orch 'automation.json'
$auto = if (Test-Path $autoPath) { Get-Content -Raw $autoPath | ConvertFrom-Json } else { $null }

if ($auto -and $auto.paused) {
  Write-Host 'hq-tick: paused (automation.json) — новые спавны приостановлены, пропуск тика'
  exit 0
}

# CLI (>=0) переопределяет automation.json; automation.json переопределяет встроенный дефолт.
function Resolve-Limit([int]$cli, [string]$key, [int]$def) {
  if ($cli -ge 0) { return $cli }
  if ($auto -and $null -ne $auto.$key) { return [int]$auto.$key }
  return $def
}
$mp = Resolve-Limit $MaxPlan   'max_plan'   1
$me = Resolve-Limit $MaxExec   'max_exec'   2
$mr = Resolve-Limit $MaxReview 'max_review' 1

$exe = Join-Path $Bin 'hq-conductor/target/release/hq-conductor.exe'
if (-not (Test-Path $exe)) { throw "нет hq-conductor.exe: $exe (нужен cargo build --release в bin/hq-conductor)" }

& $exe --hq $HQ tick --mode $Mode --max-plan $mp --max-exec $me --max-review $mr
exit $LASTEXITCODE
