#requires -Version 7
# STUB land worker (M3a plumbing test — no jj/push). Real land-only.ps1 will do
# `jj bookmark move main --to <change>; jj git push`. Stub just succeeds.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Repo,
  [Parameter(Mandatory)][string]$Change,
  [string]$Remote = 'origin'
)
Write-Host "stub land-only: repo=$Repo change=$Change remote=$Remote (no-op, exit 0)"
exit 0
