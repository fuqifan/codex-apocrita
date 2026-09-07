#requires -Version 7.0
# Temporary profiles only. No actual Windows profile installation or app launch.
$ErrorActionPreference='Stop'
$source=Split-Path $PSScriptRoot -Parent
$temporary=Join-Path $PSScriptRoot ('codex-adapter-profile-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$stage='fixture setup'
try {
    foreach ($dir in @('src','bin','profiles')) { [void][IO.Directory]::CreateDirectory((Join-Path $temporary $dir)) }
    foreach ($name in @('Desktop-LocalFiles.ps1','Initialize-AdapterConfiguration.ps1','Install-DesktopProfileHook.ps1','Desktop-ShellEnvironment.ps1','src\DesktopShellLaunch.cs','src\DesktopPackageActivation.cs')) { [IO.File]::WriteAllBytes((Join-Path $temporary $name),[IO.File]::ReadAllBytes((Join-Path $source $name))) }
    # The profile installer only checks presence/ACLs. This file is never executed.
    [IO.File]::WriteAllBytes((Join-Path $temporary 'bin\ssh.exe'),[byte[]]::new(0))
    [IO.File]::WriteAllText((Join-Path $temporary 'adapter-config.json'),'{}')
    . (Join-Path $temporary 'Desktop-LocalFiles.ps1')
    Protect-DesktopLocalFile $temporary
    # Scoped command mock lets fixture installation run while real Desktop stays open.
    function Get-Process { param([string]$Name) if ($Name -ne 'ChatGPT') { throw 'Unexpected process query in fixture.' } }
    $profiles=@((Join-Path $temporary 'profiles\utf8.ps1'),(Join-Path $temporary 'profiles\utf16.ps1'))
    $prefixes=@([Text.UTF8Encoding]::new($false).GetBytes("# user profile`r`n"),[byte[]]([Text.Encoding]::Unicode.GetPreamble()+[Text.Encoding]::Unicode.GetBytes("# unicode profile`r`n")))
    for ($index=0;$index -lt 2;$index++) { [IO.File]::WriteAllBytes($profiles[$index],$prefixes[$index]) }
    $acls=@($profiles | ForEach-Object { (Get-Acl -LiteralPath $_).Sddl })
    $installer=Join-Path $temporary 'Install-DesktopProfileHook.ps1'
    $stage='initial preflight'; $before=& $installer -CheckOnly -ProfilePaths $profiles
    if (@($before.profiles|Where-Object installed).Count) { throw 'Unexpected initial hook.' }
    $stage='first installation'; $first=& $installer -ProfilePaths $profiles
    $hashes=@($profiles|ForEach-Object{(Get-FileHash -LiteralPath $_).Hash})
    $stage='idempotent installation'; $again=& $installer -ProfilePaths $profiles
    for ($index=0;$index -lt 2;$index++) {
        if ((Get-FileHash -LiteralPath $profiles[$index]).Hash -ne $hashes[$index]) { throw 'Installation is not idempotent.' }
        if ((Get-Acl -LiteralPath $profiles[$index]).Sddl -cne $acls[$index]) { throw 'Existing profile ACL changed.' }
    }
    $pathBefore=$env:PATH; $markerBefore=$env:APOCRITA_ADAPTER_LAUNCH_ID
    . $profiles[0]
    if ($env:PATH -cne $pathBefore -or $env:APOCRITA_ADAPTER_LAUNCH_ID -cne $markerBefore) { throw 'Ordinary profile changed process environment.' }
    $stage='rollback'; $removed=& $installer -Remove -ProfilePaths $profiles
    for ($index=0;$index -lt 2;$index++) {
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($profiles[$index])) -cne [Convert]::ToBase64String($prefixes[$index])) { throw 'Rollback did not preserve profile bytes.' }
    }
    $newProfiles=@((Join-Path $temporary 'profiles\created.ps1'))
    # A separate isolated installation record is required for a different profile selection.
    [IO.File]::Delete((Join-Path $temporary 'state\desktop-profile-installation.json'))
    $stage='new profile installation'; [void](& $installer -ProfilePaths $newProfiles)
    [void](& $installer -Remove -ProfilePaths $newProfiles)
    if (Test-Path -LiteralPath $newProfiles[0]) { throw 'New empty managed profile was not removed.' }
    [IO.File]::Delete((Join-Path $temporary 'state\desktop-profile-installation.json'))
    [void](& $installer -ProfilePaths $profiles)
    [IO.File]::AppendAllText($profiles[0],"# later edit`r`n")
    $refused=$false
    try { [void](& $installer -Remove -ProfilePaths $profiles) } catch { $refused=$true }
    if (-not $refused) { throw 'Moved suffix must fail closed.' }
    $stage='reparse guard'
    $junction=Join-Path $temporary 'junction'
    [void](New-Item -ItemType Junction -Path $junction -Target (Join-Path $temporary 'profiles'))
    $refused=$false
    try { Assert-DesktopLocalPath (Join-Path $junction 'utf8.ps1') -MustExist } catch { $refused=$true }
    if (-not $refused) { throw 'Reparse ancestor must be rejected.' }
    # Remove this verified link itself, not its target, before recursive cleanup.
    [IO.Directory]::Delete($junction)
    $stage='writer guard'
    $probe=Join-Path $temporary 'writer-probe.txt'; [IO.File]::WriteAllText($probe,'fixture')
    $acl=Get-Acl -LiteralPath $probe
    [void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Write','Allow'))
    Set-Acl -LiteralPath $probe -AclObject $acl
    if (Test-DesktopTrustedWriters $probe) { throw 'Everyone write access must be rejected.' }
    $stage='configuration validation read lock'
    # This fixture executable is not the adapter. It only attempts local writes
    # and deletion against its explicit test JSON while the initializer validates it.
    $validatorSource=Join-Path $temporary 'ValidationLockFixture.cs'
    [IO.File]::WriteAllText($validatorSource,@'
using System;
using System.IO;
internal static class ValidationLockFixture {
    private static int Main(string[] args) {
        if (args.Length != 2 || args[0] != "--validate-config") return 2;
        if (File.ReadAllText(args[1]) != "{\"fixture\":true}") return 3;
        bool writeBlocked = false;
        bool deleteBlocked = false;
        try { using (File.Open(args[1], FileMode.Open, FileAccess.Write, FileShare.ReadWrite)) {} }
        catch (IOException) { writeBlocked = true; }
        try { File.Delete(args[1]); }
        catch (IOException) { deleteBlocked = true; }
        if (!writeBlocked || !deleteBlocked) return 4;
        Console.WriteLine("ADAPTER_CONFIG_VALID");
        return 0;
    }
}
'@)
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler /nologo /target:exe /platform:x64 /warnaserror+ ('/out:'+(Join-Path $temporary 'bin\ssh.exe')) $validatorSource
    if ($LASTEXITCODE -ne 0) { throw 'Local validation lock fixture compilation failed.' }
    $lockConfig=Join-Path $temporary 'lock-fixture.json'
    [IO.File]::WriteAllText($lockConfig,'{"fixture":true}')
    $validationResult=& (Join-Path $temporary 'Initialize-AdapterConfiguration.ps1') -ConfigPath $lockConfig -CheckOnly
    if (-not $validationResult.valid -or $validationResult.changed -or [IO.File]::ReadAllText($lockConfig) -cne '{"fixture":true}') { throw 'Validation did not preserve locked configuration bytes.' }
    [pscustomobject]@{pass=$true;scope='Temporary profiles, local validation fixture and mocked process-list only';checks=@('UTF8 and UTF16 bytes preserved','existing ACL preserved','idempotent installation','ordinary profile environment unchanged','exact rollback','new managed profile removed','edited suffix refused','reparse ancestor rejected','untrusted writer rejected','configuration validation blocks concurrent write and delete')}
} catch { throw ('Fixture stage '+$stage+' failed: '+$_.Exception.Message) } finally {
    # Resolve and verify the exact disposable test root before recursive cleanup.
    $resolved=[IO.Path]::GetFullPath($temporary)
    $tempRoot=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
    if ($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolved) -like 'codex-adapter-profile-test-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
