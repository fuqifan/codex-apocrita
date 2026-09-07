#requires -Version 7.0
[CmdletBinding()]
param([switch]$CheckOnly, [switch]$Remove, [string[]]$ProfilePaths)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Desktop-LocalFiles.ps1')
if ($CheckOnly -and $Remove) { throw 'Choose CheckOnly or Remove.' }
$hook = Join-Path $PSScriptRoot 'Desktop-ShellEnvironment.ps1'
$statePath = Join-Path $PSScriptRoot 'state\desktop-profile-installation.json'
if (-not $ProfilePaths) {
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $ProfilePaths = @((Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'), (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'))
}
$profiles = @($ProfilePaths | ForEach-Object { [IO.Path]::GetFullPath($_) })
if (@($profiles | Select-Object -Unique).Count -ne $profiles.Count) { throw 'Duplicate profile paths.' }
$marker = '# codex-apocrita-desktop-environment-v1'
$suffix = "`r`n$marker`r`n. '$($hook.Replace("'", "''"))'`r`n# end-codex-apocrita-desktop-environment-v1`r`n"
$utf8 = [Text.UTF8Encoding]::new($false, $true)
$state = $null
if (Test-Path -LiteralPath $statePath) {
    Assert-DesktopLocalPath $statePath -MustExist -Owned
    if (-not (Test-DesktopTrustedWriters $statePath)) { throw 'Untrusted installation record.' }
    $state = ConvertFrom-DesktopJson ([IO.File]::ReadAllText($statePath))
    if ($state.hookPath -ine $hook -or @($state.profiles).Count -ne $profiles.Count -or @($state.profiles | Where-Object { $_.path -notin $profiles }).Count) { throw 'Installation record belongs to another hook or profile selection.' }
}
if (-not $CheckOnly) {
    Assert-DesktopStopped
    [void](Initialize-DesktopStateDirectory $PSScriptRoot)
    if (-not $Remove) {
        foreach ($name in @('Desktop-ShellEnvironment.ps1','Desktop-LocalFiles.ps1','src\DesktopShellLaunch.cs','src\DesktopPackageActivation.cs','adapter-config.json','bin\ssh.exe')) { Protect-DesktopLocalFile (Join-Path $PSScriptRoot $name) }
    }
}
$results = @(); $changes = [Collections.Generic.List[object]]::new()
foreach ($path in $profiles) {
    Assert-DesktopLocalPath $path -Owned
    $exists = Test-Path -LiteralPath $path
    if ($exists -and (-not (Test-Path -LiteralPath $path -PathType Leaf) -or -not (Test-DesktopTrustedWriters $path))) { throw 'Profile must be a regular file with trusted writers.' }
    [byte[]]$bytes = if ($exists) { ,([IO.File]::ReadAllBytes($path)) } else { ,([byte[]]::new(0)) }
    $encoding=$utf8; $offset=0
    # UTF-32 is deliberately rejected instead of treating its BOM as UTF-16.
    if ($bytes.Length -ge 4 -and (($bytes[0] -eq 255 -and $bytes[1] -eq 254 -and $bytes[2] -eq 0 -and $bytes[3] -eq 0) -or ($bytes[0] -eq 0 -and $bytes[1] -eq 0 -and $bytes[2] -eq 254 -and $bytes[3] -eq 255))) { throw 'UTF-32 profiles require manual integration; nothing was changed.' }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) { $encoding=[Text.Encoding]::Unicode; $offset=2 }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) { $encoding=[Text.Encoding]::BigEndianUnicode; $offset=2 }
    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { $offset=3 }
    if ($offset -eq 0 -and $hook -match '[^\x00-\x7F]') { throw 'Use an ASCII adapter installation path for BOM-less PowerShell profiles.' }
    try { $text=$encoding.GetString($bytes,$offset,$bytes.Length-$offset) } catch { throw 'Unrecognized profile encoding; nothing was changed.' }
    $installed=$text.EndsWith($suffix,[StringComparison]::Ordinal)
    if ($text.Contains($marker) -and -not $installed) { throw 'The managed profile suffix was edited or moved; automatic editing stopped.' }
    $entry=if ($state) { @($state.profiles | Where-Object path -eq $path)[0] } else { $null }
    if ($installed -and -not $entry) { throw 'Managed suffix has no installation record; automatic editing stopped.' }
    $action='checked'
    if ($Remove -and $installed) {
        $remaining=[byte[]]::new($bytes.Length-$encoding.GetByteCount($suffix)); [Array]::Copy($bytes,$remaining,$remaining.Length)
        $changes.Add([pscustomobject]@{path=$path;before=$bytes;bytes=$remaining;removeFile=(-not $entry.existedBefore -and $remaining.Length -eq 0);action='removed'})
        $action='pending-removal'
    } elseif (-not $CheckOnly -and -not $Remove -and -not $installed) {
        $append=$encoding.GetBytes($suffix); $combined=[byte[]]::new($bytes.Length+$append.Length)
        [Array]::Copy($bytes,$combined,$bytes.Length); [Array]::Copy($append,0,$combined,$bytes.Length,$append.Length)
        $changes.Add([pscustomobject]@{path=$path;before=$bytes;bytes=$combined;removeFile=$false;action='installed'})
        $action='pending-installation'
    }
    $results += [pscustomobject]@{path=$path;installed=$installed;action=$action;existedBefore=if($entry){$entry.existedBefore}else{$exists};originalBytes=if($entry){$entry.originalBytes}else{$bytes.Length}}
}
$report=[ordered]@{version=1;hookPath=$hook;profiles=$results;removed=[bool]$Remove;profileContentsRecorded=$false;globalPathModified=$false}
if (-not $CheckOnly) {
    # Preflight every destination before the first profile write. Recovery state
    # stores only paths and lengths; existing profile bodies stay in their files.
    foreach ($change in $changes) {
        $parent=Split-Path $change.path -Parent
        if (-not (Test-Path -LiteralPath $parent)) { [void][IO.Directory]::CreateDirectory($parent) }
        Assert-DesktopLocalPath $parent -MustExist -Owned
        if (-not (Test-DesktopTrustedWriters $parent)) { throw 'Profile directory permits untrusted writers.' }
    }
    Write-DesktopProtectedJson $statePath $report
    foreach ($change in $changes) {
        Assert-DesktopLocalPath $change.path -Owned
        [byte[]]$current=if ([IO.File]::Exists($change.path)) { ,([IO.File]::ReadAllBytes($change.path)) } else { ,([byte[]]::new(0)) }
        if ([Convert]::ToBase64String($current) -cne [Convert]::ToBase64String($change.before)) { throw 'Profile changed after preflight; retry after inspecting the installation record.' }
        if ($change.removeFile) { [IO.File]::Delete($change.path) }
        else { Write-DesktopProtectedBytes $change.path $change.bytes }
        $updated=@($report.profiles | Where-Object path -eq $change.path)[0]
        $updated.action=$change.action; $updated.installed=($change.action -eq 'installed')
        Write-DesktopProtectedJson $statePath $report
    }
}
[pscustomobject]$report
