#requires -Version 7
<#
.SYNOPSIS
  Создать безопасный scratch-полигон для валидации auto-land (P4): jj-репо + ЛОКАЛЬНЫЙ bare-remote.
  Никакой сети и никаких продуктовых репозиториев. Каталоги — siblings под Personal (вне .hq),
  поэтому в Agents.HQ не коммитятся. Печатает JSON с путями (repo/remote/url) в stdout.
.EXAMPLE
  ./make-scratch-repo.ps1                 # .hq-scratch-p4-<rand> + .remote.git
  ./make-scratch-repo.ps1 -Name demo -Force
  ./make-scratch-repo.ps1 -Remove -Name demo   # снести полигон
#>
[CmdletBinding()]
param(
  [string]$Name,
  [switch]$Force,
  [switch]$Remove,
  [switch]$Modules   # P5: добавить src/{alpha,beta,shared}.rs для непересекающихся/пересекающихся областей
)
$ErrorActionPreference = 'Stop'
$Bin = $PSScriptRoot
$Orch = Split-Path $Bin -Parent
$HQ = Split-Path $Orch -Parent
$Personal = Split-Path $HQ -Parent

if (-not $Name) {
  if ($Remove) { throw "-Remove требует -Name" }
  $Name = "p4-" + ([guid]::NewGuid().ToString('N').Substring(0, 8))
}
$repoName = ".hq-scratch-$Name"
$repoPath = Join-Path $Personal $repoName
$remotePath = Join-Path $Personal "$repoName.remote.git"
$remoteUrl = "file:///" + ($remotePath -replace '\\', '/')

if ($Remove) {
  # снести соответствующие worktrees, затем сам репо и remote
  $wt = Join-Path $Personal ".hq-worktrees/$repoName"
  if (Test-Path $wt) { Remove-Item -Recurse -Force $wt }
  if (Test-Path $repoPath) { Remove-Item -Recurse -Force $repoPath }
  if (Test-Path $remotePath) { Remove-Item -Recurse -Force $remotePath }
  Write-Host "scratch '$repoName' снесён (repo+remote+worktrees)."
  return
}

if (Test-Path $repoPath) { if ($Force) { Remove-Item -Recurse -Force $repoPath } else { throw "уже есть: $repoPath (используй -Force)" } }
if (Test-Path $remotePath) { if ($Force) { Remove-Item -Recurse -Force $remotePath } else { throw "уже есть: $remotePath (используй -Force)" } }

New-Item -ItemType Directory -Force $repoPath | Out-Null
New-Item -ItemType Directory -Force $remotePath | Out-Null

# 1) локальный bare remote (только файловая система, без сети)
Push-Location $remotePath
try { git init --bare --initial-branch=main 2>&1 | Out-Null } finally { Pop-Location }

# 2) минимальный Rust-проект: build/test за секунды
Push-Location $repoPath
try {
  cargo init --lib --name hq_scratch --vcs none 2>&1 | Out-Null
  # .gitignore ДО первого снапшота: иначе jj затащит target/ (build-артефакты с абсолютными путями)
  Set-Content (Join-Path $repoPath '.gitignore') "/target`n/Cargo.lock`n"

  if ($Modules) {
    $src = Join-Path $repoPath 'src'
    Set-Content (Join-Path $src 'lib.rs') @"
pub mod alpha;
pub mod beta;
pub mod shared;

pub fn add(left: u64, right: u64) -> u64 { left + right }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn it_works() { assert_eq!(add(2, 2), 4); }
}
"@
    Set-Content (Join-Path $src 'alpha.rs') @"
pub fn alpha_base() -> i32 { 0 }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn base() { assert_eq!(alpha_base(), 0); }
}
"@
    Set-Content (Join-Path $src 'beta.rs') @"
pub fn beta_base() -> i32 { 0 }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn base() { assert_eq!(beta_base(), 0); }
}
"@
    Set-Content (Join-Path $src 'shared.rs') @"
pub fn tag() -> &'static str { "shared" }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tag_works() { assert_eq!(tag(), "shared"); }
}
"@
  }

  # 3) jj-репо поверх + начальный коммит main + remote + push
  jj git init 2>&1 | Out-Null
  jj describe -m "scratch baseline (cargo lib)" 2>&1 | Out-Null
  jj bookmark create main -r '@' 2>&1 | Out-Null
  jj new 2>&1 | Out-Null                       # @ уходит вперёд: main = чистый landable baseline
  jj git remote add origin $remoteUrl 2>&1 | Out-Null
  jj git push --remote origin --bookmark main --allow-new 2>&1 | Out-Null
} finally { Pop-Location }

# 4) проверка: baseline main виден на remote
Push-Location $repoPath
try { $atOrigin = (jj log --no-pager -r 'main@origin' --no-graph -T 'change_id.short() ++ " " ++ description.first_line()' 2>&1 | Out-String).Trim() } finally { Pop-Location }

$out = [ordered]@{
  repo        = $repoName            # значение для frontmatter `repo:` в задаче
  repo_path   = $repoPath
  remote_path = $remotePath
  remote_url  = $remoteUrl
  main_at_origin = $atOrigin
}
$out | ConvertTo-Json -Depth 5
