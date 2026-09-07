#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ConfigPath, [switch]$CheckOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Desktop-LocalFiles.ps1')
if (-not $CheckOnly) { Assert-DesktopStopped }
$config = & (Join-Path $PSScriptRoot 'Initialize-AdapterConfiguration.ps1') -ConfigPath $ConfigPath -CheckOnly:$CheckOnly
$profiles = & (Join-Path $PSScriptRoot 'Install-DesktopProfileHook.ps1') -CheckOnly:$CheckOnly
[pscustomobject]@{configuration=$config;profiles=$profiles;systemSshChanged=$false;sshConfigurationChanged=$false;globalPathChanged=$false;desktopStarted=$false}
