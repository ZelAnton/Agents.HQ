#requires -Version 7
<#
.SYNOPSIS
  Авторитетный (детерминированный) расчёт parallel-safe ВОЛН для набора задач ОДНОГО репо (фаза P5).
  Внутри волны задачи взаимно непересекающиеся (можно параллельно); пересечение по `scope_paths`,
  касание общего/моноширинного файла или `restructures` ⇒ задача сериализуется в отдельную волну (§11.6).
  Авторитет — Дирижёр (этот скрипт), а НЕ planner: `parallel_safe_with` — лишь подсказка (AND, не расширяет).
.OUTPUT
  JSON в stdout (и в -Out, если задан): { repo, shared_files_used, waves:[[task_path,...]], wave_ids:[[id,...]], rationale:[...] }
.EXAMPLE
  ./plan-waves.ps1 -Tasks ../_fixtures/sample-intra-disjoint-a.md,../_fixtures/sample-intra-disjoint-b.md
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$Tasks,
  [string]$Repo,
  [string]$Out
)
$ErrorActionPreference = 'Stop'
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ = Split-Path $Orch -Parent
# pwsh -File не разбивает массив по запятой → элемент может быть "a,b"; нормализуем сами
$Tasks = @($Tasks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Get-Fm([string]$text, [string]$key) {
  if ($text -match "(?m)^${key}:\s*\[([^\]]*)\]") { return @($Matches[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
  if ($text -match "(?m)^${key}:\s*(.+)$") { return @($Matches[1].Trim()) }
  return @()
}
function Fm1([string]$t, [string]$k) { $a = @(Get-Fm $t $k); if ($a.Count) { $a[0] } else { $null } }
function Norm([string]$p) { ($p -replace '\\', '/').Trim().TrimEnd('/').ToLower() }

# встроенный список общих/моноширинных файлов (касание ⇒ сериализация); + card.md shared_files
$SharedRx = @(
  '(^|/)cargo\.toml$', '(^|/)cargo\.lock$', '(^|/)lib\.rs$', '(^|/)mod\.rs$', '(^|/)main\.rs$',
  '(^|/)changelog\.md$', '\.(csproj|fsproj|vbproj|sln|props|targets)$',
  '(^|/)package\.json$', '(^|/)go\.mod$', '(^|/)pyproject\.toml$', '(^|/)build\.gradle', '(^|/)pom\.xml$'
)
$cardShared = @()
if ($Repo) {
  $card = Join-Path $HQ "projects/$Repo/card.md"
  if (Test-Path $card) { $cardShared = @(Get-Fm (Get-Content -Raw $card) 'shared_files' | ForEach-Object { Norm $_ }) }
}
function Is-Shared([string]$path) {
  $n = Norm $path
  foreach ($rx in $SharedRx) { if ($n -match $rx) { return $true } }
  foreach ($s in $cardShared) { if ($s -and ($n -eq $s -or $n.EndsWith("/$s") -or $n -match [regex]::Escape($s))) { return $true } }
  return $false
}
# пересечение областей: равны, или одна — каталог-предок другой (файловая+директорная гранулярность)
function Paths-Overlap([string[]]$a, [string[]]$b) {
  foreach ($x in $a) { $nx = Norm $x; foreach ($y in $b) { $ny = Norm $y
      if ($nx -eq $ny -or $nx.StartsWith("$ny/") -or $ny.StartsWith("$nx/")) { return $true } } }
  return $false
}

# ---- прочитать задачи ----
$items = @()
foreach ($t in $Tasks) {
  $tp = (Resolve-Path $t).Path
  $txt = Get-Content -Raw $tp
  $id = Fm1 $txt 'id'; if (-not $id) { $id = [IO.Path]::GetFileNameWithoutExtension($tp) }
  $repo = Fm1 $txt 'repo'; if (-not $repo) { $repo = Fm1 $txt 'scope' }
  $scope = @(Get-Fm $txt 'scope_paths')
  $restr = ((Fm1 $txt 'restructures') -in @('true', 'True', 'yes'))
  $psafe = @(Get-Fm $txt 'parallel_safe_with')
  $items += [pscustomobject]@{ id = $id; path = $tp; repo = $repo; scope = $scope; shared = [bool](@($scope | Where-Object { Is-Shared $_ }).Count); restructures = $restr; psafe = $psafe; emptyScope = (-not $scope.Count) }
}
$repos = @($items.repo | Sort-Object -Unique)
if ($repos.Count -gt 1) { Write-Host "ВНИМАНИЕ: plan-waves рассчитан на ОДИН репо, получено: $($repos -join ', ') (кросс-репо параллель — P3/tick.ps1)." }
if (-not $Repo -and $repos.Count -eq 1) { $Repo = $repos[0] }

# ---- граф конфликтов (true ⇒ нельзя в одну волну) ----
$rationale = @()
# Чистая функция: только вычисляет конфликт пары (planner_safe_with НЕ расширяет параллелизм — §11.6).
function Conflicts($a, $b) {
  if ($a.shared -or $b.shared) { return @{ c = $true; why = "общий/моноширинный файл ($($a.id)↔$($b.id)) ⇒ сериализация" } }
  if ($a.restructures -or $b.restructures) { return @{ c = $true; why = "restructures ($($a.id)↔$($b.id)) ⇒ отдельная волна" } }
  if ($a.emptyScope -or $b.emptyScope) { return @{ c = $true; why = "пустой scope_paths ($($a.id)↔$($b.id)) ⇒ сериализация (fail-closed)" } }
  if (Paths-Overlap $a.scope $b.scope) { return @{ c = $true; why = "пересечение scope_paths ($($a.id)↔$($b.id)) ⇒ сериализация" } }
  return @{ c = $false; why = $null }
}

# ---- жадная раскраска в волны: задача в первую волну, где нет конфликта ----
$waves = @()
foreach ($it in $items) {
  $placed = $false
  for ($w = 0; $w -lt $waves.Count; $w++) {
    $bad = $false
    foreach ($other in $waves[$w]) { $r = Conflicts $it $other; if ($r.c) { $bad = $true; if ($r.why) { $rationale += $r.why }; break } }
    if (-not $bad) { $waves[$w] += $it; $placed = $true; break }
  }
  if (-not $placed) { $waves += , @($it) }
}

$result = [ordered]@{
  repo               = $Repo
  shared_files_used  = @($SharedRx + $cardShared)
  waves              = @($waves | ForEach-Object { , @($_.path) })
  wave_ids           = @($waves | ForEach-Object { , @($_.id) })
  rationale          = @($rationale | Select-Object -Unique)
}
$json = $result | ConvertTo-Json -Depth 8
if ($Out) { $json | Set-Content $Out }
# человекочитаемая сводка в stderr-подобный канал (Host), JSON — в stdout (pipe-friendly)
Write-Host "=== plan-waves: repo=$Repo, задач=$($items.Count), волн=$($waves.Count) ===" -ForegroundColor Cyan
for ($i = 0; $i -lt $waves.Count; $i++) { Write-Host ("  волна {0}: {1}" -f ($i + 1), (@($waves[$i].id) -join ', ')) }
if ($result.rationale.Count) { Write-Host "  rationale:"; $result.rationale | ForEach-Object { Write-Host "    - $_" } }
$json
