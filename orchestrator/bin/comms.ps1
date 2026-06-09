#requires -Version 7
<#
.SYNOPSIS
  Headless-Дирижёр оркестра .hq (фаза P1): триаж входящего + планирование задач.
  Эквивалент интерактивного skill /comms. Сам код не пишет; зовёт claude -p на спецах агентов
  со структурным выводом (--json-schema). По умолчанию propose-only: пишет ТОЛЬКО в _runs/<run_id>/,
  реальные comms/QUEUE не мутирует. Тред T-20260609-vcs-processkit-feedback всегда пропускается.

.EXAMPLE
  ./comms.ps1 -Fixture ../_fixtures/sample-inbound      # валидация на фикстуре
  ./comms.ps1                                            # propose по реальному входящему (без мутаций)
#>
[CmdletBinding()]
param(
  [string]$Fixture,                 # путь к каталогу-фикстуре (thread.md + сообщения)
  [switch]$DryRun,                  # (по умолчанию propose-only и так не мутирует; флаг для явности)
  [string]$Only,                    # обработать только один thread-id
  [string]$Model = 'sonnet'         # модель для субагентов (дешевле для рутинных суждений)
)

$ErrorActionPreference = 'Stop'
$SkipList = @('T-20260609-vcs-processkit-feedback')

# --- пути ---
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent           # .hq/orchestrator
$HQ   = Split-Path $Orch -Parent          # .hq
$Repo = Split-Path $HQ -Parent            # d:/GitHub/Personal
$Agents  = Join-Path $Orch 'agents'
$Schemas = Join-Path $Orch 'schemas'
$RunId = if ($Fixture) { "fixture-$(Get-Date -Format yyyyMMdd-HHmm)" } else { "$(Get-Date -Format yyyyMMdd-HHmm)-tick" }
$RunDir = Join-Path $Orch "_runs/$RunId"
foreach ($d in 'triage','plan','proposed-replies','proposed-tasks') { New-Item -ItemType Directory -Force (Join-Path $RunDir $d) | Out-Null }

# --- вызов специалиста через claude -p со схемой ---
function Invoke-Specialist {
  param([string]$SpecFile, [string]$SchemaFile, [string]$InputText)
  $schema = Get-Content -Raw $SchemaFile
  # ВНИМАНИЕ: если установленный claude ожидает путь к файлу схемы вместо строки —
  # заменить ($schema) на ($SchemaFile). Проверяется на этапе сборки (claude -p --help).
  $raw = $InputText | claude -p `
      --append-system-prompt-file $SpecFile `
      --output-format json `
      --json-schema $schema `
      --permission-mode acceptEdits `
      --allowedTools 'Read,Glob,Grep' `
      --add-dir $HQ `
      --model $Model 2>&1 | Out-String
  $env = $null; try { $env = $raw | ConvertFrom-Json } catch { }
  if ($env.structured_output) { return $env.structured_output }
  if ($env.result) { try { return ($env.result | ConvertFrom-Json) } catch { return $env.result } }
  throw "Не удалось распарсить вывод claude: $raw"
}

# --- собрать входящее ---
function Get-Inbound {
  if ($Fixture) {
    $f = Resolve-Path $Fixture
    $t = Join-Path $f 'thread.md'
    return @([pscustomobject]@{ id='T-fixture-sample'; path=$t; text=((Get-ChildItem $f -Filter *.md | Get-Content -Raw) -join "`n---`n") })
  }
  $threads = Get-ChildItem (Join-Path $HQ 'comms/threads') -Directory -ErrorAction SilentlyContinue
  $items = foreach ($th in $threads) {
    $tm = Join-Path $th.FullName 'thread.md'
    if (-not (Test-Path $tm)) { continue }
    $body = Get-Content -Raw $tm
    if ($SkipList -contains $th.Name) { continue }
    if ($body -notmatch '(?m)^status:\s*open') { continue }
    if ($body -notmatch '(?m)^awaiting:.*[A-Za-z]') { continue }   # есть репо в awaiting
    if ($Only -and $th.Name -ne $Only) { continue }
    [pscustomobject]@{ id=$th.Name; path=$tm; text=((Get-ChildItem $th.FullName -Filter *.md | Get-Content -Raw) -join "`n---`n") }
  }
  return @($items)
}

# --- main ---
$inbound = Get-Inbound
$tick = [ordered]@{ run_id=$RunId; started=(Get-Date -Format o); mode=($(if($Fixture){'fixture'}else{'dry-run'}));
                    scanned=@(); skipped=$SkipList; triaged=@(); planned=@(); errors=@(); notes='headless P1 propose-only' }

foreach ($it in $inbound) {
  $tick.scanned += $it.id
  $repo = if ($it.text -match '(?m)^to:\s*(\S+)') { $Matches[1] } else { 'unknown' }
  $inputText = "Адресат: $repo`nПрочитай $HQ/projects/$repo/card.md и $HQ/knowledge/ownership.md.`nВходящее:`n$($it.text)`nВерни ТОЛЬКО JSON по triage.schema.json."
  try {
    $tri = Invoke-Specialist -SpecFile (Join-Path $Agents 'hq-triage.md') -SchemaFile (Join-Path $Schemas 'triage.schema.json') -InputText $inputText
    $tri | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $RunDir "triage/$($it.id).json")
    if ($tri.reply_md) { $tri.reply_md | Set-Content (Join-Path $RunDir "proposed-replies/$($it.id).md") }
    $tick.triaged += [ordered]@{ item=$it.id; decision=$tri.decision; seed_title=($tri.seed.title) }
    if ($tri.decision -eq 'accept' -and $tri.seed) {
      $seedJson = $tri.seed | ConvertTo-Json -Depth 12
      $plInput = "seed: $seedJson`nПрочитай карточки затронутых репо, $HQ/knowledge/dependency-graph.md и текущий $HQ/tasks/QUEUE.md (для следующих номеров TASK-####). Верни ТОЛЬКО JSON по planner.schema.json."
      $pl = Invoke-Specialist -SpecFile (Join-Path $Agents 'hq-planner.md') -SchemaFile (Join-Path $Schemas 'planner.schema.json') -InputText $plInput
      $pl | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $RunDir "plan/$($it.id).json")
      foreach ($task in $pl.tasks) {
        $task.spec_md | Set-Content (Join-Path $RunDir "proposed-tasks/$($task.id).md")
        $tick.planned += $task.id
      }
    }
  } catch {
    $tick.errors += "[$($it.id)] $($_.Exception.Message)"
  }
}

$tick | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $RunDir 'tick.json')
Write-Host "=== comms (headless) run_id=$RunId ==="
Write-Host "scanned: $($tick.scanned -join ', ')  | skipped: $($tick.skipped -join ', ')"
foreach ($t in $tick.triaged) { Write-Host ("  {0} -> {1} {2}" -f $t.item, $t.decision, $t.seed_title) }
Write-Host "planned: $($tick.planned -join ', ')"
if ($tick.errors.Count) { Write-Host "ERRORS:`n  $($tick.errors -join "`n  ")" }
Write-Host "Предложения в: $RunDir  (реальные comms/QUEUE НЕ изменены)"
