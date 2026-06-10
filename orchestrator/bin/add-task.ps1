#!/usr/bin/env pwsh
# add-task.ps1 — headless: добавить задачу в очередь intake
# Использование: add-task.ps1 -Title "…" [-Body "…"] [-Priority P2] [-Scope cross] [-Repos "a,b"]
# Эквивалент skill /add-task (без интерактивного LLM).

param(
    [Parameter(Mandatory)] [string]$Title,
    [string]$Body = "",
    [ValidateSet("P0","P1","P2")] [string]$Priority = "P2",
    [string]$Scope = "cross",
    [string]$Repos = "orchestrator"   # comma-separated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$HQ = Split-Path $PSScriptRoot -Parent | Split-Path -Parent   # .hq/
$LockFile = Join-Path $HQ "orchestrator\.lock"
$QueueFile = Join-Path $HQ "tasks\QUEUE.md"
$TaskDir = Join-Path $HQ "orchestrator\tasks"

# ---------- Locking (та же конвенция, что comms.ps1: Test-Path + PID/TTL) ----------

function Enter-Lock {
    if (Test-Path $LockFile) {
        $raw = Get-Content $LockFile -Raw -ErrorAction SilentlyContinue
        if ($raw -match '^(\d+)\t(.+)$') {
            $pid_ = [int]$Matches[1]; $ts = $Matches[2].Trim()
            $parsed = [datetime]::Parse($ts, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $age = (Get-Date) - $parsed
            $alive = $null -ne (Get-Process -Id $pid_ -ErrorAction SilentlyContinue)
            if ($alive -and $age.TotalMinutes -lt 30) {
                Write-Error "Лок активен (PID=$pid_, возраст=$([int]$age.TotalMinutes)м). Попробуй позже."
            }
        }
    }
    "$PID`t$(Get-Date -Format 'o')" | Set-Content -Path $LockFile -Encoding utf8 -NoNewline
}

function Exit-Lock {
    if (Test-Path $LockFile) {
        $raw = Get-Content $LockFile -Raw -ErrorAction SilentlyContinue
        if ($raw -match "^$PID\t") { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue }
    }
}

# ---------- Leak scan ----------

function Test-Leaks([string]$text) {
    $patterns = @('[A-Za-z]:[/\\](GitHub|Users)', '/Users/', 'ghp_[A-Za-z0-9]+', 'AKIA[A-Z0-9]{16}', 'BEGIN .* PRIVATE KEY')
    foreach ($p in $patterns) { if ($text -match $p) { return $true } }
    return $false
}

# ---------- ASCII slug (транслит кириллицы; конвенция репо — ASCII-имена спек) ----------

function ConvertTo-AsciiSlug([string]$text) {
    $map = @{
        'а'='a';'б'='b';'в'='v';'г'='g';'д'='d';'е'='e';'ё'='e';'ж'='zh';'з'='z';'и'='i'
        'й'='y';'к'='k';'л'='l';'м'='m';'н'='n';'о'='o';'п'='p';'р'='r';'с'='s';'т'='t'
        'у'='u';'ф'='f';'х'='h';'ц'='ts';'ч'='ch';'ш'='sh';'щ'='sch';'ъ'='';'ы'='y';'ь'=''
        'э'='e';'ю'='yu';'я'='ya'
    }
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $text.ToLower().ToCharArray()) {
        $s = [string]$ch
        if ($map.ContainsKey($s)) { [void]$sb.Append($map[$s]) }
        elseif ($s -match '[a-z0-9]') { [void]$sb.Append($s) }
        else { [void]$sb.Append('-') }
    }
    $slug = $sb.ToString() -replace '-+', '-' -replace '^-|-$', ''
    if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).TrimEnd('-') }
    if (-not $slug) { $slug = 'task' }
    return $slug
}

# ---------- Main ----------

Enter-Lock
try {
    # Санитизация Title: убрать переводы строк (иначе ломают YAML-скаляр frontmatter)
    $Title = ($Title -replace '[\r\n]+', ' ').Trim()
    if (-not $Title) { Write-Error "Пустой Title после нормализации." }

    # Leak scan
    if ((Test-Leaks $Title) -or (Test-Leaks $Body)) {
        Write-Error "Текст задачи содержит потенциальные утечки (пути/токены). Отредактируй и повтори."
    }

    # Dedup по названию среди существующих intake-задач (правило идемпотентности из SKILL.md)
    $dup = Get-ChildItem (Join-Path $TaskDir '*.md') -ErrorAction SilentlyContinue | ForEach-Object {
        $fm = Get-Content $_.FullName -TotalCount 25
        $titleLine  = $fm | Where-Object { $_ -match '^title:\s*(.+)$' } | Select-Object -First 1
        $statusLine = $fm | Where-Object { $_ -match '^status:\s*(.+)$' } | Select-Object -First 1
        if ($titleLine -and $statusLine) {
            $t = ($titleLine -replace '^title:\s*', '').Trim()
            $s = ($statusLine -replace '^status:\s*', '').Trim()
            if ($t -eq $Title -and $s -eq 'intake') { $_.Name }
        }
    } | Select-Object -First 1
    if ($dup) {
        Write-Warning "Задача с таким названием уже в intake ($dup) — дубль не создаём."
        exit 0
    }

    # Next TASK-#### ID: max из ОБОИХ источников (QUEUE.md + спеки в TaskDir),
    # иначе осиротевшая спека (без строки в QUEUE) приведёт к переиспользованию ID.
    $content = Get-Content $QueueFile -Raw
    $queueIds = [regex]::Matches($content, 'TASK-(\d{4})') | ForEach-Object { [int]$_.Groups[1].Value }
    $specIds = Get-ChildItem (Join-Path $TaskDir 'TASK-*.md') -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match 'TASK-(\d{4})') { [int]$Matches[1] }
    }
    $allIds = @($queueIds) + @($specIds)
    $nextNum = if ($allIds.Count -gt 0) { [int](($allIds | Measure-Object -Maximum).Maximum) + 1 } else { 1 }
    $taskId = "TASK-{0:D4}" -f $nextNum

    # ASCII-slug
    $slug = ConvertTo-AsciiSlug $Title
    $fileName = "$taskId-$slug.md"
    $specPath = Join-Path $TaskDir $fileName
    $specRelPath = "../orchestrator/tasks/$fileName"

    # repos: единый формат для frontmatter и строки QUEUE
    $reposDisplay = (($Repos -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ', '
    $reposList = "[$reposDisplay]"

    # Build QUEUE content FIRST — валидируем шапку ДО записи спеки (H3: без шапки спеку не пишем)
    $today = Get-Date -Format 'yyyy-MM-dd'
    $queueRow = "| $taskId | $Scope | $Priority | intake | $reposDisplay | — | — | ``$specRelPath`` |"
    $insertAfter = "|----|-------|-----------|--------|-------|------------|--------------------|-------|"
    if (-not $content.Contains($insertAfter)) {
        Write-Error "Не найдена шапка таблицы «Активные задачи» в QUEUE.md — задача не создана."
    }
    $newQueue = $content -replace 'Обновлено: \d{4}-\d{2}-\d{2}.*', "Обновлено: $today (intake $taskId)"
    $newQueue = $newQueue.Replace($insertAfter, "$insertAfter`n$queueRow")

    # Task spec
    $bodySection = if ($Body) { $Body } else { $Title }
    $specContent = @"
---
id: $taskId
type: task
title: $Title
date: $today
scope: $Scope
status: intake
priority: $Priority
repos: $reposList
depends-on: []
parallel-safe-with: []
assigned-to: null
origin: human
created-by: human
risk: null
fix-attempt: 0
session: null
blocked-reason: null
review: null
---

## Цель
$bodySection

## Объём по репозиториям
(ожидает планировщика — запусти /comms)

## Критерии готовности (DoD)
- [ ] (ожидает планировщика)

## Риски / зависимости
(ожидает планировщика)
"@

    # Write spec (atomic via tmp), затем QUEUE; при сбое QUEUE — откатываем спеку (H3)
    $tmpSpec = "$specPath.tmp"
    $specContent | Set-Content -Path $tmpSpec -Encoding utf8
    Move-Item $tmpSpec $specPath -Force
    try {
        $tmpQueue = "$QueueFile.tmp"
        $newQueue | Set-Content -Path $tmpQueue -Encoding utf8 -NoNewline
        Move-Item $tmpQueue $QueueFile -Force
    } catch {
        Remove-Item $specPath -Force -ErrorAction SilentlyContinue
        throw
    }

    Write-Host "Задача добавлена: $taskId — $Title"
    Write-Host "Статус: intake (ожидает триажа — запусти /comms чтобы спланировать)"
    Write-Host "Спека: .hq/orchestrator/tasks/$fileName"

} finally {
    Exit-Lock
}
