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
$TemplatePath = Join-Path $HQ "_templates\task.md"

# ---------- Locking ----------

function Enter-Lock {
    if (Test-Path $LockFile) {
        $raw = Get-Content $LockFile -Raw -ErrorAction SilentlyContinue
        if ($raw -match '^(\d+)\t(.+)$') {
            $pid_ = [int]$Matches[1]; $ts = $Matches[2].Trim()
            $age = (Get-Date) - [datetime]::Parse($ts)
            $alive = (Get-Process -Id $pid_ -ErrorAction SilentlyContinue) -ne $null
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

# ---------- Main ----------

Enter-Lock
try {
    # Leak scan
    if ((Test-Leaks $Title) -or (Test-Leaks $Body)) {
        Write-Error "Текст задачи содержит потенциальные утечки (пути/токены). Отредактируй и повтори."
    }

    # Next TASK-#### ID
    $content = Get-Content $QueueFile -Raw
    $ids = [regex]::Matches($content, 'TASK-(\d{4})') | ForEach-Object { [int]$_.Groups[1].Value }
    $nextNum = if ($ids.Count -gt 0) { [int](($ids | Measure-Object -Maximum).Maximum) + 1 } else { 1 }
    $taskId = "TASK-{0:D4}" -f $nextNum

    # Slug
    $slug = $Title.ToLower() -replace '[^a-z0-9а-яёА-ЯЁ]+', '-' -replace '^-|-$', ''
    $slug = $slug.Substring(0, [Math]::Min(40, $slug.Length)).TrimEnd('-')
    $fileName = "$taskId-$slug.md"
    $specPath = Join-Path $TaskDir $fileName
    $specRelPath = "../orchestrator/tasks/$fileName"

    # Duplicate check
    if (Get-Content $QueueFile -Raw | Select-String $taskId) {
        Write-Warning "$taskId уже в QUEUE.md — не добавляем дублей."
        exit 0
    }

    # Build repos array string
    $reposList = "[" + ($Repos -split ',' | ForEach-Object { $_.Trim() } | ForEach-Object { "$_" } | Join-String -Separator ', ') + "]"

    # Task spec body
    $today = Get-Date -Format 'yyyy-MM-dd'
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

    # Write spec (atomic via tmp)
    $tmpSpec = "$specPath.tmp"
    $specContent | Set-Content -Path $tmpSpec -Encoding utf8
    Move-Item $tmpSpec $specPath -Force

    # Add row to QUEUE.md
    $queueRow = "| $taskId | $Scope | $Priority | intake | $Repos | — | — | ``$specRelPath`` |"

    $queueContent = Get-Content $QueueFile -Raw
    # Update date header
    $queueContent = $queueContent -replace 'Обновлено: \d{4}-\d{2}-\d{2}', "Обновлено: $today"

    # Insert after header row of "Активные задачи" table
    $insertAfter = "|----|-------|-----------|--------|-------|------------|--------------------|-------|"
    if ($queueContent -notcontains $queueRow) {
        $queueContent = $queueContent -replace [regex]::Escape($insertAfter), "$insertAfter`n$queueRow"
    }

    $tmpQueue = "$QueueFile.tmp"
    $queueContent | Set-Content -Path $tmpQueue -Encoding utf8 -NoNewline
    Move-Item $tmpQueue $QueueFile -Force

    Write-Host "Задача добавлена: $taskId — $Title"
    Write-Host "Статус: intake (ожидает триажа — запусти /comms чтобы спланировать)"
    Write-Host "Спека: .hq/orchestrator/tasks/$fileName"

} finally {
    Exit-Lock
}
