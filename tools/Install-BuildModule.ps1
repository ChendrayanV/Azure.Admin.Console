<#
.SYNOPSIS
    Installs a build or test module from the PowerShell Gallery for CI and the
    release workflow, retrying when the Gallery has a bad minute.
.DESCRIPTION
    The Gallery sometimes answers 5xx (504 Gateway Time-out, 503) or times out
    for a while; one such answer used to fail a whole release. Each install
    gets -Attempt tries, waiting 20, 40, 60... seconds between them. It
    installs for the current user and trusts the repository: on a fresh
    runner the repository store doesn't exist yet, and
    Set-PSResourceRepository fails before anything creates it.
.PARAMETER Name
    The module.
.PARAMETER Version
    A NuGet version range, such as '[6.2.0,7.0)'. The latest if not given.
.PARAMETER Attempt
    How many tries (4 if not given).
.EXAMPLE
    ./tools/Install-BuildModule.ps1 -Name Pester -Version '[6.2.0,7.0)'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Name,

    [string] $Version,

    [ValidateRange(1, 10)]
    [int] $Attempt = 4
)

$ErrorActionPreference = 'Stop'
$install = @{ Name = $Name; Scope = 'CurrentUser'; TrustRepository = $true; Quiet = $true }
if ($Version) { $install.Version = $Version }
for ($try = 1; ; $try++) {
    try {
        Install-PSResource @install
        Write-Host "$Name $(if ($Version) { $Version } else { '(latest)' }) installed$(if ($try -gt 1) { " on try $try" })."
        return
    }
    catch {
        if ($try -ge $Attempt) { throw "Installing $Name from the PowerShell Gallery failed $Attempt times; the last: $($_.Exception.Message)" }
        $wait = 20 * $try
        Write-Warning "Installing $Name failed (try $try of $Attempt): $($_.Exception.Message) - trying again in $wait seconds."
        Start-Sleep -Seconds $wait
    }
}
