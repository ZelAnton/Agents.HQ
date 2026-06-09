#requires -Version 7
<#
.SYNOPSIS
  Устанавливает skill /comms из ИСТОЧНИКА ПРАВДЫ (.hq/orchestrator/skills/comms/SKILL.md)
  в .claude/skills/comms/ (каталог, который обнаруживает Claude Code при cwd = d:/GitHub/Personal).
  Запускать после правок SKILL.md в .hq, иначе install-копия устареет (L1 из ревью 2026-06-09).
#>
$ErrorActionPreference = 'Stop'
$src = (Resolve-Path (Join-Path $PSScriptRoot '../skills/comms/SKILL.md')).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path   # d:/GitHub/Personal
$dstDir = Join-Path $repoRoot '.claude/skills/comms'
New-Item -ItemType Directory -Force $dstDir | Out-Null
$dst = Join-Path $dstDir 'SKILL.md'
Copy-Item $src $dst -Force
$match = (Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash
Write-Host "source : $src"
Write-Host "install: $dst"
Write-Host "hash match: $match"
if (-not $match) { throw 'install-копия не совпала с источником' }
