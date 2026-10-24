function Test-AACAlzPolicy {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Compares the policy assignments on your management groups with the
        Azure Landing Zones reference - what each archetype assigns - and
        lists what is missing, assigned differently, or present.
    .DESCRIPTION
        Reads a local copy of the Azure Landing Zones Library (clone
        github.com/Azure/Azure-Landing-Zones-Library at the release you want
        to compare with; nothing is downloaded): the architecture's
        management groups (by default 'alz': the root, Platform,
        Connectivity, Identity, Management, Landing zones, Corp, Online,
        Sandbox, Decommissioned...), the archetypes each one gets and the
        policy assignments each archetype makes. Then reads, read-only and
        tenant-wide in Azure Resource Graph, the management groups and the
        policy assignments deployed on them.

        A row per assignment the reference makes on a management group
        (AAC.AlzPolicyCheck):
          Missing    nothing with that name or definition is assigned there
                     (Medium) - the library file to deploy it from is named
          Different  assigned, with another definition (an older or newer
                     version, or a replacement), or not enforced where the
                     reference enforces (Low)
          Present    assigned as the reference has it
        A reference management group that doesn't exist in the tenant is
        one Info row: map the reference's IDs to yours with
        -ManagementGroupMap. Reader on the management groups is enough.
    .PARAMETER LibraryPath
        The Azure Landing Zones Library folder: the repository root, or its
        platform\alz folder.
    .PARAMETER Architecture
        The library's architecture to compare with. Default 'alz'.
    .PARAMETER ManagementGroupMap
        The reference's management group IDs -> yours, for those named
        differently: @{ alz = 'contoso'; landingzones = 'contoso-lz' }.
    .PARAMETER Status
        Only these: Missing, Different, Present, NotFound.
    .PARAMETER CsvPath
        Write the checks to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the checks.
    .PARAMETER NoDisplay
        Return the checks without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        git clone https://github.com/Azure/Azure-Landing-Zones-Library C:\alz-library
        Test-AACAlzPolicy -LibraryPath C:\alz-library -ManagementGroupMap @{ alz = 'contoso' }
        Your hierarchy against the reference, the intermediate root named 'contoso'.
    .EXAMPLE
        Test-AACAlzPolicy -LibraryPath C:\alz-library -Status Missing -NoDisplay | Select-Object ManagementGroup, Assignment, LibraryFile
        What to deploy, and the library file to deploy it from.
    .OUTPUTS
        AAC.AlzPolicyCheck
    #>
    [CmdletBinding()]
    [OutputType('AAC.AlzPolicyCheck')]
    param(
        [Parameter(Mandatory)]
        [string] $LibraryPath,

        [string] $Architecture = 'alz',

        [hashtable] $ManagementGroupMap = @{},

        [ValidateSet('Missing', 'Different', 'Present', 'NotFound')]
        [string[]] $Status,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure Landing Zones policy check',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $library = Read-AACAlzLibrary -Path (& $resolve $LibraryPath) -Architecture $Architecture
    $map = @{}; foreach ($k in $ManagementGroupMap.Keys) { $map[[string]$k] = [string]$ManagementGroupMap[$k] }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Azure Landing Zones policy check' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the management groups and their policy assignments'
        $read = Invoke-AACGraphBatch -Query ([ordered]@{
                groups      = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project name = tolower(name)" }
                assignments = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | extend scope = tolower(tostring(properties.scope)) | where scope startswith '/providers/microsoft.management/managementgroups/' | project id, name, displayName = tostring(properties.displayName), scope, definitionId = tolower(tostring(properties.policyDefinitionId)), enforcement = tostring(properties.enforcementMode)" }
            })
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} management group(s) and {1:N0} assignment(s) on them' -f @($read.Rows['groups']).Count, @($read.Rows['assignments']).Count)
        ConvertTo-AACAlzPolicy -Library $library -Assignment @($read.Rows['assignments'] | Where-Object { $_ }) -ManagementGroup @($read.Rows['groups'] | Where-Object { $_ } | ForEach-Object { [string]$_['name'] }) -Map $map
    }

    $checks = @($outcome.Checks)
    if ($Status) { $wanted = @($Status | ForEach-Object { if ($_ -eq 'NotFound') { 'Not found' } else { $_ } }); $checks = @($checks | Where-Object { $wanted -contains $_.Status }) }
    $s = $outcome.Stats
    $rank = Get-AACSeverityRank
    $tones = @{ Missing = 'bad'; Different = 'warn'; Present = 'good'; 'Not found' = 'neutral' }
    $report = @{
        Subtitle = 'Azure Landing Zones policy check: the assignments on your management groups against what the reference archetypes assign'
        Facts    = [ordered]@{ Library = $library.Version; Architecture = $library.Architecture; Mapped = $(if ($map.Count) { (@($map.Keys | ForEach-Object { "$_ = $($map[$_])" }) -join ', ') } else { 'the reference''s IDs' }) }
        Status   = $(if ($s.Missing) { 'Warning' } elseif ($s.Different) { 'Info' } else { 'Success' })
        Headline = "$($s.Coverage)% of the reference's assignments are in place: $($s.Present) as the reference has them, $($s.Different) different, $($s.Missing) missing$(if ($s.NotFound) { "; $($s.NotFound) reference management group(s) not found" })"
        Tiles    = @(
            @{ Value = "$($s.Coverage)%"; Label = 'in place'; Tone = $(if ($s.Coverage -ge 90) { 'good' } elseif ($s.Coverage -ge 60) { 'warn' } else { 'bad' }) }
            @{ Value = '{0:N0}' -f $s.Missing; Label = 'missing'; Tone = $(if ($s.Missing) { 'bad' } else { 'good' }); Table = 'checks'; Filters = @{ Status = 'Missing' } }
            @{ Value = '{0:N0}' -f $s.Different; Label = 'different'; Tone = $(if ($s.Different) { 'warn' } else { 'good' }); Table = 'checks'; Filters = @{ Status = 'Different' } }
            @{ Value = '{0:N0}' -f $s.NotFound; Label = 'groups not found'; Tone = $(if ($s.NotFound) { 'warn' } else { 'good' }); Table = 'checks'; Filters = @{ Status = 'Not found' } }
        )
        Notices  = @($outcome.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Missing by management group'; Items = @($checks | Where-Object Status -EQ 'Missing' | Group-Object ManagementGroup | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'checks'; Column = 'ManagementGroup'; Tone = 'bad'; Console = $true }
            @{ Title = 'By status'; Kind = 'donut'; CenterLabel = 'assignments'; Items = @($checks | Group-Object Status | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $tones[$_.Name]; Filter = $_.Name } }); Table = 'checks'; Column = 'Status' }
        )
        Tables   = @(
            @{ Id = 'checks'; Title = 'Reference assignments'; Section = 'Checks'; Rows = $checks; Noun = 'assignments'; GroupBy = @('ManagementGroup', 'Status'); ConsoleLimit = 30
                Empty = 'Nothing to compare.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $tones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ManagementGroup'; Label = 'Management group'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Archetype'; Label = 'Archetype'; Facet = $true; Console = $true }
                    @{ Key = 'Assignment'; Label = 'Assignment'; Console = $true; Pdf = $true }
                    @{ Key = 'DisplayName'; Label = 'Display name'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Expected'; Label = 'Reference definition'; Type = 'mono' }
                    @{ Key = 'Deployed'; Label = 'Deployed definition'; Type = 'mono' }
                    @{ Key = 'DeployedEnforcement'; Label = 'Enforcement' }
                    @{ Key = 'LibraryFile'; Label = 'Library file'; Type = 'mono' }
                    @{ Key = 'LibraryGroup'; Label = 'Reference group' }
                ) }
        )
        Hint     = '-ManagementGroupMap maps the reference''s IDs to yours; -Status Missing lists what to deploy; -NoDisplay returns the checks; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $checks -Noun 'check' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $checks -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
