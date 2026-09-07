#requires -Version 7.0
[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Desktop-LocalFiles.ps1')
. (Join-Path $PSScriptRoot 'Resolve-DesktopInstallation.ps1')
$installation=Resolve-CodexDesktopInstallation
$desktopExe=$installation.desktopExecutable
$adapter=Join-Path $PSScriptRoot 'bin\ssh.exe'; $config=Join-Path $PSScriptRoot 'adapter-config.json'
$activationSource=Join-Path $PSScriptRoot 'src\DesktopPackageActivation.cs'
foreach ($path in @($PSScriptRoot,$adapter,$config,$activationSource,(Join-Path $PSScriptRoot 'Desktop-ShellEnvironment.ps1'))) {
    Assert-DesktopLocalPath $path -MustExist -Owned
    if (-not (Test-DesktopTrustedWriters $path)) { throw 'Adapter files permit untrusted writers; inspect installation permissions.' }
}
$validation=& $adapter --validate-config $config 2>&1
if ($LASTEXITCODE -ne 0 -or [string]$validation -cne 'ADAPTER_CONFIG_VALID') { throw 'Installed configuration failed local validation.' }
$profiles=& (Join-Path $PSScriptRoot 'Install-DesktopProfileHook.ps1') -CheckOnly
$installed=@($profiles.profiles | Where-Object { -not $_.installed }).Count -eq 0
$running=@(Get-Process -Name ChatGPT -ErrorAction SilentlyContinue).Count -gt 0
if ($CheckOnly) {
    [pscustomobject]@{configurationValid=$true;profilesInstalled=$installed;desktopAlreadyRunning=$running;packageVersion=$installation.packageVersion;desktopStarted=$false;remoteAccess=$false}; return
}
if (-not $installed) { throw 'Run Install-Adapter.ps1 with an explicit configuration file first.' }
Assert-DesktopStopped
$directory=Initialize-DesktopStateDirectory $PSScriptRoot
$leasePath=Join-Path $directory 'desktop-environment-lease.json'
$launchId=[guid]::NewGuid().ToString('N'); $requested=[DateTimeOffset]::UtcNow
$lease=[ordered]@{
    version=2; launchId=$launchId; ownerSid=(Get-DesktopUserSid); state='PENDING'
    requestedUtc=$requested.ToString('o'); expiresUtc=$requested.AddSeconds(60).ToString('o')
    expectedDesktopExecutable=$desktopExe; expectedPackageFullName=$installation.packageFullName
    registeredProcessId=0; registeredProcessStartUtc=$null; adapterBin=(Join-Path $PSScriptRoot 'bin')
    adapterSha256=(Get-FileHash -LiteralPath $adapter -Algorithm SHA256).Hash
    configSha256=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
}
try {
    if ($null -eq ('Apocrita.PackageActivation.Desktop' -as [type])) { Add-Type -Path $activationSource }
    Assert-DesktopStopped
    Write-DesktopProtectedJson $leasePath $lease
    $activation=[Apocrita.PackageActivation.Desktop]::Activate()
    if ($activation.HResult -lt 0 -or $activation.ProcessId -eq 0 -or $activation.Executable -ine $desktopExe -or $activation.PackageFullName -cne $installation.packageFullName -or [DateTimeOffset]::Parse($activation.ProcessStartUtc) -lt $requested.AddSeconds(-1)) { throw 'Official activation did not return the expected newly started package process.' }
    $lease.registeredProcessId=$activation.ProcessId; $lease.registeredProcessStartUtc=$activation.ProcessStartUtc; $lease.state='REGISTERED'
    Write-DesktopProtectedJson $leasePath $lease
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(20); $matched=$false
    do {
        foreach ($file in Get-ChildItem -LiteralPath $directory -Filter ('desktop-shell-env-'+$launchId+'-*.json') -File) {
            Assert-DesktopLocalPath $file.FullName -MustExist -Owned
            if (-not (Test-DesktopTrustedWriters $file.FullName)) { continue }
            $record=ConvertFrom-DesktopJson ([IO.File]::ReadAllText($file.FullName))
            if ($record.status -ceq 'APPLIED' -and $record.launchId -ceq $launchId -and $record.parentProcessId -eq $activation.ProcessId -and $record.parentStartUtc -ceq $activation.ProcessStartUtc -and $record.adapterHashMatches) { $matched=$true; break }
        }
        if ($matched) { break }; Start-Sleep -Milliseconds 100
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    if (-not $matched) { throw 'Desktop opened but its scoped shell environment was not verified. Inspect setup before retrying; the launcher does not terminate it.' }
    $process=Get-Process -Id $activation.ProcessId -ErrorAction Stop
    if ($process.Path -ine $desktopExe -or $process.HasExited) { throw 'Desktop exited before verification completed.' }
    [pscustomobject]@{status='DESKTOP_STARTED_PROFILE_APPLIED';packageVersion=$installation.packageVersion;globalPathChanged=$false;remoteTransportVerified=$false}
} catch {
    $lease.state='FAILED'; $lease.expiresUtc=[DateTimeOffset]::UtcNow.ToString('o')
    try { Write-DesktopProtectedJson $leasePath $lease } catch { Write-Warning 'Could not disable the startup lease; its original 60-second expiry remains.' }
    throw
}
