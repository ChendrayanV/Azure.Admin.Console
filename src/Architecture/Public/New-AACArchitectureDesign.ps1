function New-AACArchitectureDesign {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Step 3: builds the design - components, settings and connections -
        from a brief and the recommended (or chosen) patterns, and returns it.
    .DESCRIPTION
        With no -Pattern, the recommended patterns are used. A landing zone
        (-LandingZone, or the brief's answer) has its inherited policy and
        allowed regions read from Azure - Connect-AAC first, or -Offline.
        See the components with $design.Nodes.
    .PARAMETER Brief
        The brief, or the path of a saved one.
    .PARAMETER Pattern
        Pattern IDs (cache-aside, retry...), or piped from Get-AACArchitecturePattern.
    .PARAMETER Region
        One region, or two (primary first). westeurope by default.
    .PARAMETER LandingZone
        The landing zone management group ID.
    .PARAMETER Offline
        Don't read the landing zone from Azure.
    .PARAMETER Tag
        Tags for every resource: @{ CostCenter = 'cc-123' }.
    .PARAMETER Override
        Change components by ID: @{ data = @{ Sku = 'Hyperscale' } }.
    .PARAMETER Commitment
        ReservedInstances or SavingsPlan.
    .PARAMETER Name
        The design's name (the brief's by default).
    .PARAMETER OutPath
        Save the design as JSON.
    .PARAMETER NoDisplay
        Return the design without the summary.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        $design = New-AACArchitectureDesign -Brief $brief -Offline -OutPath .\orders-api.design.json
        The design with the recommended patterns.
    .EXAMPLE
        $design = New-AACArchitectureDesign -Brief $brief -Region westeurope, northeurope -LandingZone 'mg-landingzones'
        Two regions, checked against the landing zone's policy.
    .OUTPUTS
        AAC.ArchitectureDesign
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('AAC.ArchitectureDesign')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object] $Brief,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]] $Pattern,

        [ValidateNotNullOrEmpty()]
        [string[]] $Region = @('westeurope'),

        [string] $LandingZone,

        [switch] $Offline,

        [System.Collections.IDictionary] $Tag = @{},

        [System.Collections.IDictionary] $Override = @{},

        [ValidateSet('', 'ReservedInstances', 'SavingsPlan')]
        [string] $Commitment = '',

        [string] $Name,

        [string] $OutPath,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $chosen = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($p in @($Pattern | Where-Object { $_ })) { if (-not $chosen.Contains($p)) { $chosen.Add($p) } }
    }
    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }
        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Architecture design' -Color 'mediumpurple2' }
        $catalog = Get-AACArchitectureCatalog
        $source = if ($Brief -is [string]) { & $resolve $Brief } else { $Brief }
        $resolved = Resolve-AACArchitectureInput -InputObject $source -Kind Brief
        $answers = [ordered]@{}
        foreach ($key in $resolved.Answers.Keys) { $answers[$key] = $resolved.Answers[$key] }
        if ($PSBoundParameters.ContainsKey('LandingZone')) { $answers['OPS-03'] = $LandingZone }
        $full = ConvertTo-AACArchitectureBrief -Catalog $catalog -Answer $answers -Name $(if ($Name) { $Name } else { $resolved.Name })
        $full.Open = @(@($resolved.Open) + @($full.Open) | Select-Object -Unique)
        $full.Assumed = @(@($resolved.Assumed) + @($full.Assumed) | Where-Object { $full.Open -notcontains $_ } | Select-Object -Unique)

        $known = @($catalog.Patterns | ForEach-Object Id)
        foreach ($p in $chosen) { if ($known -notcontains $p) { throw "Azure Admin Console doesn't know the pattern '$p'. The patterns are $($known -join ', ')." } }
        $patterns = if ($chosen.Count) { $chosen.ToArray() } else { @(ConvertTo-AACArchitecturePattern -Catalog $catalog -Answers $full.Answers | Where-Object Recommended -EQ 'Yes' | ForEach-Object Id) }

        $zone = $null
        $notices = [System.Collections.Generic.List[string]]::new()
        if ($full.Answers['OPS-03'] -and -not $Offline) {
            try { $zone = Get-AACArchitectureLandingZone -ManagementGroup ([string]$full.Answers['OPS-03']) }
            catch { $notices.Add("The landing zone $($full.Answers['OPS-03']) couldn't be read, so its policy isn't checked: $($_.Exception.Message) (Connect-AAC first, or -Offline.)") }
        }
        $design = ConvertTo-AACArchitectureDesign -Brief $full -Pattern $patterns -Region $Region -LandingZone $zone -Tag $Tag -Override $Override -Commitment $Commitment
        $design.Notices = @(@($design.Notices) + @($notices))

        $nodes = @($design.Nodes | ForEach-Object { $n = $_; $o = [ordered]@{ PSTypeName = 'AAC.ArchitectureComponent' }; foreach ($k in 'Id', 'Name', 'Kind', 'Service', 'Zone', 'Region', 'Sku', 'ZoneRedundant', 'PrivateEndpoint', 'PublicAccess', 'Identity', 'Settings', 'Pattern') { $o[$k] = $n[$k] }; [pscustomobject]$o })
        $object = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.ArchitectureDesign'; Name = $design.Name; CatalogVersion = $design.CatalogVersion; Created = $design.Created; Regions = $design.Regions; LandingZone = $design.LandingZone
            Patterns = $design.Patterns; Components = $nodes.Count; Nodes = $nodes; Connections = @($design.Connections | ForEach-Object { [pscustomobject]$_ }); ManagementGroups = $design.ManagementGroups
            Policies = @($design.Policies | ForEach-Object { [pscustomobject]$_ }); AllowedLocations = $design.AllowedLocations; Tags = $design.Tags; Commitment = $design.Commitment
            Answers = $design.Answers; Open = $design.Open; Assumed = $design.Assumed; Notices = $design.Notices
        }
        if ($OutPath -and $PSCmdlet.ShouldProcess((& $resolve $OutPath), 'Save the architecture design')) {
            $path = & $resolve $OutPath
            $folder = Split-Path -Path $path -Parent
            if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
            $object | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
        }

        $report = @{
            Facts    = [ordered]@{ Design = $design.Name; Regions = ($design.Regions -join ', '); 'Landing zone' = $(if ($design.LandingZone) { $design.LandingZone } else { 'none' }); Catalog = $design.CatalogVersion }
            Status   = $(if ($design.Notices.Count) { 'Warning' } else { 'Success' })
            Headline = "$($nodes.Count) component(s), $(@($design.Connections).Count) connection(s), $(@($design.Patterns).Count) pattern(s): $((@($design.Patterns | ForEach-Object { $id = $_; @($catalog.Patterns | Where-Object Id -EQ $id)[0].Name })) -join ', ')"
            Notices  = @($design.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
            Tiles    = @(
                @{ Value = '{0:N0}' -f $nodes.Count; Label = 'components'; Tone = 'info' }
                @{ Value = '{0:N0}' -f @($design.Regions).Count; Label = 'region(s)'; Tone = 'violet' }
                @{ Value = '{0:N0}' -f @($design.Policies).Count; Label = 'inherited policy assignments'; Tone = 'info' }
            )
            Tables   = @(@{ Id = 'components'; Title = 'Components'; Rows = $nodes; Noun = 'components'; NoConsole = $true
                    Columns = @(
                        @{ Key = 'Zone'; Label = 'Zone'; Console = $true }
                        @{ Key = 'Name'; Label = 'Component'; Console = $true }
                        @{ Key = 'Sku'; Label = 'SKU'; Console = $true }
                        @{ Key = 'Region'; Label = 'Region'; Console = $true }
                        @{ Key = 'ZoneRedundant'; Label = 'Zone-redundant'; Console = $true }
                        @{ Key = 'PrivateEndpoint'; Label = 'Private endpoint'; Console = $true }
                        @{ Key = 'Pattern'; Label = 'Why'; Type = 'wide'; Console = $true }
                    ) })
            Hint     = 'Next: Test-AACArchitectureDesign checks it; New-AACArchitectureDiagram draws it; -Override changes a component.'
        }
        Invoke-AACReportOutput -Report $report -Title 'Architecture design' -ShowView:$interactive -NoPaging:$NoPaging -Object @($object) -ReturnObject
    }
}
