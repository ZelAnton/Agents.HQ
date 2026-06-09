#requires -Version 7
<#
.SYNOPSIS
  Headless-Дирижёр оркестра .hq (фаза P1): триаж входящего + планирование задач.
  Эквивалент интерактивного skill /comms. Сам код не пишет; зовёт claude -p на спецах агентов
  со структурным выводом (--json-schema). По умолчанию propose-only (пишет ТОЛЬКО в _runs/<run_id>/,
  реальные comms/QUEUE не мутирует). --Apply применяет реально (с гейтом утечек). Тред из skip-list
  всегда пропускается. Детерминированная логика (lock, нумерация TASK-####, валидация графа) — здесь,
  а не в LLM.

.EXAMPLE
  ./comms.ps1 -Fixture ../_fixtures/sample-inbound     # валидация на фикстуре (propose-only)
  ./comms.ps1                                           # propose по реальному входящему
  ./comms.ps1 -Apply                                    # применить (ответы в треды + QUEUE + спеки)
#>
[CmdletBinding()]
param(
  [string]$Fixture,                 # каталог-фикстура (thread.md + сообщения)
  [switch]$Apply,                   # реально применить (иначе propose-only в _runs/)
  [switch]$Force,                   # игнорировать last-triaged-seq (переобработать)
  [string]$Only,                    # обработать только один thread-id
  [string]$Model = 'sonnet',        # модель субагентов
  [int]$LockTtlMin = 30
)

$ErrorActionPreference = 'Stop'
$SkipList = @('T-20260609-vcs-processkit-feedback')

# --- пути (от расположения скрипта; без захардкоженных абсолютов) ---
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent           # .hq/orchestrator
$HQ   = Split-Path $Orch -Parent          # .hq
$Agents  = Join-Path $Orch 'agents'
$Schemas = Join-Path $Orch 'schemas'
$StateDir = Join-Path $Orch '_state'
$ProcessedFile = Join-Path $StateDir 'processed.json'
$LockFile = Join-Path $Orch '.lock'
$Mode = if ($Fixture) { 'fixture' } elseif ($Apply) { 'live' } else { 'dry-run' }
$RunId = ($(if ($Fixture) { 'fixture-' } else { '' })) + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID"
$RunDir = Join-Path $Orch "_runs/$RunId"

# --- лок (M5): единственный активный тик, до любого скана/записи ---
function Enter-Lock {
  $attempt = 0
  while ($true) {
    try {
      $fs = [System.IO.File]::Open($LockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
      $sw = New-Object System.IO.StreamWriter($fs)
      $sw.WriteLine("$PID`t$(Get-Date -Format o)`t$([Environment]::MachineName)")
      $sw.Flush(); $sw.Dispose(); $fs.Dispose(); return
    } catch {
      if ($attempt -ge 1) { throw "Активен другой тик (lock: $LockFile). Подожди или сними вручную." }
      $attempt++
      $stale = $true; $alive = $false
      try {
        $parts = (Get-Content -Raw $LockFile -ErrorAction Stop) -split "`t"
        $stale = ((Get-Date) - [datetime]$parts[1]).TotalMinutes -gt $LockTtlMin
        $alive = [bool](Get-Process -Id ([int]$parts[0]) -ErrorAction SilentlyContinue)
      } catch { $stale = $true }
      if ($stale -or -not $alive) { Remove-Item -Force $LockFile -ErrorAction SilentlyContinue; continue }
      throw "Активен другой тик (lock: $LockFile, pid=$($parts[0])). Подожди или сними вручную."
    }
  }
}
function Exit-Lock { Remove-Item -Force $LockFile -ErrorAction SilentlyContinue }

# --- скан утечек (M11): локальные пути/секреты не должны уезжать в публичный .hq ---
$LeakPatterns = @(
  @{ n = 'local-path'; rx = '[A-Za-z]:[\\/](?:GitHub|Users)' },
  @{ n = 'unix-home'; rx = '/(?:GitHub|Users)/' },
  @{ n = 'github-pat'; rx = 'ghp_[A-Za-z0-9]{20,}' },
  @{ n = 'slack-token'; rx = 'xox[baprs]-' },
  @{ n = 'aws-key'; rx = 'AKIA[0-9A-Z]{16}' },
  @{ n = 'private-key'; rx = 'BEGIN [A-Z ]*PRIVATE KEY' }
)
function Find-Leaks([string]$text) {
  $hits = @(); foreach ($p in $LeakPatterns) { if ($text -match $p.rx) { $hits += $p.n } }; return $hits
}

# --- вызов специалиста через claude -p (M3: раздельный stderr, робастный JSON; M4: retry) ---
function Invoke-Specialist {
  param([string]$SpecFile, [string]$SchemaFile, [string]$InputText, [int]$Retries = 1)
  $schema = Get-Content -Raw $SchemaFile
  $errFile = [System.IO.Path]::GetTempFileName()
  for ($try = 0; $try -le $Retries; $try++) {
    $extra = if ($try -gt 0) { "`n`nПРЕДЫДУЩИЙ вывод был невалиден. Верни СТРОГО валидный JSON по схеме, без markdown и текста вокруг." } else { '' }
    $out = & claude -p ($InputText + $extra) `
        --append-system-prompt-file $SpecFile `
        --output-format json `
        --json-schema $schema `
        --permission-mode acceptEdits `
        --allowedTools 'Read,Glob,Grep' `
        --add-dir $HQ `
        --model $Model 2>$errFile
    $stdout = ($out | Out-String)
    $env = $null
    try { $env = $stdout | ConvertFrom-Json } catch {
      # робастно: вырезать от первой { до последней }
      $a = $stdout.IndexOf('{'); $b = $stdout.LastIndexOf('}')
      if ($a -ge 0 -and $b -gt $a) { try { $env = $stdout.Substring($a, $b - $a + 1) | ConvertFrom-Json } catch {} }
    }
    if ($env) {
      if ($env.structured_output) { Remove-Item $errFile -ErrorAction SilentlyContinue; return $env.structured_output }
      # ВАЖНО: при сложной схеме claude может вернуть structured_output=null, а валидный JSON положить
      # в .result как ```json-блок. Извлекаем робастно: сначала как есть, потом от первой { до последней }.
      if ($env.result) {
        $r = [string]$env.result; $parsed = $null
        try { $parsed = $r | ConvertFrom-Json } catch {
          $a = $r.IndexOf('{'); $b = $r.LastIndexOf('}')
          if ($a -ge 0 -and $b -gt $a) { try { $parsed = $r.Substring($a, $b - $a + 1) | ConvertFrom-Json } catch {} }
        }
        if ($parsed) { Remove-Item $errFile -ErrorAction SilentlyContinue; return $parsed }
      }
    }
    # не получилось — повтор
  }
  $errTxt = (Get-Content -Raw $errFile -ErrorAction SilentlyContinue)
  Remove-Item $errFile -ErrorAction SilentlyContinue
  throw "claude -p не дал валидный structured_output после $($Retries+1) попыток. stderr: $errTxt"
}

# --- определить адресата (M1): awaiting → scope:single → to → participants ---
function Get-Addressee([string]$threadMd) {
  $awaiting = @()
  if ($threadMd -match '(?m)^awaiting:\s*\[([^\]]*)\]') { $awaiting = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  elseif ($threadMd -match '(?m)^awaiting:\s*([^\[\r\n]+)$') { $awaiting = @($Matches[1].Trim()) }
  $repos = @($awaiting | Where-Object { $_ -and $_ -ne 'human' })
  if ($repos.Count) { return @{ repo = $repos[0]; multi = ($repos.Count -gt 1); others = ($repos | Select-Object -Skip 1) } }
  if ($threadMd -match '(?m)^scope:\s*single:(\S+)') { return @{ repo = $Matches[1]; multi = $false } }
  if ($threadMd -match '(?m)^to:\s*(\S+)') { return @{ repo = $Matches[1]; multi = $false } }
  if ($threadMd -match '(?m)^participants:\s*\[([^\]]*)\]') {
    $p = @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'human' })
    if ($p.Count) { return @{ repo = $p[0]; multi = $false } }
  }
  return @{ repo = $null }
}

# --- валидация графа planner (M4): локальные id, разрешимость, ацикличность, parallel-safe по непересечению ---
function Test-PlanGraph($plan) {
  $errs = @()
  $ids = @($plan.tasks | ForEach-Object { $_.id })
  if (($ids | Select-Object -Unique).Count -ne $ids.Count) { $errs += 'дубли локальных id' }
  $scopeOf = @{}; foreach ($t in $plan.tasks) { $scopeOf[$t.id] = @($t.scope_paths) }
  foreach ($t in $plan.tasks) {
    foreach ($d in @($t.depends_on)) { if ($ids -notcontains $d) { $errs += "$($t.id): depends_on висячая ссылка $d" } }
    foreach ($p in @($t.parallel_safe_with)) {
      if ($ids -notcontains $p) { $errs += "$($t.id): parallel_safe_with висячая ссылка $p"; continue }
      $inter = @($scopeOf[$t.id] | Where-Object { $scopeOf[$p] -contains $_ })
      if ($inter.Count) { $errs += "$($t.id)~${p}: parallel_safe_with при пересечении scope ($($inter -join ','))" }
      if (@($t.depends_on) -contains $p) { $errs += "$($t.id): $p одновременно в depends_on и parallel_safe_with" }
    }
  }
  # ацикличность (DFS)
  $color = @{}; foreach ($i in $ids) { $color[$i] = 0 }
  $cyc = $false
  $depOf = @{}; foreach ($t in $plan.tasks) { $depOf[$t.id] = @($t.depends_on) }
  function _dfs($n) {
    $script:color[$n] = 1
    foreach ($m in $script:depOf[$n]) {
      if ($script:ids -notcontains $m) { continue }
      if ($script:color[$m] -eq 1) { $script:cyc = $true }
      elseif ($script:color[$m] -eq 0) { _dfs $m }
    }
    $script:color[$n] = 2
  }
  $script:color = $color; $script:depOf = $depOf; $script:ids = $ids; $script:cyc = $false
  foreach ($i in $ids) { if ($script:color[$i] -eq 0) { _dfs $i } }
  if ($script:cyc) { $errs += 'цикл в depends_on' }
  return $errs
}

# --- проверка triage-инварианта seed (L6) ---
function Test-TriageInvariant($tri) {
  $errs = @()
  if (@('accept', 'reject', 'clarify', 'escalate') -notcontains $tri.decision) { $errs += "decision вне enum: $($tri.decision)" }
  if ($tri.decision -eq 'accept') {
    if (-not $tri.seed) { $errs += 'accept без seed' }
    elseif (-not $tri.seed.title -or -not $tri.seed.sketch -or -not @($tri.seed.repos).Count) { $errs += 'seed с пустыми полями' }
  } elseif ($tri.seed) { $errs += "не-accept ($($tri.decision)), но seed не null" }
  return $errs
}

# --- собрать входящее (M1: thread.md отдельно; идемпотентность через processed.json) ---
function Get-Processed { if (Test-Path $ProcessedFile) { return (Get-Content -Raw $ProcessedFile | ConvertFrom-Json) } return @{} }
function Get-MaxSeq([string]$dir) {
  $m = -1; Get-ChildItem $dir -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^(\d+)-') { $n = [int]$Matches[1]; if ($n -gt $m) { $m = $n } }
  }; return $m
}
function Get-Inbound {
  if ($Fixture) {
    $f = (Resolve-Path $Fixture).Path
    $tm = Join-Path $f 'thread.md'
    return @([pscustomobject]@{ id = 'T-fixture-sample'; threadMd = (Get-Content -Raw $tm); body = ((Get-ChildItem $f -Filter *.md | Sort-Object Name | Get-Content -Raw) -join "`n---`n") })
  }
  $processed = Get-Processed
  $threads = Get-ChildItem (Join-Path $HQ 'comms/threads') -Directory -ErrorAction SilentlyContinue
  $items = foreach ($th in $threads) {
    if ($SkipList -contains $th.Name) { continue }
    if ($Only -and $th.Name -ne $Only) { continue }
    $tm = Join-Path $th.FullName 'thread.md'
    if (-not (Test-Path $tm)) { continue }
    $tmText = Get-Content -Raw $tm
    if ($tmText -notmatch '(?m)^status:\s*open') { continue }
    $maxSeq = Get-MaxSeq $th.FullName
    $last = if ($processed.PSObject.Properties.Name -contains $th.Name) { [int]$processed.$($th.Name) } else { -1 }
    if (-not $Force -and $maxSeq -le $last) { continue }   # идемпотентность (missing#1)
    [pscustomobject]@{ id = $th.Name; threadMd = $tmText; maxSeq = $maxSeq;
      body = ((Get-ChildItem $th.FullName -Filter *.md | Sort-Object Name | Get-Content -Raw) -join "`n---`n") }
  }
  return @($items)
}

# ======================= main =======================
Enter-Lock
try {
  foreach ($d in 'triage', 'plan', 'proposed-replies', 'proposed-tasks') { New-Item -ItemType Directory -Force (Join-Path $RunDir $d) | Out-Null }
  $tick = [ordered]@{ run_id = $RunId; started = (Get-Date -Format o); mode = $Mode; scanned = @(); skipped = $SkipList; triaged = @(); planned = @(); errors = @(); notes = '' }
  $inbound = Get-Inbound
  $acceptedSeeds = @()   # @{item; seed}

  foreach ($it in $inbound) {
    $tick.scanned += $it.id
    $addr = Get-Addressee $it.threadMd
    if (-not $addr.repo) { $tick.errors += "[$($it.id)] не удалось определить адресата (нет awaiting/scope/to/participants) — пропуск"; continue }
    if (-not (Test-Path (Join-Path $HQ "projects/$($addr.repo)/card.md"))) { $tick.errors += "[$($it.id)] адресат '$($addr.repo)' без карточки — пропуск"; continue }
    if ($addr.multi) { $tick.errors += "[$($it.id)] awaiting содержит несколько репо; primary=$($addr.repo), прочие отложены: $($addr.others -join ',')" }
    $inputText = "Адресат: $($addr.repo)`nПрочитай .hq/projects/$($addr.repo)/card.md и .hq/knowledge/ownership.md.`nВходящее:`n$($it.body)`nВерни ТОЛЬКО JSON по triage.schema.json."
    try {
      $tri = Invoke-Specialist -SpecFile (Join-Path $Agents 'hq-triage.md') -SchemaFile (Join-Path $Schemas 'triage.schema.json') -InputText $inputText
      $inv = Test-TriageInvariant $tri
      if ($inv.Count) { $tick.errors += "[$($it.id)] triage-инвариант: $($inv -join '; ')"; continue }
      $tri | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $RunDir "triage/$($it.id).json")
      if ($tri.reply_md) { $tri.reply_md | Set-Content (Join-Path $RunDir "proposed-replies/$($it.id).md") }
      $tick.triaged += [ordered]@{ item = $it.id; decision = $tri.decision; seed_title = ($tri.seed.title) }
      if ($tri.decision -eq 'accept') { $acceptedSeeds += @{ item = $it.id; seed = $tri.seed } }
    } catch { $tick.errors += "[$($it.id)] triage: $($_.Exception.Message)" }
  }

  # планирование принятого
  $plans = @()   # @{item; plan}
  foreach ($a in $acceptedSeeds) {
    $seedJson = $a.seed | ConvertTo-Json -Depth 12
    $plInput = "seed: $seedJson`nПрочитай карточки затронутых репо и .hq/knowledge/dependency-graph.md. Используй ЛОКАЛЬНЫЕ id T1,T2,... Верни ТОЛЬКО JSON по planner.schema.json."
    try {
      $pl = Invoke-Specialist -SpecFile (Join-Path $Agents 'hq-planner.md') -SchemaFile (Join-Path $Schemas 'planner.schema.json') -InputText $plInput
      $gerr = Test-PlanGraph $pl
      if ($gerr.Count) { $tick.errors += "[$($a.item)] planner-граф: $($gerr -join '; ')"; continue }
      $plans += @{ item = $a.item; plan = $pl }
      $pl | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $RunDir "plan/$($a.item).json")
    } catch { $tick.errors += "[$($a.item)] planner: $($_.Exception.Message)" }
  }

  # детерминированная нумерация TASK-#### (M2, под локом): сквозной счётчик от QUEUE.md
  $next = 1; $q = Join-Path $HQ 'tasks/QUEUE.md'
  if (Test-Path $q) { ([regex]::Matches((Get-Content -Raw $q), 'TASK-(\d{4})')) | ForEach-Object { $n = [int]$_.Groups[1].Value; if ($n -ge $next) { $next = $n + 1 } } }
  $queueRows = @()
  foreach ($pp in $plans) {
    $map = @{}; foreach ($t in $pp.plan.tasks) { $map[$t.id] = ('TASK-{0:D4}' -f $next); $next++ }
    foreach ($t in $pp.plan.tasks) {
      $gid = $map[$t.id]
      $dep = @($t.depends_on | ForEach-Object { $map[$_] })
      $par = @($t.parallel_safe_with | ForEach-Object { $map[$_] })
      # заголовок: предпочесть явный title от planner; иначе — первая содержательная строка spec_md
      $title = $null
      if (($t.PSObject.Properties.Name -contains 'title') -and $t.title) { $title = [string]$t.title }
      if (-not $title) {
        $title = "$($t.repo): $gid"
        foreach ($ln in ($t.spec_md -split "`n")) {
          $l = $ln.Trim()
          if ($l -and $l -notmatch '^#' -and $l -notmatch '^[-*>]') { $title = ($l -replace '[`*_]', ''); if ($title.Length -gt 80) { $title = $title.Substring(0, 80).Trim() }; break }
        }
      }
      $fm = @"
---
id: $gid
type: task
title: $title
date: $(Get-Date -Format yyyy-MM-dd)
scope: $($t.repo)
status: queued
priority: $($t.priority)
repos: [$($t.repo)]
depends-on: [$($dep -join ', ')]
parallel-safe-with: [$($par -join ', ')]
assigned-to: null
origin: $($pp.item)
---

"@
      # скан утечек перед записью текста, сгенерированного LLM (M11)
      $leak = Find-Leaks ($title + "`n" + $t.spec_md)
      if ($leak.Count) { $tick.errors += "[$($pp.item)/$gid] утечка в spec_md: $($leak -join ',') — задача пропущена"; continue }
      ($fm + $t.spec_md) | Set-Content (Join-Path $RunDir "proposed-tasks/$gid.md")
      $queueRows += "| $gid | $($t.repo) | $($t.priority) | queued | $($t.scope_paths -join ' ') | $($dep -join ', ') | $($par -join ', ') |"
      $tick.planned += $gid
    }
  }
  if ($queueRows.Count) {
    @("# Предлагаемые строки QUEUE (run $RunId) — НЕ применено в dry-run/fixture", '',
      '| ID | Scope | Приоритет | Статус | scope_paths | depends-on | parallel-safe-with |',
      '|----|-------|-----------|--------|-------------|------------|--------------------|') + $queueRows |
    Set-Content (Join-Path $RunDir 'proposed-queue-rows.md')
  }

  $tick | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $RunDir 'tick.json')

  # --- применение (--Apply): реальные мутации с гейтом утечек ---
  if ($Apply) {
    $tick.notes = 'apply: пока реализовано propose+журнал; реальная запись в comms/QUEUE — следующий инкремент P1.'
    # NB: запись ответов в треды и строк в QUEUE.md выполняется отдельным проверенным шагом;
    #     здесь оставляем propose-артефакты + обновляем processed.json для идемпотентности.
    if (-not $Fixture) {
      $processed = Get-Processed; $obj = @{}; $processed.PSObject.Properties | ForEach-Object { $obj[$_.Name] = $_.Value }
      foreach ($it in $inbound) { if ($tick.scanned -contains $it.id) { $obj[$it.id] = $it.maxSeq } }
      New-Item -ItemType Directory -Force $StateDir | Out-Null
      $obj | ConvertTo-Json | Set-Content $ProcessedFile
    }
  }

  Write-Host "=== comms run_id=$RunId mode=$Mode ==="
  Write-Host "scanned: $($tick.scanned -join ', ')  | skipped: $($tick.skipped -join ', ')"
  foreach ($t in $tick.triaged) { Write-Host ("  {0} -> {1} {2}" -f $t.item, $t.decision, $t.seed_title) }
  Write-Host "planned: $($tick.planned -join ', ')"
  if ($tick.errors.Count) { Write-Host "ERRORS:`n  $($tick.errors -join "`n  ")" }
  Write-Host "Артефакты: $RunDir  ($(if($Apply){'apply'}else{'propose-only; реальные comms/QUEUE НЕ изменены'}))"
}
finally { Exit-Lock }
