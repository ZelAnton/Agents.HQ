#requires -Version 7
<#
.SYNOPSIS
  Устанавливает skills из ИСТОЧНИКОВ ПРАВДЫ (.hq/orchestrator/skills/<name>/SKILL.md)
  в .claude/skills/<name>/ (каталог, который обнаруживает Claude Code при cwd = d:/GitHub/Personal).
  Запускать после правок любого SKILL.md в .hq, иначе install-копии устареют.
#>
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path   # d:/GitHub/Personal
$skillsRoot = Join-Path $PSScriptRoot '../skills'

$skills = Get-ChildItem -Path $skillsRoot -Directory | Select-Object -ExpandProperty Name

foreach ($name in $skills) {
    $src = Join-Path $skillsRoot "$name/SKILL.md"
    if (-not (Test-Path $src)) { Write-Warning "Нет $src, пропускаем"; continue }
    $dstDir = Join-Path $repoRoot ".claude/skills/$name"
    New-Item -ItemType Directory -Force $dstDir | Out-Null
    $dst = Join-Path $dstDir 'SKILL.md'
    Copy-Item $src $dst -Force
    $match = (Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash
    Write-Host "[$name] $src → $dst  hash=$match"
    if (-not $match) { throw "install-копия $name не совпала с источником" }
}
