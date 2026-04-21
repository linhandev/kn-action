#Requires -RunAsAdministrator
# GitLab Runner on Windows often runs as NT AUTHORITY\SYSTEM. Git Bash then uses
#   HOME = C:\Windows\System32\config\systemprofile
# Keys must live under that user's .ssh — not only under your login account.
# This copies GitCode SSH identity from a normal user (default: current user) into SYSTEM's profile.
param(
  [string] $SourceUserProfile = $env:USERPROFILE
)
$ErrorActionPreference = 'Stop'
$srcKey = Join-Path $SourceUserProfile '.ssh\id_ed25519'
if (-not (Test-Path -LiteralPath $srcKey)) { throw "Missing $srcKey" }
$dstDir = Join-Path $env:SYSTEMROOT 'System32\config\systemprofile\.ssh'
$dst = Join-Path $dstDir 'id_ed25519'
New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
Copy-Item -Force -LiteralPath $srcKey -Destination $dst
# ssh requires tight ACLs on private keys
& icacls.exe $dst /inheritance:r /grant:r '*S-1-5-18:(R)' | Out-Null
$kh = Join-Path $SourceUserProfile '.ssh\known_hosts'
if (Test-Path -LiteralPath $kh) {
  Copy-Item -Force -LiteralPath $kh -Destination (Join-Path $dstDir 'known_hosts')
}
Write-Output "Installed for SYSTEM: $dst"
