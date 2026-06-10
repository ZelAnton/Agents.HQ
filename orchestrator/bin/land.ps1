#requires -Version 7
<#
.SYNOPSIS
  Шаг ПРИЗЕМЛЕНИЯ (фаза P4): по результату исполнения (exec-one) — интегрировать изменение на свежий
  main@origin, провести жёсткий гейт «нет конфликтов» (§11.3), Верификатор (hq-verify), детерминированный
  fail-closed `risk()` (§11.1). Если риск low И autonomy=auto-low → AUTO-LAND (advance main + push).
  Иначе → завести DEC человеку (§11.2/§11.4/§11.7) и оставить workspace.
  Конфликты НЕ авто-разрешаются (это P5): конфликт ⇒ DEC.
.EXAMPLE
  ./land.ps1 -RunDir ../_runs/p4-case1 -Task ../_fixtures/sample-scratch-low.md -Autonomy auto-low
  ./land.ps1 -Resume DEC-0001          # человек ответил в DEC — исполнить выбор (land|abandon)
#>
[CmdletBinding()]
param(
  [string]$RunDir,
  [string]$Task,
  [ValidateSet('propose', 'assist', 'auto-low')][string]$Autonomy,
  [int]$SizeLimit = 200,
  [string]$Model = 'sonnet',
  [string]$Remote = 'origin',
  [string]$Resume
)
$ErrorActionPreference = 'Stop'
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent
$DecDir = Join-Path $HQ 'human/decisions'
$Inbox = Join-Path $HQ 'human/INBOX.md'

# ---------- helpers (как в exec-one.ps1) ----------
function Get-Fm([string]$text, [string]$key) {
  if ($text -match "(?m)^${key}:\s*\[([^\]]*)\]") { return @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  if ($text -match "(?m)^${key}:\s*(.+)$") { return @($Matches[1].Trim()) }
  return @()
}
function Fm1([string]$t, [string]$k) { $a = @(Get-Fm $t $k); if ($a.Count) { $a[0] } else { $null } }
$LeakRx = @('[A-Za-z]:[\\/](?:GitHub|Users)', '/(?:GitHub|Users)/', 'ghp_[A-Za-z0-9]{20,}', 'xox[baprs]-', 'AKIA[0-9A-Z]{16}', 'BEGIN [A-Z ]*PRIVATE KEY')
function Find-Leaks([string]$t) { $h = @(); foreach ($rx in $LeakRx) { if ($t -match $rx) { $h += $rx } }; return $h }
# чувствительные пути ⇒ риск НЕ-low (§11.1): CI/релиз, манифесты, секреты, миграции
$SensitiveRx = @(
  '(^|[\\/])\.github[\\/]', '(^|[\\/])\.gitlab', '(^|[\\/])Cargo\.toml$', '(^|[\\/])Cargo\.lock$',
  '\.(csproj|fsproj|vbproj|sln|props|targets|nuspec)$', '(^|[\\/])(\.env|\.npmrc|\.pypirc)',
  'secret', 'credential', '(^|[\\/])migrations?[\\/]', '(^|[\\/])CHANGELOG\.md$', '\.ya?ml$'
)
function Find-Sensitive([string[]]$paths) { $h = @(); foreach ($p in $paths) { foreach ($rx in $SensitiveRx) { if ($p -match $rx) { $h += $p; break } } }; return @($h) }

function Invoke-Claude {
  param([string]$Cwd, [string]$SpecFile, [string]$SchemaFile, [string]$InputText)
  $schema = Get-Content -Raw $SchemaFile
  $err = [IO.Path]::GetTempFileName()
  Push-Location $Cwd
  try {
    $raw = & claude -p $InputText --append-system-prompt-file $SpecFile --output-format json --json-schema $schema `
        --permission-mode acceptEdits --allowedTools 'Read,Glob,Grep,Bash(jj:*),Bash(cargo:*)' --model $Model 2>$err | Out-String
  } finally { Pop-Location }
  $e = $null; try { $e = $raw | ConvertFrom-Json } catch {}
  if ($e.structured_output) { Remove-Item $err -EA SilentlyContinue; return $e.structured_output }
  if ($e.result) {
    $r = [string]$e.result; try { return ($r | ConvertFrom-Json) } catch {}
    $a = $r.IndexOf('{'); $b = $r.LastIndexOf('}'); if ($a -ge 0 -and $b -gt $a) { try { return ($r.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch {} }
  }
  $et = Get-Content -Raw $err -EA SilentlyContinue; Remove-Item $err -EA SilentlyContinue
  throw "hq-verify: claude -p без валидного JSON. stderr: $et"
}

function Get-Autonomy([string]$repo) {
  $card = Join-Path $HQ "projects/$repo/card.md"
  if (Test-Path $card) { $a = Fm1 (Get-Content -Raw $card) 'autonomy'; if ($a) { return $a } }
  return 'propose'   # дефолт fail-closed: нет карточки/поля ⇒ только предложение, без auto-land
}

function Next-DecId {
  $max = 0
  if (Test-Path $DecDir) { Get-ChildItem $DecDir -Filter 'DEC-*.md' -EA SilentlyContinue | ForEach-Object { if ($_.Name -match 'DEC-(\d+)') { $n = [int]$Matches[1]; if ($n -gt $max) { $max = $n } } } }
  return ('DEC-{0:D4}' -f ($max + 1))
}

# Поднять main@origin → revset изменения; вернуть фактический commit (или $null)
function Rev-Commit([string]$repoPath, [string]$revset) {
  Push-Location $repoPath
  try { $c = (jj log --no-pager -r $revset --no-graph -T 'commit_id.short()' 2>$null | Out-String).Trim() } finally { Pop-Location }
  if ($LASTEXITCODE -ne 0 -or -not $c) { return $null }
  return ($c -split '\r?\n')[0]
}

# Выполнить приземление: main → change, push. Возвращает текст результата.
function Invoke-Land([string]$repoPath, [string]$change, [string]$remote) {
  Push-Location $repoPath
  try {
    jj bookmark move main --to $change 2>&1 | Out-String | Write-Verbose
    $push = jj git push --remote $remote --bookmark main 2>&1 | Out-String
    $at = (jj log --no-pager -r "main@$remote" --no-graph -T 'change_id.short() ++ " " ++ description.first_line()' 2>&1 | Out-String).Trim()
  } finally { Pop-Location }
  return @{ push = $push; main_at_remote = $at }
}

# ============================ RESUME (человек ответил в DEC) ============================
if ($Resume) {
  $decFile = Get-ChildItem $DecDir -Filter "$Resume*.md" -EA SilentlyContinue | Select-Object -First 1
  if (-not $decFile) { throw "нет файла решения для $Resume в $DecDir" }
  $dt = Get-Content -Raw $decFile.FullName
  if ((Fm1 $dt 'status') -ne 'answered') { throw "$Resume ещё не answered — заполни answer + status: answered в $($decFile.Name)" }
  $consumed = Fm1 $dt 'consumed-at'
  if ($consumed -and $consumed -ne 'null') { throw "$Resume уже обработан (consumed-at=$consumed)." }
  # answer.decision лежит с отступом в блоке answer:; берём токен до возможного # комментария
  $decision = $null; if ($dt -match '(?m)^\s+decision:\s*([^\s#]+)') { $decision = $Matches[1] }
  if ($decision -eq 'null') { $decision = $null }
  if (-not $decision) { throw "${Resume}: answer.decision не заполнен (укажи A|B или land|abandon)." }
  $repo = Fm1 $dt 'land-repo'; $change = Fm1 $dt 'land-change'; $ws = Fm1 $dt 'land-workspace'; $dest = Fm1 $dt 'land-dest'; $remote = Fm1 $dt 'land-remote'
  if (-not $remote) { $remote = 'origin' }
  $repoPath = Join-Path $Personal $repo
  Write-Host "RESUME $Resume → decision=$decision repo=$repo change=$change"
  if ($decision -in @('A', 'land')) {
    $r = Invoke-Land $repoPath $change $remote
    Write-Host "  LANDED. main@$remote → $($r.main_at_remote)"
  }
  elseif ($decision -in @('B', 'abandon')) {
    Push-Location $repoPath; try { jj workspace forget $ws 2>&1 | Out-Null } finally { Pop-Location }
    if ($dest -and (Test-Path $dest)) { Remove-Item -Recurse -Force $dest }
    Write-Host "  ABANDONED ws=$ws (без land)."
  }
  else { Write-Host "  decision='$decision' не распознан как land/abandon — ничего не делаю."; return }
  # отметить обработанным (идемпотентность §11.7)
  $stamped = $dt -replace '(?m)^(consumed-at:).*$', "consumed-at: $(Get-Date -Format yyyy-MM-dd)"
  if ($stamped -eq $dt) { $stamped = $dt -replace '(?m)^(status:\s*answered.*)$', "`$1`nconsumed-at: $(Get-Date -Format yyyy-MM-dd)" }
  Set-Content $decFile.FullName $stamped
  return
}

# ============================ НОРМАЛЬНЫЙ ШАГ LAND ============================
if (-not $RunDir) { throw "нужен -RunDir <дир exec-one> (или -Resume <DEC>)" }
if (-not $Task) { throw "нужен -Task <спека задачи> (для DoD/scope в Верификатор)" }
$RunDir = (Resolve-Path $RunDir).Path
$summaryPath = Join-Path $RunDir 'summary.json'
if (-not (Test-Path $summaryPath)) { throw "нет summary.json в $RunDir — сначала exec-one." }
$sum = Get-Content -Raw $summaryPath | ConvertFrom-Json
$repo = $sum.repo; $ws = $sum.workspace; $dest = $sum.dest
$repoPath = Join-Path $Personal $repo
if (-not (Test-Path (Join-Path $repoPath '.jj'))) { throw "$repo не jj-репо" }

$taskText = Get-Content -Raw $Task
$dod = ($taskText -split '(?m)^---\s*$', 3)[2]
$scopePaths = @(Get-Fm $taskText 'scope_paths')
$buildCmd = Fm1 $taskText 'build_cmd'; if (-not $buildCmd) { $buildCmd = 'cargo build' }
$testCmd = Fm1 $taskText 'test_cmd';  if (-not $testCmd) { $testCmd = 'cargo test' }

$autonomy = if ($Autonomy) { $Autonomy } else { Get-Autonomy $repo }
Write-Host "=== LAND repo=$repo ws=$ws autonomy=$autonomy ==="

# change_id рабочей копии workspace (стабилен при rebase)
$change = (& { Push-Location $repoPath; try { (jj log --no-pager -r "${ws}@" --no-graph -T 'change_id.short()' 2>$null | Out-String).Trim() } finally { Pop-Location } })
if (-not $change) { throw "не нашёл change для workspace $ws (ws жива?)" }
$change = ($change -split '\r?\n')[0]

# ---------- 1) ИНТЕГРАЦИЯ: fetch + (rebase на свежий main@origin при сдвиге) ----------
$integrationNote = @()
Push-Location $repoPath
try {
  jj git fetch --remote $Remote 2>&1 | Out-String | Write-Verbose
} finally { Pop-Location }
$baseRev = if (Rev-Commit $repoPath "main@$Remote") { "main@$Remote" } else { 'main' }
$baseCommit = Rev-Commit $repoPath $baseRev
$parentCommit = Rev-Commit $repoPath "${change}-"
if ($baseCommit -and $parentCommit -and ($baseCommit -ne $parentCommit)) {
  $integrationNote += "main сдвинулся ($parentCommit→$baseCommit) — rebase изменения на $baseRev"
  Push-Location $repoPath
  try { jj rebase -s $change -d $baseRev 2>&1 | Out-String | Write-Verbose } finally { Pop-Location }
} else { $integrationNote += "main не двигался — интеграция без rebase" }

# ---------- 2) ЖЁСТКИЙ ГЕЙТ §11.3: нет нерешённых jj-конфликтов ----------
$conflicted = Rev-Commit $repoPath "($change | conflicts()) & conflicts()"
$hasConflict = [bool]$conflicted

# ---------- 3) собрать diff/файлы изменения (после интеграции) ----------
Push-Location $repoPath
try {
  $diffSummary = (jj diff --no-pager -r $change --summary 2>&1 | Out-String)
  $diffText = (jj diff --no-pager -r $change --git 2>&1 | Out-String)
  $isEmpty = ((jj log --no-pager -r $change --no-graph -T 'empty' 2>$null | Out-String).Trim() -eq 'true')
} finally { Pop-Location }
$changedFiles = @($diffSummary -split '\r?\n' | Where-Object { $_ -match '^\s*[A-Z]\s+(.+)$' } | ForEach-Object { ($_ -replace '^\s*[A-Z]\s+', '').Trim() })
$sizeLines = @($diffText -split '\r?\n' | Where-Object { $_ -match '^[+-]' -and $_ -notmatch '^[+-]{3}' }).Count
$sensitive = Find-Sensitive $changedFiles
$diffLeaks = Find-Leaks $diffText

# ---------- 4) АВТОРИТЕТНЫЙ гейт build/test (перезапуск в ws, только если кандидат на auto-land) ----------
if ($autonomy -eq 'auto-low' -and -not $hasConflict -and -not $isEmpty) {
  Push-Location $dest
  $buildOk = $false; $testOk = $false
  try {
    Invoke-Expression $buildCmd 2>&1 | Tee-Object (Join-Path $RunDir 'land-build.log') | Out-Null; $buildOk = ($LASTEXITCODE -eq 0)
    if ($buildOk) { Invoke-Expression $testCmd 2>&1 | Tee-Object (Join-Path $RunDir 'land-test.log') | Out-Null; $testOk = ($LASTEXITCODE -eq 0) }
  } finally { Pop-Location }
} else {
  # не кандидат на land — берём гейт исполнителя из summary (skipped ⇒ не-зелёный, см. exec-one)
  $buildOk = [bool]$sum.gate_build; $testOk = [bool]$sum.gate_tests
}

# ---------- 5) ВЕРИФИКАТОР (hq-verify) ----------
$verify = $null; $verifyErr = $null
$vInput = @"
DoD задачи (изменение ОБЯЗАНО его покрыть):
$dod

Объявленный scope_paths (выход за него — сигнал): $($scopePaths -join ', ')

Изменённые файлы:
$diffSummary

Diff (git-формат):
$diffText

Проверь покрытие DoD, объём (scope), корректность, безопасность/утечки, чувствительные зоны.
Верни ТОЛЬКО JSON по verify.schema.json.
"@
try { $verify = Invoke-Claude -Cwd $dest -SpecFile (Join-Path $Orch 'agents/hq-verify.md') -SchemaFile (Join-Path $Orch 'schemas/verify.schema.json') -InputText $vInput }
catch { $verifyErr = $_.Exception.Message }
if ($verify) { $verify | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $RunDir 'verify.json') }

# ---------- 6) risk() — детерминированно, FAIL-CLOSED (§11.1/§11.2/§11.3) ----------
$execOutOfScope = @($sum.out_of_scope)
$verifyOutOfScope = @($verify.out_of_scope)
$conflictsResolved = @()   # P4: слияний нет (конфликт ⇒ DEC). Поле для P5.
$reasons = @()
if ($isEmpty) { $reasons += 'изменение пустое' }
if ($hasConflict) { $reasons += 'есть нерешённые jj-конфликты (§11.3)' }
if (-not $buildOk) { $reasons += 'build не зелёный' }
if (-not $testOk) { $reasons += 'tests не зелёные (или skipped)' }
if (-not $verify) { $reasons += "Верификатор недоступен/ошибка: $verifyErr" }
elseif ($verify.verdict -ne 'pass') { $reasons += "Верификатор verdict=$($verify.verdict)" }
if ($verify -and -not $verify.dod_met) { $reasons += 'DoD не покрыт (dod_met=false)' }
if ($execOutOfScope.Count -or $verifyOutOfScope.Count) { $reasons += "выход за scope: $((@($execOutOfScope) + @($verifyOutOfScope)) -join ', ')" }
if ($conflictsResolved.Count) { $reasons += 'были разрешённые конфликты ⇒ не-low (§11.2)' }
if ($sensitive.Count) { $reasons += "чувствительные пути: $($sensitive -join ', ')" }
if ($sizeLines -gt $SizeLimit) { $reasons += "объём $sizeLines строк > порога $SizeLimit" }
if ($diffLeaks.Count) { $reasons += "возможные утечки: $($diffLeaks -join ', ')" }
$riskLow = ($reasons.Count -eq 0)
$risk = if ($riskLow) { 'low' } else { 'not-low' }

Write-Host "  change=$change empty=$isEmpty conflict=$hasConflict build/test=$buildOk/$testOk verify=$(if($verify){$verify.verdict}else{'ERR'}) dod=$(if($verify){$verify.dod_met}else{'?'}) size=$sizeLines sensitive=[$($sensitive -join ',')]"
Write-Host "  risk=$risk; autonomy=$autonomy"

# ---------- 7) РЕШЕНИЕ: auto-land vs DEC ----------
$decision = [ordered]@{ repo = $repo; workspace = $ws; change = $change; risk = $risk; reasons = $reasons; integration = $integrationNote }
if ($riskLow -and $autonomy -eq 'auto-low') {
  $r = Invoke-Land $repoPath $change $Remote
  $decision.action = 'auto-landed'; $decision.main_at_remote = $r.main_at_remote
  Write-Host ""
  Write-Host "  ✅ AUTO-LAND: main→$change, push в '$Remote'. main@$Remote = $($r.main_at_remote)"
  $decision | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RunDir 'land-result.json')
}
else {
  # ---- DEC человеку (§11.7); workspace оставляем для решения ----
  $decId = Next-DecId
  $slug = ($repo -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLower(); if ($slug.Length -gt 24) { $slug = $slug.Substring(0, 24) }
  $decFile = Join-Path $DecDir "$decId-land-$slug.md"
  $reasonList = if ($reasons.Count) { ($reasons | ForEach-Object { "- $_" }) -join "`n" } else { '- (риск low, но autonomy ≠ auto-low — приземление требует твоего согласия)' }
  $findingsList = if ($verify -and @($verify.findings).Count) { (@($verify.findings) | ForEach-Object { "- [$($_.sev)] $($_.msg)" }) -join "`n" } else { '- (нет замечаний Верификатора)' }
  $tick = [char]96
  $changedFilesMd = if ($changedFiles.Count) { ($changedFiles | ForEach-Object { "- $tick$_$tick" }) -join "`n" } else { '- (нет файлов)' }
  $verifyVerdict = if ($verify) { $verify.verdict } else { 'ОШИБКА' }
  $recommended = if ($riskLow) { 'A' } else { 'null' }
  $dec = @"
---
id: $decId
type: decision
title: Приземлять ли изменение в $repo ($change)?
date: $(Get-Date -Format yyyy-MM-dd)
from: orchestrator/land.ps1
priority: P1
status: open
blocks: []
from-thread: null
land-repo: $repo
land-workspace: $ws
land-dest: $dest
land-change: $change
land-remote: $Remote
land-risk: $risk
consumed-at: null
options:
  - id: A
    label: land — приземлить (advance main + push)
  - id: B
    label: abandon — откатить (forget workspace, без land)
recommended: $recommended

# ↓↓↓ ЗАПОЛНЯЕТ ЧЕЛОВЕК. Авторитетный ответ — здесь. ↓↓↓
answer:
  decision: null        # A | B | other
  note: null
  by: anton
  date: null
# и переключи status: open → answered, затем: land.ps1 -Resume $decId
---

## Контекст
Оркестратор исполнил задачу в изолированной workspace ``$ws`` (репо **$repo**), прогнал гейт и
Верификатор. Авто-приземление НЕ выполнено: ``risk=$risk``, ``autonomy=$autonomy``.

**Изменение** ``$change``; build/test = ``$buildOk``/``$testOk``; объём = ``$sizeLines`` строк.
Изменённые файлы:
$changedFilesMd

## Почему не приземлено автоматически
$reasonList

## Замечания Верификатора ($verifyVerdict)
$findingsList

## Что делать
- Проверь diff: ``cd "$dest"; jj diff``
- **A (land):** ответь ``decision: A`` + ``status: answered`` → затем ``pwsh land.ps1 -Resume $decId``
- **B (abandon):** ответь ``decision: B`` + ``status: answered`` → затем ``pwsh land.ps1 -Resume $decId``
"@
  New-Item -ItemType Directory -Force $DecDir | Out-Null
  Set-Content $decFile $dec
  $decision.action = 'escalated'; $decision.dec = $decId; $decision.dec_file = $decFile
  $decision | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $RunDir 'land-result.json')

  # индекс INBOX (источник правды — сам DEC; здесь только строка)
  if (Test-Path $Inbox) {
    $line = "| $decId | P1 | Land $repo ($change)? | — | ``human/decisions/$(Split-Path $decFile -Leaf)`` |"
    $ib = @(Get-Content $Inbox)
    if (($ib -join "`n") -notmatch [regex]::Escape($decId)) {
      $phRx = '^\|\s*_пока нет_\s*\|\s*\|\s*\|\s*\|\s*\|[ \t]*$'   # DEC-плейсхолдер = ровно 5 ячеек
      $hasPh = [bool]($ib | Where-Object { $_ -match $phRx })
      $out = @(); $placed = $false
      foreach ($l in $ib) {
        if (-not $placed -and $hasPh -and $l -match $phRx) { $out += $line; $placed = $true; continue }  # заменить плейсхолдер
        $out += $l
        if (-not $placed -and -not $hasPh -and $l -match '^\|----\|-----------\|--------\|-----------\|------\|[ \t]*$') { $out += $line; $placed = $true }  # вставить после шапки DEC
      }
      if (-not $placed) { $out += @('', $line) }
      Set-Content $Inbox $out
    }
  }
  Write-Host ""
  Write-Host "  🟥 DEC $decId заведён → $decFile (land НЕ выполнен; ws сохранена)."
}
Write-Host "Артефакты: $RunDir (verify.json, land-result.json, land-*.log)"
