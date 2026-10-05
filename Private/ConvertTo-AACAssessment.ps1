function ConvertTo-AACAssessment {
    <#
    .SYNOPSIS
        Turns what Invoke-AACAssessment read into its sheets, overview and
        organization - the model behind the CSV, HTML, PDF and diagrams.
    .DESCRIPTION
        No Azure calls. Inputs:
          -Catalog / -Compiled   the sheets (Get-AACAssessmentCatalog) and
                                 their queries' columns (Get-AACAssessmentQuery)
          -SheetRow, -SheetError each sheet's Resource Graph rows, or why it
                                 couldn't be read
          -Resource              every resource (id, name, type, kind,
                                 location, resourceGroup, subscriptionId, sku,
                                 state, tags)
          -Subscription, -ResourceGroup, -ManagementGroup   the containers
          -Advisor               Advisor recommendations (with retirements)
          -Security, -SecureScore  Defender for Cloud (unhealthy assessments)
          -Policy                policy states summed per assignment and policy
          -SupportTicket         support tickets
          -Arm                   @{ AdvisorScore; Reservation; Outage (subscription
                                 -> items); Quota ('sub|location' -> items); Sku
                                 (location -> items) }
          -Cost                  Read-AACInventoryCost's result, or $null

        Each sheet: @{ Id; Category; Sheet; Columns (labels in order);
        Types (label -> number/date/text); Key; Rows (pscustomobjects with
        those labels, and ResourceId); Error; Kind ('Overview', 'Inventory',
        'Advisor', 'Security', 'Policy', 'Health', 'Cost') }.

        Inventory sheets also get, after their own columns: Retirement (an
        Advisor retirement notice for the resource), Advisor (its number of
        recommendations), the cost (month to date, last month, currency)
        with -Cost, and Tags with -IncludeTag.

        Returns @{ Sheets; Stats; Tree (for the HTML report);
        Organization (management groups, subscriptions, resource groups,
        for the organization diagram); Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Catalog,
        [hashtable] $Compiled = @{},
        [hashtable] $SheetRow = @{},
        [hashtable] $SheetError = @{},
        [AllowEmptyCollection()] [object[]] $Resource = @(),
        [AllowEmptyCollection()] [object[]] $Subscription = @(),
        [AllowEmptyCollection()] [object[]] $ResourceGroup = @(),
        [AllowEmptyCollection()] [object[]] $ManagementGroup = @(),
        [AllowEmptyCollection()] [object[]] $Advisor = @(),
        [AllowEmptyCollection()] [object[]] $Security = @(),
        [AllowEmptyCollection()] [object[]] $SecureScore = @(),
        [AllowEmptyCollection()] [object[]] $Policy = @(),
        [AllowEmptyCollection()] [object[]] $SupportTicket = @(),
        [hashtable] $Arm = @{},
        [hashtable] $Cost,
        [string] $TenantId = '',
        [string] $TenantName = '',
        [switch] $IncludeTag,
        [switch] $AdvisorRead,
        [switch] $SecurityRead,
        [switch] $PolicyRead,
        [datetime] $Now = (Get-Date)
    )

    # --- Helpers ---------------------------------------------------------------------------------------------------
    $lower = { param($Value) ([string]$Value).ToLowerInvariant() }
    $value = { param($Row, [string] $Key) if ($Row -is [System.Collections.IDictionary]) { if ($Row.Contains($Key)) { $Row[$Key] } } elseif ($null -ne $Row) { Get-AACPropertyValue -InputObject $Row -Name $Key } }
    $at = {
        # A dotted path into nested hashtables (a.b.c); $null where a level is missing.
        param($Item, [string] $Path)
        foreach ($part in ($Path -split '\.')) {
            if ($Item -is [System.Collections.IDictionary]) { $Item = if ($Item.Contains($part)) { $Item[$part] } else { $null } }
            elseif ($null -ne $Item -and $Item -isnot [string] -and $Item -isnot [ValueType] -and $Item -isnot [System.Collections.IEnumerable]) { $Item = Get-AACPropertyValue -InputObject $Item -Name $part }
            else { return $null }
        }
        $Item
    }
    $leaf = { param($Id) if ($Id) { ([string]$Id).TrimEnd('/') -replace '^.*/', '' } else { '' } }
    $text = {
        # What a cell shows: true/false as Yes/No, an ISO date as yyyy-MM-dd HH:mm.
        param($Item, [bool] $IsDate)
        if ($null -eq $Item) { return '' }
        if ($Item -is [bool]) { return $(if ($Item) { 'Yes' } else { 'No' }) }
        if ($Item -is [datetime]) { return $Item.ToUniversalTime().ToString('yyyy-MM-dd HH:mm') }
        if ($Item -is [ValueType]) { return $Item }
        $string = [string]$Item
        if ($string -ceq 'true' -or $string -ceq 'True') { return 'Yes' }
        if ($string -ceq 'false' -or $string -ceq 'False') { return 'No' }
        if ($IsDate -and $string -match '^\d{4}-\d{2}-\d{2}$') { return $string }
        if ($IsDate -and $string) {
            $date = [datetime]::MinValue
            if ([datetime]::TryParse($string, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) { return $date.ToString('yyyy-MM-dd HH:mm') }
        }
        $string
    }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ } }
    $subnetOf = { param([string] $Id) if ($Id -match '(?i)/virtualnetworks/([^/]+)/subnets/([^/]+)') { "$($Matches[1])/$($Matches[2])" } else { & $leaf $Id } }
    $transform = {
        # The '@' column specs: an array (or object) Resource Graph returned as is.
        param([string] $Spec, $Raw)
        $kind = ($Spec -replace '^@([a-z]+):.*$', '$1')
        $sub = if ($Spec -match '\|(.+)$') { $Matches[1] } else { '' }
        $items = @(& $list $Raw)
        switch ($kind) {
            'names' { (@($items | ForEach-Object { [string](& $at $_ 'name') } | Where-Object { $_ })) -join ', ' }
            'leafs' { (@($items | ForEach-Object { & $leaf $(if ($_ -is [string]) { $_ } else { & $at $_ 'id' }) } | Where-Object { $_ })) -join ', ' }
            'subnets' { (@($items | ForEach-Object { & $subnetOf $(if ($_ -is [string]) { $_ } else { [string](& $at $_ 'id') }) } | Where-Object { $_ })) -join ', ' }
            'pick' { (@($items | ForEach-Object { & $list (& $at $_ $sub) } | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -Unique)) -join ', ' }
            'pickleaf' { (@($items | ForEach-Object { & $leaf (& $at $_ $sub) } | Where-Object { $_ } | Select-Object -Unique)) -join ', ' }
            'sum' { $total = 0.0; $any = $false; foreach ($item in $items) { $n = & $at $item $sub; if ($null -ne $n -and "$n" -ne '') { $total += [double]$n; $any = $true } }; if ($any) { [Math]::Round($total, 2) } else { $null } }
            'keys' { if ($Raw -is [System.Collections.IDictionary]) { (@($Raw.Keys | Sort-Object)) -join ', ' } else { '' } }
            default { [string]$Raw }
        }
    }
    $slug = { param([string] $Name) ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
    $round = { param($Number) if ($null -eq $Number) { $null } else { [Math]::Round([double]$Number, 2) } }

    # --- Lookups ------------------------------------------------------------------------------------------------
    $subscriptionNames = @{}
    foreach ($row in $Subscription) { $subscriptionNames[(& $lower (& $value $row 'subscriptionId'))] = [string](& $value $row 'name') }
    $subscriptionName = { param($Id) $key = & $lower $Id; if ($subscriptionNames.Contains($key)) { $subscriptionNames[$key] } else { [string]$Id } }
    $inScope = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $Resource) { [void]$inScope.Add([string](& $value $row 'id')) }
    $typeCategory = @{}
    $typeSheet = @{}
    foreach ($sheet in $Catalog) {
        foreach ($type in @($sheet.Type)) {
            $key = & $lower $type
            if (-not $typeCategory.Contains($key)) { $typeCategory[$key] = $sheet.Category; $typeSheet[$key] = $sheet.Sheet }
        }
    }
    $categoryOf = {
        param([string] $Type)
        $key = & $lower $Type
        if ($typeCategory.Contains($key)) { return $typeCategory[$key] }
        $provider = ($key -split '/')[0]
        switch -Wildcard ($provider) {
            'microsoft.network' { 'Networking' } 'microsoft.compute' { 'Compute' } 'microsoft.storage*' { 'Storage' } 'microsoft.web' { 'Web' }
            'microsoft.sql' { 'Databases' } 'microsoft.dbfor*' { 'Databases' } 'microsoft.insights' { 'Monitoring' } 'microsoft.operationalinsights' { 'Monitoring' }
            'microsoft.operationsmanagement' { 'Monitoring' } 'microsoft.alertsmanagement' { 'Monitoring' } 'microsoft.keyvault' { 'Security' } 'microsoft.security' { 'Security' }
            'microsoft.containerservice' { 'Containers' } 'microsoft.app' { 'Containers' } 'microsoft.logic' { 'Integration' } 'microsoft.eventgrid' { 'Integration' }
            'microsoft.automation' { 'Management' } 'microsoft.recoveryservices' { 'Management' } 'microsoft.managedidentity' { 'Management' }
            'microsoft.cognitiveservices' { 'AI' } 'microsoft.machinelearningservices' { 'AI' } 'microsoft.hybridcompute' { 'Hybrid' } 'microsoft.devices' { 'IoT' }
            default { 'Other' }
        }
    }

    # Retirements and Advisor counts per resource.
    $retirements = @{}
    $advisorCount = @{}
    foreach ($row in $Advisor) {
        $id = & $lower (& $value $row 'resourceId')
        if (-not $id) { continue }
        if ([string](& $value $row 'subCategory') -ne 'ServiceUpgradeAndRetirement') { $advisorCount[$id] = 1 + $(if ($advisorCount.Contains($id)) { $advisorCount[$id] } else { 0 }) }
        else {
            $notice = @((& $value $row 'retirementFeature'), (& $value $row 'problem')) | Where-Object { $_ } | Select-Object -First 1
            $date = [string](& $value $row 'retirementDate')
            $entry = "$notice$(if ($date) { " ($(& $text $date $true))" })"
            if (-not $retirements.Contains($id)) { $retirements[$id] = [System.Collections.Generic.List[string]]::new() }
            if (-not $retirements[$id].Contains($entry)) { $retirements[$id].Add($entry) }
        }
    }

    # Cost per resource: month to date, last month.
    $costs = @{}
    $currencies = [System.Collections.Generic.HashSet[string]]::new()
    if ($Cost) {
        foreach ($row in @($Cost.Rows)) {
            $id = & $lower (& $value $row 'ResourceId')
            if (-not $id) { continue }
            $month = & $value $row 'BillingMonth'
            $monthKey = if ($month -is [datetime]) { $month.ToString('yyyy-MM') } elseif ([string]$month -match '^(\d{4})-?(\d{2})') { "$($Matches[1])-$($Matches[2])" } else { '' }
            if (-not $costs.Contains($id)) { $costs[$id] = @{ ThisMonth = 0.0; LastMonth = 0.0; Currency = '' } }
            $amount = [double](& $value $row 'Cost')
            if ($monthKey -eq $Cost.ThisMonth) { $costs[$id].ThisMonth += $amount } elseif ($monthKey -eq $Cost.LastMonth) { $costs[$id].LastMonth += $amount }
            $currency = [string](& $value $row 'Currency')
            if ($currency) { $costs[$id].Currency = $currency; [void]$currencies.Add($currency) }
        }
    }
    $hasCost = $null -ne $Cost

    # Compute SKUs: location -> size -> vCPUs and memory.
    $skus = @{}
    if ($Arm.Contains('Sku')) {
        foreach ($location in $Arm.Sku.Keys) {
            $sizes = @{}
            foreach ($sku in @($Arm.Sku[$location])) {
                if ([string](& $value $sku 'resourceType') -ne 'virtualMachines') { continue }
                $capabilities = @{}
                foreach ($capability in @(& $value $sku 'capabilities')) { $capabilities[[string](& $value $capability 'name')] = & $value $capability 'value' }
                $sizes[(& $lower (& $value $sku 'name'))] = @{ Cpu = $(if ($capabilities.Contains('vCPUs')) { [int]$capabilities['vCPUs'] }); Memory = $(if ($capabilities.Contains('MemoryGB')) { [double]$capabilities['MemoryGB'] }) }
            }
            $skus[(& $lower $location)] = $sizes
        }
    }

    # The columns every inventory sheet adds after its own.
    $tagText = {
        param($Tags)
        if ($Tags -is [System.Collections.IDictionary] -and $Tags.Count) { (@($Tags.Keys | Sort-Object | ForEach-Object { "$_=$($Tags[$_])" })) -join '; ' } else { '' }
    }
    $addCommon = {
        param([System.Collections.IDictionary] $Out, [string] $Id, $Tags)
        $key = & $lower $Id
        $Out['Retirement'] = if ($retirements.Contains($key)) { $retirements[$key] -join '; ' } else { '' }
        if ($AdvisorRead) { $Out['Advisor'] = if ($advisorCount.Contains($key)) { [int]$advisorCount[$key] } else { 0 } }
        if ($hasCost) {
            $entry = if ($costs.Contains($key)) { $costs[$key] } else { $null }
            $Out['Cost (month to date)'] = if ($entry) { & $round $entry.ThisMonth } else { $null }
            $Out['Cost (last month)'] = if ($entry) { & $round $entry.LastMonth } else { $null }
            $Out['Currency'] = if ($entry) { $entry.Currency } else { '' }
        }
        if ($IncludeTag) { $Out['Tags'] = & $tagText $Tags }
        $Out['ResourceId'] = $Id
    }
    $commonTypes = [ordered]@{ 'Retirement' = 'text' }
    if ($AdvisorRead) { $commonTypes['Advisor'] = 'number' }
    if ($hasCost) { $commonTypes['Cost (month to date)'] = 'money'; $commonTypes['Cost (last month)'] = 'money'; $commonTypes['Currency'] = 'text' }
    if ($IncludeTag) { $commonTypes['Tags'] = 'wide' }

    $sheets = [System.Collections.Generic.List[hashtable]]::new()
    $newSheet = {
        param([string] $Kind, [string] $Category, [string] $Name, [System.Collections.IDictionary] $Types, [object[]] $Rows, [string[]] $Key, [string] $Failure, [string] $Note)
        @{ Id = & $slug $Name; Kind = $Kind; Category = $Category; Sheet = $Name; Columns = @($Types.Keys); Types = $Types; Rows = @($Rows); Key = @($Key); Error = $Failure; Note = $Note }
    }

    # --- The inventory sheets -------------------------------------------------------------------------------------
    $inventory = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($sheet in $Catalog) {
        $name = $sheet.Sheet
        $sheetQuery = if ($Compiled.Contains($name)) { $Compiled[$name] } else { @{ Columns = [ordered]@{} } }
        $rows = @(if ($SheetRow.Contains($name)) { $SheetRow[$name] })
        $failure = if ($SheetError.Contains($name)) { [string]$SheetError[$name] } else { '' }
        if (-not $rows.Count -and -not $failure) { continue }
        $nameLabel = if ($sheet.Contains('NameLabel') -and $sheet.NameLabel) { $sheet.NameLabel } else { 'Name' }
        $types = [ordered]@{ 'Subscription' = 'text'; 'Resource group' = 'text'; $nameLabel = 'resource'; 'Location' = 'text' }
        foreach ($label in $sheet.Columns.Keys) {
            $spec = [string]$sheet.Columns[$label]
            $types[$label] = if ($spec -match '^(int|num|gb|len):' -or $spec -match '^@sum:' -or $spec -match '^x:(vmCpu|vmMemory|subnetUsable|subnetFree)$') { 'number' } else { 'text' }
        }
        foreach ($label in $commonTypes.Keys) { $types[$label] = $commonTypes[$label] }
        $expands = $sheet.Contains('Pre') -and [string]$sheet.Pre -match 'mv-expand'
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $out = foreach ($row in $rows) {
            $id = [string](& $value $row 'id')
            # A tag value filter can match a resource more than once.
            if (-not $expands -and -not $seen.Add($id)) { continue }
            $item = [ordered]@{
                'Subscription'   = & $subscriptionName (& $value $row 'subscriptionId')
                'Resource group' = [string](& $value $row 'resourceGroup')
                $nameLabel       = [string](& $value $row 'name')
                'Location'       = [string](& $value $row 'location')
            }
            foreach ($label in $sheet.Columns.Keys) {
                $spec = [string]$sheet.Columns[$label]
                $column = if ($sheetQuery.Columns.Contains($label)) { $sheetQuery.Columns[$label].Column } else { '' }
                $item[$label] = if ($spec -like '@*') { & $transform $spec (& $value $row $column) }
                elseif ($spec -like 'x:*') { $null }
                elseif ($column) { & $text (& $value $row $column) ($spec -like 'date:*') }
                else { '' }
            }
            # Filled in after the query.
            foreach ($label in @($sheet.Columns.Keys)) {
                switch ([string]$sheet.Columns[$label]) {
                    'x:vmCpu' { $size = $skus[(& $lower $item['Location'])]; if ($size -and $size.Contains((& $lower $item['Size']))) { $item[$label] = $size[(& $lower $item['Size'])].Cpu } }
                    'x:vmMemory' { $size = $skus[(& $lower $item['Location'])]; if ($size -and $size.Contains((& $lower $item['Size']))) { $item[$label] = $size[(& $lower $item['Size'])].Memory } }
                    'x:subnetUsable' {
                        $usable = 0; $any = $false
                        foreach ($prefix in ([string]$item['Prefix'] -split ',\s*' | Where-Object { $_ })) { $range = ConvertTo-AACCidrRange $prefix; if ($range.Version -eq 4 -and $range.Valid) { $usable += [Math]::Max(0, $range.Size - 5); $any = $true } }
                        $item[$label] = if ($any) { $usable } else { $null }
                    }
                    'x:subnetFree' { $usableLabel = @($sheet.Columns.Keys | Where-Object { $sheet.Columns[$_] -eq 'x:subnetUsable' })[0]; if ($null -ne $item[$usableLabel]) { $item[$label] = [Math]::Max(0, [int]$item[$usableLabel] - [int]$item['IP configurations']) } }
                }
            }
            & $addCommon $item $id (& $value $row 'tags')
            [pscustomobject]$item
        }
        $inventory.Add((& $newSheet 'Inventory' $sheet.Category $name $types @($out) (@('Subscription', 'Resource group', $nameLabel) + @($sheet.Key)) $failure ''))
    }

    # --- Overview: subscriptions, resource groups, resource types, every resource -----------------------------------
    $bySubscription = @{}
    $byGroup = @{}
    foreach ($row in $Resource) {
        $sub = & $lower (& $value $row 'subscriptionId')
        $group = "$sub|$(& $lower (& $value $row 'resourceGroup'))"
        if (-not $bySubscription.Contains($sub)) { $bySubscription[$sub] = @{ Resources = 0; Types = [System.Collections.Generic.HashSet[string]]::new(); Locations = [System.Collections.Generic.HashSet[string]]::new(); Cost = 0.0; LastCost = 0.0 } }
        $bySubscription[$sub].Resources++
        [void]$bySubscription[$sub].Types.Add((& $lower (& $value $row 'type')))
        $location = & $lower (& $value $row 'location')
        if ($location) { [void]$bySubscription[$sub].Locations.Add($location) }
        $byGroup[$group] = 1 + $(if ($byGroup.Contains($group)) { $byGroup[$group] } else { 0 })
    }
    foreach ($id in $costs.Keys) {
        $sub = if ($id -match '^/subscriptions/([^/]+)') { $Matches[1] } else { '' }
        if ($sub -and $bySubscription.Contains($sub)) { $bySubscription[$sub].Cost += $costs[$id].ThisMonth; $bySubscription[$sub].LastCost += $costs[$id].LastMonth }
    }
    $groupNames = @{}
    foreach ($row in $ManagementGroup) { $groupNames[(& $lower (& $value $row 'name'))] = [string]$(if (& $value $row 'displayName') { & $value $row 'displayName' } else { & $value $row 'name' }) }
    $scores = @{}
    foreach ($row in $SecureScore) { $max = [double](& $value $row 'max'); if ($max) { $scores[(& $lower (& $value $row 'subscriptionId'))] = [Math]::Round([double](& $value $row 'current') / $max * 100, 1) } }
    $advisorBySubscription = @{}
    foreach ($row in $Advisor) {
        # Retirements have a sheet of their own, as in the Advisor sheet.
        if ([string](& $value $row 'subCategory') -eq 'ServiceUpgradeAndRetirement') { continue }
        $sub = & $lower (& $value $row 'subscriptionId')
        if (-not $advisorBySubscription.Contains($sub)) { $advisorBySubscription[$sub] = @{ All = 0; High = 0 } }
        $advisorBySubscription[$sub].All++
        if ([string](& $value $row 'impact') -eq 'High') { $advisorBySubscription[$sub].High++ }
    }
    $groupCount = @{}
    foreach ($row in $ResourceGroup) { $sub = & $lower (& $value $row 'subscriptionId'); $groupCount[$sub] = 1 + $(if ($groupCount.Contains($sub)) { $groupCount[$sub] } else { 0 }) }
    $mgPath = {
        param($Row)
        # The chain runs from the subscription's parent up to the root: root first.
        $names = @(@(& $list (& $value $Row 'chain')) | ForEach-Object { [string]$(if (& $at $_ 'displayName') { & $at $_ 'displayName' } else { & $at $_ 'name' }) } | Where-Object { $_ })
        if (-not $names.Count) { return '' }
        [array]::Reverse($names)
        $names -join ' > '
    }
    $subscriptionTypes = [ordered]@{ 'Subscription' = 'text'; 'Subscription ID' = 'mono'; 'State' = 'badge'; 'Offer' = 'text'; 'Management groups' = 'text'; 'Resource groups' = 'number'; 'Resources' = 'number'; 'Resource types' = 'number'; 'Locations' = 'number' }
    if ($AdvisorRead) { $subscriptionTypes['Advisor'] = 'number'; $subscriptionTypes['Advisor (High)'] = 'number' }
    if ($SecurityRead) { $subscriptionTypes['Secure score (%)'] = 'score' }
    if ($hasCost) { $subscriptionTypes['Cost (month to date)'] = 'money'; $subscriptionTypes['Cost (last month)'] = 'money'; $subscriptionTypes['Cost status'] = 'text' }
    $subscriptionRows = foreach ($row in $Subscription | Sort-Object { [string](& $value $_ 'name') }) {
        $id = & $lower (& $value $row 'subscriptionId')
        $counts = if ($bySubscription.Contains($id)) { $bySubscription[$id] } else { @{ Resources = 0; Types = @(); Locations = @(); Cost = 0.0; LastCost = 0.0 } }
        $item = [ordered]@{
            'Subscription' = [string](& $value $row 'name'); 'Subscription ID' = [string](& $value $row 'subscriptionId'); 'State' = [string](& $value $row 'state')
            'Offer' = [string](& $value $row 'quotaId'); 'Management groups' = & $mgPath $row
            'Resource groups' = $(if ($groupCount.Contains($id)) { $groupCount[$id] } else { 0 }); 'Resources' = $counts.Resources; 'Resource types' = @($counts.Types).Count; 'Locations' = @($counts.Locations).Count
        }
        if ($AdvisorRead) { $item['Advisor'] = $(if ($advisorBySubscription.Contains($id)) { $advisorBySubscription[$id].All } else { 0 }); $item['Advisor (High)'] = $(if ($advisorBySubscription.Contains($id)) { $advisorBySubscription[$id].High } else { 0 }) }
        if ($SecurityRead) { $item['Secure score (%)'] = $(if ($scores.Contains($id)) { $scores[$id] } else { $null }) }
        if ($hasCost) {
            $item['Cost (month to date)'] = & $round $counts.Cost; $item['Cost (last month)'] = & $round $counts.LastCost
            $item['Cost status'] = $(if ($Cost['Status'] -and $Cost['Status'].Contains($id)) { [string]$Cost['Status'][$id] } else { '' })
        }
        $item['ResourceId'] = "/subscriptions/$(& $value $row 'subscriptionId')"
        [pscustomobject]$item
    }
    $sheets.Add((& $newSheet 'Overview' 'Overview' 'Subscriptions' $subscriptionTypes @($subscriptionRows) @('Subscription', 'State', 'Resource groups', 'Resources', 'Locations') '' ''))

    $groupRows = foreach ($row in $ResourceGroup | Sort-Object { & $subscriptionName (& $value $_ 'subscriptionId') }, { [string](& $value $_ 'name') }) {
        $key = "$(& $lower (& $value $row 'subscriptionId'))|$(& $lower (& $value $row 'name'))"
        $count = if ($byGroup.Contains($key)) { $byGroup[$key] } else { 0 }
        [pscustomobject][ordered]@{
            'Subscription' = & $subscriptionName (& $value $row 'subscriptionId'); 'Resource group' = [string](& $value $row 'name'); 'Location' = [string](& $value $row 'location')
            'Resources' = $count; 'Empty' = $(if ($count) { 'No' } else { 'Yes' }); 'Tags' = & $tagText (& $value $row 'tags'); 'ResourceId' = [string](& $value $row 'id')
        }
    }
    $sheets.Add((& $newSheet 'Overview' 'Overview' 'Resource groups' ([ordered]@{ 'Subscription' = 'text'; 'Resource group' = 'resource'; 'Location' = 'text'; 'Resources' = 'number'; 'Empty' = 'badge'; 'Tags' = 'wide' }) @($groupRows) @('Subscription', 'Resource group', 'Location', 'Resources', 'Empty') '' ''))

    $typeRows = foreach ($group in $Resource | Group-Object { & $lower (& $value $_ 'type') } | Sort-Object Count -Descending) {
        [pscustomobject][ordered]@{
            'Category' = & $categoryOf $group.Name; 'Resource type' = $group.Name; 'Resources' = $group.Count
            'Subscriptions' = @($group.Group | ForEach-Object { & $value $_ 'subscriptionId' } | Select-Object -Unique).Count
            'Locations' = (@($group.Group | ForEach-Object { [string](& $value $_ 'location') } | Where-Object { $_ } | Select-Object -Unique | Sort-Object)) -join ', '
            'Sheet' = $(if ($typeSheet.Contains($group.Name)) { $typeSheet[$group.Name] } else { '' })
        }
    }
    $sheets.Add((& $newSheet 'Overview' 'Overview' 'Resource types' ([ordered]@{ 'Category' = 'text'; 'Resource type' = 'mono'; 'Resources' = 'number'; 'Subscriptions' = 'number'; 'Locations' = 'wide'; 'Sheet' = 'text' }) @($typeRows) @('Category', 'Resource type', 'Resources', 'Subscriptions') '' ''))

    $allTypes = [ordered]@{ 'Subscription' = 'text'; 'Resource group' = 'text'; 'Name' = 'resource'; 'Type' = 'mono'; 'Category' = 'text'; 'Kind' = 'text'; 'Location' = 'text'; 'SKU' = 'text'; 'State' = 'text' }
    foreach ($label in $commonTypes.Keys) { if ($label -ne 'Tags') { $allTypes[$label] = $commonTypes[$label] } }
    $allTypes['Tagged'] = 'badge'
    $allTypes['Tags'] = 'wide'
    $allRows = foreach ($row in $Resource) {
        $item = [ordered]@{
            'Subscription' = & $subscriptionName (& $value $row 'subscriptionId'); 'Resource group' = [string](& $value $row 'resourceGroup'); 'Name' = [string](& $value $row 'name')
            'Type' = & $lower (& $value $row 'type'); 'Category' = & $categoryOf (& $value $row 'type'); 'Kind' = [string](& $value $row 'kind'); 'Location' = [string](& $value $row 'location')
            'SKU' = [string](& $value $row 'sku'); 'State' = [string](& $value $row 'state')
        }
        & $addCommon $item ([string](& $value $row 'id')) $null
        $item['Tags'] = & $tagText (& $value $row 'tags')
        $item['Tagged'] = if ($item['Tags']) { 'Yes' } else { 'No' }
        [pscustomobject]$item
    }
    $sheets.Add((& $newSheet 'Overview' 'Overview' 'All resources' $allTypes @($allRows) @('Subscription', 'Resource group', 'Name', 'Type', 'Location') '' ''))
    foreach ($sheet in $inventory) { $sheets.Add($sheet) }

    # --- Advisor -------------------------------------------------------------------------------------------------
    $scoped = { param($Id) -not $Id -or -not $inScope.Count -or $inScope.Contains([string]$Id) -or [string]$Id -notmatch '/providers/' }
    if ($AdvisorRead) {
        $advisorRows = foreach ($row in $Advisor | Where-Object { [string](& $value $_ 'subCategory') -ne 'ServiceUpgradeAndRetirement' -and (& $scoped (& $value $_ 'resourceId')) } | Sort-Object { @{ High = 0; Medium = 1; Low = 2 }[[string](& $value $_ 'impact')] }, { [string](& $value $_ 'category') }) {
            $resourceId = [string](& $value $row 'resourceId')
            [pscustomobject][ordered]@{
                'Impact' = [string](& $value $row 'impact'); 'Category' = [string](& $value $row 'category'); 'Problem' = [string](& $value $row 'problem'); 'Solution' = [string](& $value $row 'solution')
                'Resource' = $(if ($resourceId) { & $leaf $resourceId } else { [string](& $value $row 'impactedValue') }); 'Resource type' = [string](& $value $row 'impactedType')
                'Subscription' = & $subscriptionName (& $value $row 'subscriptionId'); 'Resource group' = [string](& $value $row 'resourceGroup')
                'Annual savings' = & $round (& $value $row 'savings'); 'Currency' = [string](& $value $row 'savingsCurrency'); 'Updated' = & $text (& $value $row 'lastUpdated') $true
                'ResourceId' = $resourceId
            }
        }
        $sheets.Add((& $newSheet 'Advisor' 'Advisor' 'Advisor recommendations' ([ordered]@{ 'Impact' = 'badge'; 'Category' = 'text'; 'Problem' = 'wide'; 'Solution' = 'wide'; 'Resource' = 'resource'; 'Resource type' = 'text'; 'Subscription' = 'text'; 'Resource group' = 'text'; 'Annual savings' = 'money'; 'Currency' = 'text'; 'Updated' = 'text' }) @($advisorRows) @('Impact', 'Category', 'Problem', 'Resource', 'Subscription') '' ''))
    }
    $retirementRows = foreach ($row in $Advisor | Where-Object { [string](& $value $_ 'subCategory') -eq 'ServiceUpgradeAndRetirement' -and (& $scoped (& $value $_ 'resourceId')) } | Sort-Object { [string](& $value $_ 'retirementDate') }) {
        $resourceId = [string](& $value $row 'resourceId')
        [pscustomobject][ordered]@{
            'Retirement date' = & $text (& $value $row 'retirementDate') $true; 'Retiring' = [string]$(@((& $value $row 'retirementFeature'), (& $value $row 'problem')) | Where-Object { $_ } | Select-Object -First 1)
            'Resource' = & $leaf $resourceId; 'Resource type' = [string](& $value $row 'impactedType'); 'Subscription' = & $subscriptionName (& $value $row 'subscriptionId')
            'Resource group' = [string](& $value $row 'resourceGroup'); 'What to do' = [string](& $value $row 'solution'); 'ResourceId' = $resourceId
        }
    }
    $sheets.Add((& $newSheet 'Advisor' 'Advisor' 'Retirements' ([ordered]@{ 'Retirement date' = 'text'; 'Retiring' = 'wide'; 'Resource' = 'resource'; 'Resource type' = 'text'; 'Subscription' = 'text'; 'Resource group' = 'text'; 'What to do' = 'wide' }) @($retirementRows) @('Retirement date', 'Retiring', 'Resource', 'Subscription') '' 'Services and features being retired that these resources use (Azure Advisor, service upgrade and retirement).'))
    if ($Arm.Contains('AdvisorScore')) {
        $scoreRows = foreach ($sub in $Arm.AdvisorScore.Keys) {
            foreach ($item in @($Arm.AdvisorScore[$sub])) {
                $last = & $at $item 'properties.lastRefreshedScore'
                [pscustomobject][ordered]@{
                    'Subscription' = & $subscriptionName $sub; 'Category' = [string](& $value $item 'name'); 'Score (%)' = & $round (& $at $last 'score')
                    'Impacted resources' = & $at $last 'impactedResourceCount'; 'Potential increase' = & $round (& $at $last 'potentialScoreIncrease'); 'Refreshed' = & $text (& $at $last 'date') $true
                    'ResourceId' = "/subscriptions/$sub"
                }
            }
        }
        $sheets.Add((& $newSheet 'Advisor' 'Advisor' 'Advisor score' ([ordered]@{ 'Subscription' = 'text'; 'Category' = 'text'; 'Score (%)' = 'score'; 'Impacted resources' = 'number'; 'Potential increase' = 'number'; 'Refreshed' = 'text' }) @($scoreRows | Sort-Object Subscription, Category) @('Subscription', 'Category', 'Score (%)', 'Impacted resources') '' ''))
    }

    # --- Security ---------------------------------------------------------------------------------------------
    if ($SecurityRead) {
        $securityRows = foreach ($row in $Security | Where-Object { & $scoped (& $value $_ 'resourceId') } | Sort-Object { @{ High = 0; Medium = 1; Low = 2 }[[string](& $value $_ 'severity')] }, { [string](& $value $_ 'recommendation') }) {
            $resourceId = [string](& $value $row 'resourceId')
            [pscustomobject][ordered]@{
                'Severity' = [string](& $value $row 'severity'); 'Recommendation' = [string](& $value $row 'recommendation'); 'Resource' = & $leaf $resourceId
                'Resource type' = $(if ($resourceId -match '(?i)/providers/([^/]+/[^/]+)/[^/]+$') { $Matches[1].ToLowerInvariant() } else { '' })
                'Subscription' = & $subscriptionName (& $value $row 'subscriptionId'); 'Categories' = [string](& $value $row 'categories')
                'Remediation' = [string](& $value $row 'remediation'); 'Unhealthy since' = & $text (& $value $row 'since') $true; 'ResourceId' = $resourceId
            }
        }
        $sheets.Add((& $newSheet 'Security' 'Security' 'Security recommendations' ([ordered]@{ 'Severity' = 'badge'; 'Recommendation' = 'wide'; 'Resource' = 'resource'; 'Resource type' = 'text'; 'Subscription' = 'text'; 'Categories' = 'text'; 'Remediation' = 'wide'; 'Unhealthy since' = 'text' }) @($securityRows) @('Severity', 'Recommendation', 'Resource', 'Subscription') '' 'Defender for Cloud: the unhealthy assessments.'))
        $scoreRows = foreach ($row in $SecureScore) {
            $max = [double](& $value $row 'max')
            [pscustomobject][ordered]@{ 'Subscription' = & $subscriptionName (& $value $row 'subscriptionId'); 'Score' = & $round (& $value $row 'current'); 'Max' = & $round $max; 'Secure score (%)' = $(if ($max) { [Math]::Round([double](& $value $row 'current') / $max * 100, 1) } else { $null }); 'ResourceId' = "/subscriptions/$(& $value $row 'subscriptionId')" }
        }
        $sheets.Add((& $newSheet 'Security' 'Security' 'Secure score' ([ordered]@{ 'Subscription' = 'text'; 'Score' = 'number'; 'Max' = 'number'; 'Secure score (%)' = 'score' }) @($scoreRows | Sort-Object 'Secure score (%)') @('Subscription', 'Score', 'Max', 'Secure score (%)') '' ''))
    }

    # --- Policy ---------------------------------------------------------------------------------------------------
    if ($PolicyRead) {
        $policyRows = foreach ($row in $Policy) {
            $non = [int](& $value $row 'nonCompliant'); $ok = [int](& $value $row 'compliant')
            [pscustomobject][ordered]@{
                'Assignment' = [string]$(@((& $value $row 'assignment'), (& $value $row 'assignmentName')) | Where-Object { $_ } | Select-Object -First 1)
                'Policy' = [string]$(@((& $value $row 'policy'), (& $leaf (& $value $row 'definitionId'))) | Where-Object { $_ } | Select-Object -First 1)
                'Initiative' = [string]$(@((& $value $row 'policySet'), (& $leaf (& $value $row 'setId'))) | Where-Object { $_ } | Select-Object -First 1)
                'Effect' = [string](& $value $row 'effect'); 'Non-compliant' = $non; 'Compliant' = $ok; 'Exempt' = [int](& $value $row 'exempt'); 'Other' = [int](& $value $row 'other')
                'Compliance (%)' = $(if ($non + $ok) { [Math]::Round($ok / ($non + $ok) * 100, 1) } else { $null }); 'Subscriptions' = [int](& $value $row 'subscriptions')
                'Scope' = [string](& $value $row 'assignmentScope'); 'ResourceId' = [string](& $value $row 'assignmentId')
            }
        }
        $sheets.Add((& $newSheet 'Policy' 'Policy' 'Policy compliance' ([ordered]@{ 'Assignment' = 'text'; 'Policy' = 'wide'; 'Initiative' = 'text'; 'Effect' = 'badge'; 'Non-compliant' = 'number'; 'Compliant' = 'number'; 'Exempt' = 'number'; 'Other' = 'number'; 'Compliance (%)' = 'score'; 'Subscriptions' = 'number'; 'Scope' = 'mono' }) @($policyRows | Sort-Object -Property @{ Expression = 'Non-compliant'; Descending = $true }, Assignment) @('Assignment', 'Policy', 'Effect', 'Non-compliant', 'Compliance (%)') '' 'Each policy of each assignment: the resources in each compliance state.'))
    }

    # --- Health: outages, quotas, support tickets -----------------------------------------------------------------------
    if ($Arm.Contains('Outage')) {
        $events = @{}
        foreach ($sub in $Arm.Outage.Keys) {
            foreach ($item in @($Arm.Outage[$sub])) {
                $p = & $value $item 'properties'
                if ([string](& $at $p 'eventType') -ne 'ServiceIssue') { continue }
                $key = [string](& $value $item 'name')
                if (-not $events.Contains($key)) { $events[$key] = @{ Item = $item; Subscriptions = [System.Collections.Generic.List[string]]::new() } }
                # Each subscription has its copy of the event: keep the fullest one.
                elseif (@($p.Keys).Count -gt @((& $value $events[$key].Item 'properties').Keys).Count) { $events[$key].Item = $item }
                $events[$key].Subscriptions.Add((& $subscriptionName $sub))
            }
        }
        $outageRows = foreach ($key in $events.Keys) {
            $p = & $value $events[$key].Item 'properties'
            $impacts = @(& $list (& $at $p 'impact'))
            $summary = ([string]$(@((& $at $p 'summary'), (& $at $p 'description')) | Where-Object { $_ } | Select-Object -First 1)) -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '\s+', ' '
            [pscustomobject][ordered]@{
                'Tracking ID' = $key; 'Title' = [string](& $at $p 'title'); 'Status' = [string](& $at $p 'status'); 'Level' = [string]$(@((& $at $p 'level'), (& $at $p 'eventLevel')) | Where-Object { $_ } | Select-Object -First 1)
                'Started' = & $text (& $at $p 'impactStartTime') $true; 'Mitigated' = & $text (& $at $p 'impactMitigationTime') $true; 'Last update' = & $text (& $at $p 'lastUpdateTime') $true
                'Services' = (@($impacts | ForEach-Object { [string](& $at $_ 'impactedService') } | Where-Object { $_ } | Select-Object -Unique)) -join ', '
                'Regions' = (@($impacts | ForEach-Object { & $list (& $at $_ 'impactedRegions') } | ForEach-Object { [string](& $at $_ 'impactedRegion') } | Where-Object { $_ } | Select-Object -Unique)) -join ', '
                'Subscriptions' = (@($events[$key].Subscriptions | Sort-Object -Unique)) -join ', '; 'Summary' = $summary.Trim(); 'ResourceId' = ''
            }
        }
        $sheets.Add((& $newSheet 'Health' 'Health' 'Outages' ([ordered]@{ 'Tracking ID' = 'mono'; 'Title' = 'wide'; 'Status' = 'badge'; 'Level' = 'text'; 'Started' = 'text'; 'Mitigated' = 'text'; 'Last update' = 'text'; 'Services' = 'wide'; 'Regions' = 'wide'; 'Subscriptions' = 'wide'; 'Summary' = 'wide' }) @($outageRows | Sort-Object Started -Descending) @('Tracking ID', 'Title', 'Status', 'Started', 'Services') '' 'Azure service issues that affected these subscriptions in the last 6 months (Resource Health).'))
    }
    if ($Arm.Contains('Quota')) {
        $quotaRows = foreach ($key in $Arm.Quota.Keys) {
            $sub, $location = $key -split '\|', 2
            foreach ($item in @($Arm.Quota[$key])) {
                $current = [double](& $value $item 'currentValue'); $limit = [double](& $value $item 'limit')
                if ($current -le 0) { continue }
                [pscustomobject][ordered]@{ 'Subscription' = & $subscriptionName $sub; 'Location' = $location; 'Quota' = [string](& $at $item 'name.localizedValue'); 'Used' = $current; 'Limit' = $limit; 'Used (%)' = $(if ($limit) { [Math]::Round($current / $limit * 100, 1) } else { $null }); 'ResourceId' = "/subscriptions/$sub" }
            }
        }
        $sheets.Add((& $newSheet 'Health' 'Health' 'Quotas' ([ordered]@{ 'Subscription' = 'text'; 'Location' = 'text'; 'Quota' = 'text'; 'Used' = 'number'; 'Limit' = 'number'; 'Used (%)' = 'number' }) @($quotaRows | Sort-Object -Property @{ Expression = 'Used (%)'; Descending = $true }) @('Subscription', 'Location', 'Quota', 'Used', 'Limit', 'Used (%)') '' 'Compute quotas in use, in the regions with virtual machines or scale sets.'))
    }
    if ($SupportTicket.Count) {
        $ticketRows = foreach ($row in $SupportTicket) {
            [pscustomobject][ordered]@{
                'Ticket' = [string](& $value $row 'ticketId'); 'Title' = [string](& $value $row 'ticketTitle'); 'Service' = [string](& $value $row 'service'); 'Severity' = [string](& $value $row 'severity')
                'Status' = [string](& $value $row 'status'); 'Support plan' = [string](& $value $row 'plan'); 'Created' = & $text (& $value $row 'created') $true; 'Modified' = & $text (& $value $row 'modified') $true
                'Subscription' = & $subscriptionName (& $value $row 'subscriptionId'); 'ResourceId' = [string](& $value $row 'id')
            }
        }
        $sheets.Add((& $newSheet 'Health' 'Health' 'Support tickets' ([ordered]@{ 'Ticket' = 'mono'; 'Title' = 'wide'; 'Service' = 'text'; 'Severity' = 'badge'; 'Status' = 'badge'; 'Support plan' = 'text'; 'Created' = 'text'; 'Modified' = 'text'; 'Subscription' = 'text' }) @($ticketRows | Sort-Object Created -Descending) @('Ticket', 'Title', 'Severity', 'Status', 'Created') '' ''))
    }

    # --- Cost: reservation recommendations ---------------------------------------------------------------------------
    if ($Arm.Contains('Reservation')) {
        $reservationRows = foreach ($sub in $Arm.Reservation.Keys) {
            foreach ($item in @($Arm.Reservation[$sub])) {
                $p = & $value $item 'properties'
                [pscustomobject][ordered]@{
                    'Subscription' = & $subscriptionName $sub; 'Location' = [string](& $value $item 'location'); 'Resource type' = [string](& $at $p 'resourceType')
                    'Size' = [string]$(@((& $at $p 'normalizedSize'), (& $at $p 'skuName'), (& $value $item 'sku')) | Where-Object { $_ } | Select-Object -First 1)
                    'Quantity' = & $round (& $at $p 'recommendedQuantity'); 'Term' = [string](& $at $p 'term'); 'Scope' = [string](& $at $p 'scope'); 'Look-back' = [string](& $at $p 'lookBackPeriod')
                    'Cost without' = & $round (& $at $p 'costWithNoReservedInstances'); 'Cost with' = & $round (& $at $p 'totalCostWithReservedInstances'); 'Net savings' = & $round (& $at $p 'netSavings')
                    'ResourceId' = "/subscriptions/$sub"
                }
            }
        }
        $sheets.Add((& $newSheet 'Cost' 'Cost' 'Reservation recommendations' ([ordered]@{ 'Subscription' = 'text'; 'Location' = 'text'; 'Resource type' = 'text'; 'Size' = 'text'; 'Quantity' = 'number'; 'Term' = 'text'; 'Scope' = 'text'; 'Look-back' = 'text'; 'Cost without' = 'money'; 'Cost with' = 'money'; 'Net savings' = 'money' }) @($reservationRows | Sort-Object -Property @{ Expression = 'Net savings'; Descending = $true }) @('Subscription', 'Resource type', 'Size', 'Quantity', 'Term', 'Net savings') '' 'Azure Consumption: reserved instances that would cost less than pay-as-you-go, from recent usage.'))
    }

    # --- Stats ---------------------------------------------------------------------------------------------------
    $sheetOf = { param([string] $Name) @($sheets | Where-Object Sheet -EQ $Name)[0] }
    $countWhere = {
        param([string] $Name, [scriptblock] $Filter)
        $found = @($sheets | Where-Object Sheet -EQ $Name)
        if ($found.Count) { @($found[0].Rows | Where-Object $Filter).Count } else { 0 }
    }
    $orphans = 0
    foreach ($sheet in $inventory) { foreach ($label in 'Orphaned', 'Empty') { if ($sheet.Columns -contains $label) { $orphans += @($sheet.Rows | Where-Object { $_.$label -eq 'Yes' }).Count } } }
    $orphans += & $countWhere 'Disks' { $_.State -eq 'Unattached' }
    $currency = if ($currencies.Count -eq 1) { @($currencies)[0] } elseif ($currencies.Count -gt 1) { 'mixed' } else { '' }
    $stats = [ordered]@{
        Subscriptions       = @($Subscription).Count
        ResourceGroups      = @($ResourceGroup).Count
        EmptyResourceGroups = & $countWhere 'Resource groups' { $_.Empty -eq 'Yes' }
        Resources           = @($Resource).Count
        ResourceTypes       = @($typeRows).Count
        Locations           = @($Resource | ForEach-Object { [string](& $value $_ 'location') } | Where-Object { $_ } | Select-Object -Unique).Count
        InventorySheets     = @($inventory | Where-Object { $_.Rows.Count }).Count
        FailedSheets        = @($inventory | Where-Object Error).Count
        Untagged            = @($Resource | Where-Object { $tags = & $value $_ 'tags'; -not ($tags -is [System.Collections.IDictionary] -and $tags.Count) }).Count
        Orphans             = $orphans
        AdvisorHigh         = & $countWhere 'Advisor recommendations' { $_.Impact -eq 'High' }
        Advisor             = $(if ($AdvisorRead) { @((& $sheetOf 'Advisor recommendations').Rows).Count } else { $null })
        Retirements         = @($retirementRows).Count
        SecurityHigh        = & $countWhere 'Security recommendations' { $_.Severity -eq 'High' }
        Security            = $(if ($SecurityRead) { @((& $sheetOf 'Security recommendations').Rows).Count } else { $null })
        PolicyNonCompliant  = [int](@($Policy | ForEach-Object { [int](& $value $_ 'nonCompliant') }) | Measure-Object -Sum).Sum
        Outages             = & $countWhere 'Outages' { $true }
        CostMonthToDate     = $(if ($hasCost -and $currency -ne 'mixed') { [Math]::Round((@($costs.Values | ForEach-Object { $_.ThisMonth }) | Measure-Object -Sum).Sum + 0, 2) } else { $null })
        CostLastMonth       = $(if ($hasCost -and $currency -ne 'mixed') { [Math]::Round((@($costs.Values | ForEach-Object { $_.LastMonth }) | Measure-Object -Sum).Sum + 0, 2) } else { $null })
        Currency            = $currency
    }

    # --- The organization: management groups > subscriptions > resource groups ---------------------------------------
    $mgRows = @($ManagementGroup)
    $children = @{}
    foreach ($row in $mgRows) {
        $parent = & $lower (& $value $row 'parent')
        if (-not $children.Contains($parent)) { $children[$parent] = [System.Collections.Generic.List[object]]::new() }
        $children[$parent].Add($row)
    }
    $subscriptionsUnder = @{}
    foreach ($row in $Subscription) {
        $chain = @(& $list (& $value $row 'chain'))
        $parent = if ($chain.Count) { & $lower (& $at $chain[0] 'name') } else { '' }
        if (-not $subscriptionsUnder.Contains($parent)) { $subscriptionsUnder[$parent] = [System.Collections.Generic.List[object]]::new() }
        $subscriptionsUnder[$parent].Add($row)
    }
    $groupsOf = @{}
    foreach ($row in $ResourceGroup) {
        $sub = & $lower (& $value $row 'subscriptionId')
        if (-not $groupsOf.Contains($sub)) { $groupsOf[$sub] = [System.Collections.Generic.List[object]]::new() }
        $groupsOf[$sub].Add($row)
    }
    $subscriptionNode = {
        param($Row)
        $id = & $lower (& $value $Row 'subscriptionId')
        $counts = if ($bySubscription.Contains($id)) { $bySubscription[$id].Resources } else { 0 }
        $name = [string](& $value $Row 'name')
        @{
            l = 's'; n = $name; d = [string](& $value $Row 'subscriptionId'); c = @(, @($counts, 'resources')); f = @{ table = 'all-resources'; filters = @{ Subscription = $name } }
            k = @(foreach ($group in @(if ($groupsOf.Contains($id)) { $groupsOf[$id] }) | Sort-Object { [string](& $value $_ 'name') }) {
                    $groupName = [string](& $value $group 'name')
                    $n = $(if ($byGroup.Contains("$id|$($groupName.ToLowerInvariant())")) { $byGroup["$id|$($groupName.ToLowerInvariant())"] } else { 0 })
                    @{ l = 'g'; n = $groupName; d = [string](& $value $group 'location'); c = @(, @($n, 'resources')); x = ($n -eq 0); f = @{ table = 'all-resources'; filters = @{ Subscription = $name; 'Resource group' = $groupName } } }
                })
        }
    }
    $mgNode = {
        param($Row, [int] $Depth)
        $key = & $lower (& $value $Row 'name')
        @{
            l = 'm'; n = [string]$(if (& $value $Row 'displayName') { & $value $Row 'displayName' } else { & $value $Row 'name' }); d = [string](& $value $Row 'name')
            k = @(
                if ($Depth -lt 12 -and $children.Contains($key)) { foreach ($child in $children[$key] | Sort-Object { [string](& $value $_ 'displayName') }) { & $mgNode $child ($Depth + 1) } }
                if ($subscriptionsUnder.Contains($key)) { foreach ($sub in $subscriptionsUnder[$key] | Sort-Object { [string](& $value $_ 'name') }) { & $subscriptionNode $sub } }
            )
        }
    }
    $mgNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $mgRows) { [void]$mgNames.Add([string](& $value $row 'name')) }
    $roots = @($mgRows | Where-Object { $parent = [string](& $value $_ 'parent'); -not $parent -or -not $mgNames.Contains($parent) })
    $orphanSubscriptions = @($Subscription | Where-Object { $chain = @(& $list (& $value $_ 'chain')); -not $chain.Count -or -not $mgNames.Contains([string](& $at $chain[0] 'name')) })
    $tree = @{
        l = 't'; n = $(if ($TenantName) { $TenantName } else { 'Tenant' }); d = $TenantId; c = @(@($stats.Subscriptions, 'subscriptions'), @($stats.Resources, 'resources'))
        k = @(
            foreach ($root in $roots) { & $mgNode $root 0 }
            foreach ($sub in $orphanSubscriptions | Sort-Object { [string](& $value $_ 'name') }) { & $subscriptionNode $sub }
        )
    }

    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($sheet in $inventory | Where-Object Error) { $notices.Add("$($sheet.Sheet) couldn't be read: $($sheet.Error)") }

    @{
        Sheets       = $sheets.ToArray()
        Stats        = $stats
        Tree         = $tree
        Organization = @{ ManagementGroup = $mgRows; Subscription = @($Subscription); ResourceGroup = @($ResourceGroup); ResourceCount = $byGroup; SubscriptionResources = $bySubscription }
        Notices      = $notices.ToArray()
    }
}
