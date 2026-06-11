#requires -Version 7
<#
.SYNOPSIS
  Приземлить одно изменение: jj bookmark move main --to <change>, затем jj git push.
  Изолирует land-операцию от land.ps1 (M3 architecture: Rust owns routing, PS owns jj).
  Без LLM. Без DEC. Вызывается hq-conductor tick только после risk()=low + verify pass.
.EXAMPLE
  ./land-only.ps1 -Repo .hq-scratch-p4-abc123 -Change abc1234567 -Remote origin
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Repo,
  [Parameter(Mandatory)][string]$Change,
  [string]$Remote = 'origin',
  # Optional exec-workspace cleanup after a successful land (M3: «jj workspace list чист после land»).
  # Non-fatal — land уже состоялся; падение forget/remove не откатывает push.
  [string]$Workspace = '',
  [string]$Dest = ''
)
$ErrorActionPreference = 'Stop'
$Bin      = $PSScriptRoot
$Orch     = Split-Path $Bin -Parent
$HQ       = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent

$repoPath = Join-Path $Personal $Repo
if (-not (Test-Path (Join-Path $repoPath '.jj'))) {
  throw "нет jj-репо: $repoPath (Repo=$Repo)"
}

$t0 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Push-Location $repoPath
try {
  # Advance main bookmark to the exec-done change
  $bmOut = jj bookmark move main --to $Change 2>&1
  if ($LASTEXITCODE -ne 0) { throw "jj bookmark move main --to $Change failed (exit=$LASTEXITCODE): $bmOut" }

  # Push main to remote
  $pushOut = jj git push --remote $Remote --bookmark main 2>&1
  if ($LASTEXITCODE -ne 0) { throw "jj git push --remote $Remote --bookmark main failed (exit=$LASTEXITCODE): $pushOut" }

  # Confirm: log where main@remote ended up
  $atRemote = (jj log --no-pager -r "main@$Remote" --no-graph --template 'change_id.short() ++ " " ++ description.first_line()' 2>&1 | Out-String).Trim()

  # Cleanup exec workspace (the change is now on main; the workspace is redundant). Best-effort:
  # forget jj-tracking then remove the working-copy dir. Failures here do NOT fail the land.
  if ($Workspace) {
    $fgOut = jj workspace forget $Workspace 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Warning "land-only: workspace forget '$Workspace' не удался (не критично): $fgOut" }
  }
} finally { Pop-Location }

if ($Dest -and (Test-Path $Dest)) {
  try { Remove-Item -Recurse -Force $Dest } catch { Write-Warning "land-only: не удалось удалить $Dest (не критично): $_" }
}

$ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - $t0
Write-Host "land-only: repo=$Repo change=$Change remote=$Remote ok ($($ms)ms) → main@$Remote=$atRemote"
exit 0
