function Export-AACResource {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Exports your Azure resources - for the whole tenant, a management group,
        subscriptions, resource groups or resource types - to CSV, HTML and PDF,
        with the subscription and management group by name, the tags as columns
        and each resource's key settings flattened into plain values.
    .DESCRIPTION
        What Resource Graph Explorer's "Download as CSV" doesn't give you:

          Where       subscription name and state, the management group and its
                      path up to the root, resource group and its tags, location
                      and zones - one Resource Graph query, joined to
                      resourcecontainers
          What        type, kind, SKU and capacity, the parent of a child
                      resource, identity, provisioning state, public network
                      access, managed by, created (when Azure records it)
          Details     the settings people look up, per type: a VM's size, OS,
                      image and power state; a disk's size, state and VM; a
                      storage account's TLS, public access and network rules; a
                      NIC's IP, VM and NSG; an App Service's plan, runtime and
                      host; an AKS cluster's version and nodes; a key vault's
                      soft delete, purge protection and RBAC... about 25 types
          Tags        one column per tag key ('Tag: Environment'), so the CSV
                      sorts and filters in a spreadsheet - and the tags as one
                      'key=value; ...' column too
          -Flatten    every property as a column of its own
                      ('properties.networkAcls.defaultAction'), for the deep
                      dives; best with -ResourceType

        Filters run in Resource Graph where they can (so only what you asked
        for comes back): -ResourceType, -ResourceGroupName, -Name (exact, or
        with wildcards), -Location, -Tag (a value, or '*' for any), -MissingTag
        (resources without a tag - for tag governance) and -Filter, a KQL
        condition of your own. -Search then looks for text anywhere in the name,
        type, group, subscription, location, details, tags and ID.

        Large estates are read in parallel: the subscriptions are split across
        up to four Resource Graph queries, each paged to the end. Read-only;
        Reader is enough.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only these resource groups; wildcards work.
    .PARAMETER ResourceType
        Only these types (for example 'microsoft.compute/virtualmachines', or
        'microsoft.network/*'); wildcards work.
    .PARAMETER Name
        Only resources with these names; wildcards work.
    .PARAMETER Location
        Only resources in these regions (for example uksouth, 'West Europe').
    .PARAMETER Tag
        Only resources with these tags: @{ Environment = 'prod' }, or
        @{ Owner = '*' } for any value.
    .PARAMETER MissingTag
        Only resources without these tags.
    .PARAMETER Search
        Only resources with this text in their name, type, resource group,
        subscription, location, details, tags or ID.
    .PARAMETER Filter
        A Kusto (KQL) condition Resource Graph applies, as '| where <Filter>' -
        for example "tostring(properties.provisioningState) != 'Succeeded'".
    .PARAMETER TagColumn
        The tag keys that get a column of their own. Default: every tag key
        found, the most used first.
    .PARAMETER Flatten
        Add every property, flattened, as a column of its own.
    .PARAMETER First
        Stop after this many resources (after the filters).
    .PARAMETER CsvPath
        Write the resources to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the resources.
    .PARAMETER NoDisplay
        Return the resources without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Export-AACResource -CsvPath .\out\Resources.csv
        Every resource you can see, with names, management groups, tags as columns and details.
    .EXAMPLE
        Export-AACResource -ManagementGroupId mg-landingzones -HtmlPath .\out\LandingZones.html -PdfPath .\out\LandingZones.pdf
        One management group's resources as an interactive report and a PDF.
    .EXAMPLE
        Export-AACResource -ResourceType 'microsoft.compute/virtualmachines' -NoDisplay | Select-Object Name, Subscription, Location, Details
        Every VM with its size, OS, image and power state.
    .EXAMPLE
        Export-AACResource -MissingTag CostCenter, Owner -CsvPath .\out\Untagged.csv
        The resources without a CostCenter or Owner tag, for the owners to fix.
    .EXAMPLE
        Export-AACResource -ResourceType 'microsoft.storage/storageaccounts' -Flatten -CsvPath .\out\Storage.csv
        Every storage account with every property as a column.
    .EXAMPLE
        Export-AACResource -Tag @{ Environment = 'prod' } -Search 'sql'
        Production resources with 'sql' anywhere in them.
    .OUTPUTS
        AAC.Resource
    #>
    [CmdletBinding()]
    [OutputType('AAC.Resource')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [SupportsWildcards()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [SupportsWildcards()]
        [string[]] $Name,

        [string[]] $Location,

        [hashtable] $Tag,

        [string[]] $MissingTag,

        [string] $Search,

        [string] $Filter,

        [string[]] $TagColumn,

        [switch] $Flatten,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $First,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure resources',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolvePath = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        Query          = Get-AACResourceExportQuery -ResourceType $ResourceType -ResourceGroupName $ResourceGroupName -Name $Name -Location $Location -Tag $Tag -MissingTag $MissingTag -Filter $Filter
        Flatten        = [bool]$Flatten
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Resources' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        # Up to four queries side by side, each over its share of the
        # subscriptions (and never more than 1,000 subscriptions in one).
        $ids = @($scope.Ids)
        $parts = [Math]::Max([Math]::Min(4, $ids.Count), [Math]::Ceiling($ids.Count / 1000))
        $queries = [ordered]@{}
        if ($parts -le 1) { $queries['resources'] = @{ Query = $request.Query; SubscriptionId = $ids } }
        else {
            for ($p = 0; $p -lt $parts; $p++) {
                $share = @(for ($i = $p; $i -lt $ids.Count; $i += $parts) { $ids[$i] })
                $queries["resources$($p + 1)"] = @{ Query = $request.Query; SubscriptionId = $share }
            }
        }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description "Reading the resources of $($ids.Count) subscription(s)"
        $read = Invoke-AACGraphBatch -Query $queries -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read part $Done of $Total"
        }
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($key in $queries.Keys) { foreach ($row in @($read.Rows[$key])) { if ($null -ne $row) { $rows.Add($row) } } }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} resource(s)' -f $rows.Count)
        Update-AACProgress -Id 'flatten' -Indeterminate -Description 'Flattening tags, management groups and settings'
        $result = ConvertTo-AACResourceExport -Row $rows.ToArray() -Flatten:$request.Flatten
        Update-AACProgress -Id 'flatten' -Complete -Description ('{0:N0} resource(s) of {1:N0} type(s)' -f $result.Stats.Resources, $result.Stats.Types)
        @{ Result = $result; Scope = $scope }
    }

    # --- What Resource Graph couldn't filter --------------------------------------------------------------------------
    $resources = @($outcome.Result.Resources)
    $like = { param([string] $Value, [string[]] $Pattern) foreach ($p in $Pattern) { if ($Value -like $p) { return $true } }; $false }
    if ($ResourceGroupName) { $resources = @($resources | Where-Object { & $like $_.ResourceGroup $ResourceGroupName }) }
    if ($ResourceType) { $resources = @($resources | Where-Object { & $like $_.ResourceType $ResourceType }) }
    if ($Name) { $resources = @($resources | Where-Object { & $like $_.Name $Name }) }
    if ($Search) {
        $text = "*$Search*"
        $resources = @($resources | Where-Object { $_.Name -like $text -or $_.ResourceType -like $text -or $_.ResourceGroup -like $text -or $_.Subscription -like $text -or $_.Location -like $text -or $_.Details -like $text -or $_.TagText -like $text -or $_.ResourceId -like $text })
    }
    if ($First) { $resources = @($resources | Select-Object -First $First) }

    # --- Flat rows: the CSV, and the report's table ------------------------------------------------------------------
    $tagKeys = if ($TagColumn) { @($TagColumn) } else { @($outcome.Result.TagKeys) }
    $propertyKeys = @()
    if ($Flatten) {
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $propertyKeys = @(foreach ($r in $resources) { foreach ($k in $r.Properties.Keys) { if ($seen.Add($k)) { $k } } })
    }
    $fixed = 'Name', 'ResourceType', 'Kind', 'ResourceGroup', 'Subscription', 'ManagementGroup', 'ManagementGroupPath', 'Location', 'Zones', 'Sku', 'Capacity', 'Identity', 'ProvisioningState', 'PublicNetworkAccess', 'Parent', 'ManagedBy', 'Created', 'Details', 'TagText', 'TagCount', 'ResourceGroupTags', 'SubscriptionId', 'SubscriptionState', 'ManagementGroupId', 'ResourceGroupId', 'ResourceId'
    $rows = @(foreach ($r in $resources) {
            $flat = [ordered]@{}
            foreach ($k in $fixed) { $flat[$(if ($k -eq 'TagText') { 'Tags' } else { $k })] = $r.$k }
            # Tag keys differ in case between resources (Environment, environment): matched without case.
            $tags = @{}
            foreach ($k in $r.Tags.Keys) { $tags[$k.ToLowerInvariant()] = $r.Tags[$k] }
            foreach ($k in $tagKeys) { $flat["Tag: $k"] = [string]$tags[$k.ToLowerInvariant()] }
            foreach ($k in $propertyKeys) { $flat["properties.$k"] = $(if ($r.Properties.Contains($k)) { $r.Properties[$k] } else { $null }) }
            [pscustomobject]$flat
        })

    # --- The report ------------------------------------------------------------------------------------------------------
    $count = { param([object[]] $Items, [string] $Property) @($Items | Group-Object -Property $Property -NoElement | Sort-Object Count -Descending) }
    $types = & $count $resources 'ResourceType'
    $untagged = @($resources | Where-Object { -not $_.TagCount }).Count
    $distinct = { param([string[]] $Values) $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase); foreach ($v in $Values) { if ($v) { $null = $set.Add($v) } }; $set.Count }
    $subscriptions = & $distinct @($resources | ForEach-Object { $_.SubscriptionId })
    $groups = & $distinct @($resources | ForEach-Object { $_.ResourceGroupId })
    $regions = & $distinct @($resources | ForEach-Object { $_.Location })
    $topTags = @($tagKeys | Select-Object -First 8)
    $tagCoverage = @(foreach ($k in $topTags) {
            $n = @($rows | Where-Object { $_."Tag: $k" }).Count
            if ($resources.Count) { @{ Label = $k; Value = [Math]::Round(100 * $n / $resources.Count, 1) } }
        })
    $filters = @(
        if ($ResourceType) { "type $($ResourceType -join ', ')" }
        if ($ResourceGroupName) { "resource group $($ResourceGroupName -join ', ')" }
        if ($Name) { "name $($Name -join ', ')" }
        if ($Location) { "location $($Location -join ', ')" }
        if ($Tag) { 'tag ' + (@($Tag.Keys | ForEach-Object { "$_=$($Tag[$_])" }) -join ', ') }
        if ($MissingTag) { "missing tag $($MissingTag -join ', ')" }
        if ($Search) { "text '$Search'" }
        if ($Filter) { "where $Filter" }
    )
    $columns = @(
        @{ Key = 'Name'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
        @{ Key = 'ResourceType'; Label = 'Type'; Type = 'type'; Facet = $true; Console = $true; Pdf = $true }
        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Console = $true; Pdf = $true }
        @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true; Console = $true }
        @{ Key = 'Location'; Label = 'Location'; Facet = $true; Console = $true; Pdf = $true }
        @{ Key = 'Sku'; Label = 'SKU'; Facet = $true }
        @{ Key = 'Details'; Label = 'Details'; Type = 'wide'; Pdf = $true }
        @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
        @{ Key = 'ManagementGroup'; Label = 'Management group'; Facet = $true }
        @{ Key = 'ManagementGroupPath'; Label = 'Management group path'; Hidden = $true }
        @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Hidden = $true }
        @{ Key = 'Identity'; Label = 'Identity'; Facet = $true }
        @{ Key = 'ProvisioningState'; Label = 'Provisioning'; Facet = $true; Hidden = $true }
        @{ Key = 'PublicNetworkAccess'; Label = 'Public access'; Facet = $true; Hidden = $true }
        @{ Key = 'Zones'; Label = 'Zones'; Hidden = $true }
        @{ Key = 'Parent'; Label = 'Parent'; Hidden = $true }
        @{ Key = 'Created'; Label = 'Created'; Type = 'date'; Hidden = $true }
    ) + @($topTags | ForEach-Object { @{ Key = "Tag: $_"; Label = "Tag: $_"; Facet = $true } })
    $report = @{
        Subtitle = 'Resources with their subscription, management group, tags and key settings'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Filters = $(if ($filters.Count) { $filters -join '; ' } else { 'none' }) }
        Status   = 'Info'
        Headline = $(if ($resources.Count) { "{0:N0} resource(s) of {1:N0} type(s) in {2:N0} resource group(s) across {3:N0} subscription(s); {4:N0} untagged" -f $resources.Count, $types.Count, $groups, $subscriptions, $untagged } else { 'No resources match.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $resources.Count; Label = 'resources'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $types.Count; Label = 'types'; Tone = 'violet' }
            @{ Value = '{0:N0}' -f $subscriptions; Label = 'subscriptions'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $groups; Label = 'resource groups'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $regions; Label = 'locations'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $untagged; Label = 'untagged'; Tone = $(if ($untagged) { 'warn' } else { 'good' }) }
        )
        Charts   = @(
            @{ Title = 'Top types'; Items = @($types | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'resources'; Column = 'ResourceType'; Tone = 'violet'; Console = $true }
            @{ Title = 'By location'; Items = @(& $count $resources 'Location' | Select-Object -First 10 | ForEach-Object { @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = $_.Count; Filter = $_.Name } }); Table = 'resources'; Column = 'Location'; Tone = 'info'; Console = $true }
            @{ Title = 'By subscription'; Items = @(& $count $resources 'Subscription' | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'resources'; Column = 'Subscription'; Tone = 'neutral' }
            @{ Title = 'Tag coverage (% of resources)'; Items = $tagCoverage; Tone = 'good' }
        )
        Tables   = @(
            @{ Id = 'resources'; Title = 'Resources'; Section = 'Resources'; Rows = $rows; Noun = 'resources'; GroupBy = @('ResourceType', 'ResourceGroup', 'Subscription', 'Location', 'ManagementGroup'); ConsoleLimit = 30
                Empty = 'No resources match.'; Columns = $columns }
        )
        Hint     = '-ResourceType, -ResourceGroupName, -Tag, -MissingTag, -Search and -Filter narrow it; -Flatten adds every property; -CsvPath for a spreadsheet, -HtmlPath and -PdfPath for reports.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'resource' -CsvPath (& $resolvePath $CsvPath) -HtmlPath (& $resolvePath $HtmlPath) -PdfPath (& $resolvePath $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $resources -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
