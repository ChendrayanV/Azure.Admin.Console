function ConvertTo-AACSentinelContentPackage {
    <#
    .SYNOPSIS
        Turns a workspace's Content hub packages - installed and in the
        catalog - their templates and its analytics rules into
        AAC.SentinelContentPackage objects, each with findings.
    .DESCRIPTION
        No Azure calls, so it can be tested with made-up data.

          -Installed     contentPackages (what is installed), hashtables
          -Catalog       contentProductPackages (every package Content hub
                         offers, with the version installed, if any)
          -Template      contentTemplates (the templates installed packages
                         brought: analytics rules, workbooks, hunting
                         queries, playbooks, parsers, data connectors...)
          -Rule          the analytics rules, to tell which analytics
                         templates a rule was created from

        A package is matched to the catalog by its contentId. Findings: an
        update is available, the package is deprecated, and none of its
        analytics rule templates has a rule - installed, but detecting nothing.
        -IncludeAvailable adds the catalog packages that aren't installed.
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelContentPackage')]
    param(
        [AllowEmptyCollection()]
        [object[]] $Installed = @(),

        [AllowEmptyCollection()]
        [object[]] $Catalog = @(),

        [AllowEmptyCollection()]
        [object[]] $Template = @(),

        [AllowEmptyCollection()]
        [object[]] $Rule = @(),

        [switch] $IncludeAvailable
    )

    $inv = [cultureinfo]::InvariantCulture
    $get = {
        param($Object, [string[]] $Path)
        $value = $Object
        foreach ($key in $Path) {
            if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($key)) { return $null }
            $value = $value[$key]
        }
        $value
    }
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $parsed = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $parsed }
        $null
    }
    $isTrue = { param($Value) $Value -eq $true -or [string]$Value -eq 'true' }
    $isNewer = {
        param([string] $Latest, [string] $Current)
        $latestVersion = $null; $currentVersion = $null
        [version]::TryParse($Latest, [ref]$latestVersion) -and [version]::TryParse($Current, [ref]$currentVersion) -and $latestVersion -gt $currentVersion
    }
    $key = { param([string] $Id) if ($Id) { $Id.ToLowerInvariant() } else { '' } }

    $catalogById = @{}
    foreach ($item in @($Catalog | Where-Object { $null -ne $_ })) {
        $id = & $key ([string](& $get $item 'properties', 'contentId'))
        if ($id) { $catalogById[$id] = $item }
    }
    # The rules each analytics template was used for, and whether they are on.
    $rulesByTemplate = @{}
    foreach ($item in @($Rule | Where-Object { $null -ne $_ })) {
        $templateId = & $key ([string](& $get $item 'properties', 'alertRuleTemplateName'))
        if (-not $templateId) { continue }
        if (-not $rulesByTemplate.Contains($templateId)) { $rulesByTemplate[$templateId] = @{ Total = 0; Enabled = 0 } }
        $rulesByTemplate[$templateId].Total++
        if (& $get $item 'properties', 'enabled') { $rulesByTemplate[$templateId].Enabled++ }
    }
    $templatesByPackage = @{}
    foreach ($item in @($Template | Where-Object { $null -ne $_ })) {
        $packageId = & $key ([string](& $get $item 'properties', 'packageId'))
        if (-not $packageId) { continue }
        if (-not $templatesByPackage.Contains($packageId)) { $templatesByPackage[$packageId] = [System.Collections.Generic.List[object]]::new() }
        $templatesByPackage[$packageId].Add($item)
    }

    $row = {
        param($Package, [bool] $IsInstalled)
        $properties = & $get $Package 'properties'
        $contentId = [string](& $get $properties 'contentId')
        $listing = $catalogById[(& $key $contentId)]
        $installedVersion = if ($IsInstalled) { [string](& $get $properties 'version') } else { '' }
        $latestVersion = if ($listing) { [string](& $get $listing 'properties', 'version') } elseif ($IsInstalled) { $installedVersion } else { [string](& $get $properties 'version') }
        $deprecated = (& $isTrue (& $get $properties 'isDeprecated')) -or ($listing -and (& $isTrue (& $get $listing 'properties', 'isDeprecated')))
        $templates = @(if ($templatesByPackage.Contains((& $key $contentId))) { $templatesByPackage[(& $key $contentId)] })
        $ofKind = { param([string[]] $Kind) @($templates | Where-Object { $Kind -contains [string](& $get $_ 'properties', 'contentKind') }) }
        $analytics = @(& $ofKind 'AnalyticsRule')
        $rulesCreated = 0; $rulesEnabled = 0; $templatesUsed = 0
        foreach ($t in $analytics) {
            $used = $rulesByTemplate[(& $key ([string](& $get $t 'properties', 'contentId')))]
            if ($used) { $templatesUsed++; $rulesCreated += $used.Total; $rulesEnabled += $used.Enabled }
        }
        $update = $IsInstalled -and (& $isNewer $latestVersion $installedVersion)
        $findings = [System.Collections.Generic.List[string]]::new()
        if ($update) { $findings.Add("Update available ($installedVersion to $latestVersion)") }
        if ($deprecated) { $findings.Add('Deprecated') }
        if ($IsInstalled -and $analytics.Count -and -not $rulesEnabled) { $findings.Add("No enabled rule from its $($analytics.Count) analytics template(s)") }
        $known = 'AnalyticsRule', 'HuntingQuery', 'Workbook', 'Playbook', 'Parser', 'DataConnector', 'ResourcesDataConnector'
        [pscustomobject][ordered]@{
            PSTypeName             = 'AAC.SentinelContentPackage'
            Name                   = [string](& $get $properties 'displayName')
            State                  = $(if ($IsInstalled) { 'Installed' } else { 'Available' })
            Kind                   = [string](& $get $properties 'contentKind')
            Publisher              = [string](& $get $properties 'publisherDisplayName')
            Support                = [string](& $get $properties 'support', 'tier')
            InstalledVersion       = $installedVersion
            LatestVersion          = $latestVersion
            UpdateAvailable        = [bool]$update
            Deprecated             = [bool]$deprecated
            Preview                = [bool](& $isTrue (& $get $properties 'isPreview'))
            AnalyticsRuleTemplates = $analytics.Count
            TemplatesUsed          = $templatesUsed
            RulesCreated           = $rulesCreated
            RulesEnabled           = $rulesEnabled
            Workbooks              = @(& $ofKind 'Workbook').Count
            HuntingQueries         = @(& $ofKind 'HuntingQuery').Count
            Playbooks              = @(& $ofKind 'Playbook').Count
            Parsers                = @(& $ofKind 'Parser').Count
            DataConnectors         = @(& $ofKind 'DataConnector', 'ResourcesDataConnector').Count
            OtherTemplates         = @($templates | Where-Object { $known -notcontains [string](& $get $_ 'properties', 'contentKind') }).Count
            Findings               = $findings -join '; '
            Domains                = @(& $get $properties 'categories', 'domains' | Where-Object { $_ }) -join ', '
            LastPublished          = & $date $(if ($listing) { & $get $listing 'properties', 'lastPublishDate' } else { & $get $properties 'lastPublishDate' })
            ContentId              = $contentId
        }
    }

    $installedIds = @{}
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @($Installed | Where-Object { $null -ne $_ })) {
        $installedIds[(& $key ([string](& $get $item 'properties', 'contentId')))] = $true
        $result.Add((& $row $item $true))
    }
    if ($IncludeAvailable) {
        foreach ($id in $catalogById.Keys) {
            if ($installedIds.Contains($id)) { continue }
            # The catalog knows what is installed too: trust the installed list above.
            $result.Add((& $row $catalogById[$id] $false))
        }
    }
    @($result | Sort-Object -Property @{ Expression = 'State'; Descending = $true }, @{ Expression = { [bool]$_.Findings }; Descending = $true }, 'Name')
}
