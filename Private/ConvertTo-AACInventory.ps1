function ConvertTo-AACInventory {
    <#
    .SYNOPSIS
        Builds the tenant inventory tree - tenant > management groups >
        subscriptions > resource groups > resources - from Azure Resource
        Graph rows, with counts rolled up at every level.
    .DESCRIPTION
        Management groups are nested by their parent; a subscription goes
        under the management group it is directly in (the first of its
        managementGroupAncestorsChain); resource groups under their
        subscription; resources under their resource group. When the
        management groups can't be read (no permission on them), or a
        subscription's group isn't among those read, it goes straight under
        the tenant.

        Management groups with no subscription in the result are left out -
        unless they were asked for by name (-KeepManagementGroup), so an empty
        group asked for still shows.

        With -Security (Microsoft Defender for Cloud, from Resource Graph's
        securityresources), every node also has a security posture:
          - a resource: its secure score - the share of its assessed
            recommendations that are healthy - and its unhealthy findings by
            severity (High, Medium, Low), the worst of them (Severity) and
            the first few by name (TopFindings)
          - a resource group: the same, over its resources
          - a subscription: Defender's own secure score (current / max)
          - a management group and the tenant: their subscriptions' scores
            added up, as Defender does (sum of current / sum of max)
        Rating: Good (70% or more), Fair (40-69%), Poor (under 40%).

        With -Cost (Cost Management rows by ResourceId and SubscriptionId,
        monthly), every node also has its actual cost month to date and last
        month (CostMonthToDate, CostLastMonth) and its Currency:
          - a resource: its own cost; a cost row for a child resource (a
            database of a server, say) goes to the closest resource above it
          - costs of resources no longer in Azure, and charges not tied to a
            resource, go to a 'Deleted resources' line under their
            subscription (Level DeletedResources)
          - every level above: its children's costs added up - in their one
            currency; never converted, so a node whose children are billed
            in different currencies has Currency 'mixed' and no total
          - a subscription whose cost couldn't be read says why (CostStatus)
        With -ResourceGroupName in effect (FilterGroups), cost rows outside
        the resource groups read are left out.

        Returns a hashtable:
          Root   the tenant node; every node is a hashtable with Level, Id,
                 Name, DisplayName, Detail, Children and the rolled-up counts
                 ManagementGroups, Subscriptions, ResourceGroups, Resources
          Items  every node, flattened in tree order, as AAC.InventoryItem
                 objects (Level, Depth, Name, Path, Type, Location, ...)
          Stats  the totals
          Controls, Recommendations  (with -Security) Defender's security
                 controls per subscription, with the potential score increase
                 of fixing each, and every unhealthy recommendation with the
                 resource it is on
        TopSpend (with -Cost) the resources that cost the most this month
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $TenantId,

        [string] $TenantName,

        # Rows: id, name, displayName, parentId.
        [AllowEmptyCollection()]
        [object[]] $ManagementGroup = @(),

        # Rows: subscriptionId, name, state, parentGroup (a management group name), tags.
        [AllowEmptyCollection()]
        [object[]] $Subscription = @(),

        # Rows: id, name, subscriptionId, location, state, managedBy, tags.
        [AllowEmptyCollection()]
        [object[]] $ResourceGroup = @(),

        # Rows: id, name, type, kind, location, resourceGroup, subscriptionId, sku, zones, tags.
        [AllowEmptyCollection()]
        [object[]] $Resource = @(),

        [string[]] $KeepManagementGroup = @(),

        # Defender for Cloud rows: Scores (subscriptionId, current, max),
        # Controls (subscriptionId, control, current, max, healthy,
        # unhealthy), Summary (resourceId, healthy, unhealthy, high, medium,
        # low) and Recommendations (resourceId, subscriptionId, name,
        # severity, impact, effort, categories, cause).
        [hashtable] $Security,

        # Cost Management: Rows (ResourceId, SubscriptionId, BillingMonth,
        # Cost, Currency), Status (subscription ID -> 'OK', 'No cost' or why
        # it couldn't be read), ThisMonth and LastMonth ('yyyy-MM'), and
        # FilterGroups (only rows in the resource groups read).
        [hashtable] $Cost
    )

    function Get-Value($Row, [string] $Key) {
        if ($Row -is [System.Collections.IDictionary]) {
            if ($Row.Contains($Key)) { return $Row[$Key] }
            foreach ($name in $Row.Keys) { if ($name -eq $Key) { return $Row[$name] } }
            return $null
        }
        Get-AACPropertyValue -InputObject $Row -Name $Key
    }
    $text = { param($Row, [string] $Key) $value = Get-Value $Row $Key; if ($null -eq $value) { '' } else { [string]$value } }
    $lower = { param([string] $Value) $Value.ToLowerInvariant() }
    $tagText = {
        param($Tags)
        if ($Tags -is [System.Collections.IDictionary]) { return (@($Tags.Keys | Sort-Object | ForEach-Object { "$_=$($Tags[$_])" }) -join '; ') }
        if ($Tags -and $Tags -isnot [string]) { return (@($Tags.PSObject.Properties | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; ') }
        ''
    }
    $newNode = {
        param([string] $Level, [string] $Id, [string] $Name, [string] $DisplayName)
        @{
            Level = $Level; Id = $Id; Name = $Name; DisplayName = $(if ($DisplayName) { $DisplayName } else { $Name })
            Children = [System.Collections.Generic.List[object]]::new(); Parent = $null
            ManagementGroups = 0; Subscriptions = 0; ResourceGroups = 0; Resources = 0
            Location = ''; State = ''; Type = ''; Kind = ''; Sku = ''; Tags = ''; SubscriptionId = ''; SubscriptionName = ''
            ResourceGroup = ''; ManagementGroup = ''; Zones = ''; TypeCounts = @{}; Visible = $true
            # Security posture (Defender for Cloud).
            SecureScore = $null; ScoreCurrent = 0.0; ScoreMax = 0.0; OfficialScore = $false
            Healthy = 0; Unhealthy = 0; High = 0; Medium = 0; Low = 0; Severity = ''; Rating = ''; TopFindings = ''
            # Cost (Cost Management).
            CostMonthToDate = 0.0; CostLastMonth = 0.0; Currency = ''; Currencies = @{}; CostStatus = ''; DeletedCount = 0
        }
    }

    # --- The tenant and its management groups ------------------------------------------------------
    $root = & $newNode 'Tenant' "/tenants/$TenantId" $TenantId $(if ($TenantName) { $TenantName } else { $TenantId })
    $groups = @{}
    foreach ($row in $ManagementGroup) {
        $name = & $text $row 'name'
        if (-not $name) { continue }
        $groups[(& $lower $name)] = & $newNode 'ManagementGroup' (& $text $row 'id') $name (& $text $row 'displayName')
        $groups[(& $lower $name)].ParentName = (& $text $row 'parentId') -replace '^.*/', ''
    }
    foreach ($key in @($groups.Keys)) {
        $group = $groups[$key]
        $parentKey = & $lower ([string]$group.ParentName)
        # The tenant root group's parent is the tenant itself.
        $parent = if ($parentKey -and $groups.Contains($parentKey) -and $parentKey -ne $key) { $groups[$parentKey] } else { $root }
        $group.Parent = $parent
        $parent.Children.Add($group)
    }

    # --- Subscriptions, resource groups, resources ------------------------------------------------------
    $subscriptions = @{}
    foreach ($row in $Subscription) {
        $id = & $lower (& $text $row 'subscriptionId')
        if (-not $id -or $subscriptions.Contains($id)) { continue }
        $node = & $newNode 'Subscription' "/subscriptions/$id" (& $text $row 'name') ''
        $node.SubscriptionId = $id
        $node.SubscriptionName = $node.Name
        $node.State = & $text $row 'state'
        $node.Tags = & $tagText (Get-Value $row 'tags')
        $node.QuotaId = & $text $row 'quotaId'
        $parentKey = & $lower (& $text $row 'parentGroup')
        $parent = if ($parentKey -and $groups.Contains($parentKey)) { $groups[$parentKey] } else { $root }
        $node.ManagementGroup = if ($parent.Level -eq 'ManagementGroup') { $parent.DisplayName } else { '' }
        $node.Parent = $parent
        $parent.Children.Add($node)
        $subscriptions[$id] = $node
    }
    $ensureSubscription = {
        param([string] $Id)
        $key = & $lower $Id
        if (-not $subscriptions.Contains($key)) {
            # A subscription seen only through its resources.
            $node = & $newNode 'Subscription' "/subscriptions/$key" $key ''
            $node.SubscriptionId = $key; $node.SubscriptionName = $key; $node.Parent = $root
            $root.Children.Add($node)
            $subscriptions[$key] = $node
        }
        $subscriptions[$key]
    }
    $resourceGroups = @{}
    foreach ($row in $ResourceGroup) {
        $sub = & $ensureSubscription (& $text $row 'subscriptionId')
        $name = & $text $row 'name'
        $key = "$($sub.SubscriptionId)/$(& $lower $name)"
        if ($resourceGroups.Contains($key)) { continue }
        $node = & $newNode 'ResourceGroup' (& $text $row 'id') $name ''
        $node.Location = & $text $row 'location'
        $node.State = & $text $row 'state'
        $node.ManagedBy = & $text $row 'managedBy'
        $node.Tags = & $tagText (Get-Value $row 'tags')
        $node.SubscriptionId = $sub.SubscriptionId; $node.SubscriptionName = $sub.Name; $node.ResourceGroup = $name; $node.ManagementGroup = $sub.ManagementGroup
        $node.Parent = $sub
        $sub.Children.Add($node)
        $resourceGroups[$key] = $node
    }
    foreach ($row in $Resource) {
        $sub = & $ensureSubscription (& $text $row 'subscriptionId')
        $groupName = & $text $row 'resourceGroup'
        $key = "$($sub.SubscriptionId)/$(& $lower $groupName)"
        if (-not $resourceGroups.Contains($key)) {
            $group = & $newNode 'ResourceGroup' "/subscriptions/$($sub.SubscriptionId)/resourceGroups/$groupName" $groupName ''
            $group.SubscriptionId = $sub.SubscriptionId; $group.SubscriptionName = $sub.Name; $group.ResourceGroup = $groupName; $group.ManagementGroup = $sub.ManagementGroup
            $group.Parent = $sub; $sub.Children.Add($group)
            $resourceGroups[$key] = $group
        }
        $parent = $resourceGroups[$key]
        $node = & $newNode 'Resource' (& $text $row 'id') (& $text $row 'name') ''
        $node.Type = & $lower (& $text $row 'type')
        $node.Kind = & $text $row 'kind'
        $node.Location = & $text $row 'location'
        $node.Sku = & $text $row 'sku'
        $node.Zones = (@(Get-Value $row 'zones') | Where-Object { $_ }) -join ', '
        $node.Tags = & $tagText (Get-Value $row 'tags')
        $node.SubscriptionId = $sub.SubscriptionId; $node.SubscriptionName = $sub.Name; $node.ResourceGroup = $groupName; $node.ManagementGroup = $sub.ManagementGroup
        $node.Parent = $parent
        $parent.Children.Add($node)
    }

    # --- Security posture (Defender for Cloud) --------------------------------------------------------
    $hasSecurity = $null -ne $Security -and @(@($Security.Scores) + @($Security.Summary) | Where-Object { $_ }).Count -gt 0
    $byId = @{}
    $controls = @()
    $recommendations = @()
    if ($hasSecurity) {
        $walk = [System.Collections.Generic.Stack[object]]::new()
        $walk.Push($root)
        while ($walk.Count) {
            $node = $walk.Pop()
            if ($node.Id) { $byId[(& $lower $node.Id)] = $node }
            foreach ($child in $node.Children) { $walk.Push($child) }
        }
        foreach ($row in @($Security.Summary)) {
            $node = $byId[(& $lower (& $text $row 'resourceId'))]
            if (-not $node -or $node.Level -ne 'Resource') { continue }
            $node.Healthy = [int](Get-Value $row 'healthy'); $node.Unhealthy = [int](Get-Value $row 'unhealthy')
            $node.High = [int](Get-Value $row 'high'); $node.Medium = [int](Get-Value $row 'medium'); $node.Low = [int](Get-Value $row 'low')
        }
        foreach ($row in @($Security.Scores)) {
            $sub = $subscriptions[(& $lower (& $text $row 'subscriptionId'))]
            if (-not $sub) { continue }
            $sub.ScoreCurrent = [double](Get-Value $row 'current'); $sub.ScoreMax = [double](Get-Value $row 'max'); $sub.OfficialScore = $sub.ScoreMax -gt 0
        }
        # Controls and recommendations: the same objects Get-AACSecurityPosture
        # returns (ConvertTo-AACSecurityControl, ConvertTo-AACSecurityRecommendation),
        # kept to the subscriptions and resources in this inventory.
        $names = @{}
        $maxima = @{}
        foreach ($key in $subscriptions.Keys) { $names[$key] = $subscriptions[$key].Name; $maxima[$key] = $subscriptions[$key].ScoreMax }
        $controls = @(ConvertTo-AACSecurityControl -Row @($Security.Controls) -ScoreMax $maxima -SubscriptionName $names)
        $recommendations = @(foreach ($item in @(ConvertTo-AACSecurityRecommendation -Row @($Security.Recommendations) -SubscriptionName $names)) {
                $node = $byId[([string]$item.ResourceId).ToLowerInvariant()]
                if (-not $node -or $node.Level -notin 'Resource', 'Subscription', 'ResourceGroup') { continue }
                # As the tree names it.
                $item.Resource = $node.DisplayName; $item.Type = $node.Type; $item.ResourceGroup = $node.ResourceGroup
                $item.SubscriptionName = $node.SubscriptionName; $item.SubscriptionId = $node.SubscriptionId; $item.ResourceId = $node.Id
                $item
            })
        foreach ($group in @($recommendations | Where-Object { $_.Type } | Group-Object -Property { ([string]$_.ResourceId).ToLowerInvariant() })) {
            $node = $byId[$group.Name]
            if ($node) { $node.TopFindings = (@($group.Group | Select-Object -First 3 | ForEach-Object { $_.Recommendation })) -join '; ' }
        }
    }

    # --- Cost (Cost Management) -------------------------------------------------------------------------
    $hasCost = $null -ne $Cost
    $unplaced = 0
    if ($hasCost) {
        $invariant = [cultureinfo]::InvariantCulture
        $monthOf = {
            param($Value)
            if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM', $invariant) }
            if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime.ToString('yyyy-MM', $invariant) }
            $raw = ([string]$Value).Trim()
            if ($raw -match '^(\d{4})(\d{2})\d{2}$') { return "$($Matches[1])-$($Matches[2])" }
            if ($raw -match '^(\d{4})-(\d{2})') { return "$($Matches[1])-$($Matches[2])" }
            ''
        }
        $resourcesById = @{}
        $walk = [System.Collections.Generic.Stack[object]]::new()
        $walk.Push($root)
        while ($walk.Count) {
            $node = $walk.Pop()
            if ($node.Level -eq 'Resource' -and $node.Id) { $resourcesById[(& $lower $node.Id)] = $node }
            foreach ($child in $node.Children) { $walk.Push($child) }
        }
        $deleted = @{}
        $deletedIds = @{}
        $addCost = {
            param($Node, [string] $Month, [double] $Amount, [string] $Currency)
            if ($Month -eq $Cost.ThisMonth) { $Node.CostMonthToDate += $Amount }
            elseif ($Month -eq $Cost.LastMonth) { $Node.CostLastMonth += $Amount }
            else { return }
            if ($Currency) { $Node.Currencies[$Currency] = $true }
        }
        foreach ($row in @($Cost.Rows)) {
            $amount = [double](Get-Value $row 'Cost')
            $month = & $monthOf (Get-Value $row 'BillingMonth')
            if (-not $month) { $month = & $monthOf (Get-Value $row 'UsageDate') }
            if (-not $month) { $unplaced++; continue }
            $currency = & $text $row 'Currency'
            $resourceId = & $lower (& $text $row 'ResourceId')
            # The resource, or the closest one above it (a server for its database).
            $node = $null
            for ($id = $resourceId; $id -match '/providers/.+/.+/.+'; $id = $id -replace '/[^/]+/[^/]+$', '') {
                if ($resourcesById.Contains($id)) { $node = $resourcesById[$id]; break }
            }
            if ($node) { & $addCost $node $month $amount $currency; continue }
            # Not in the inventory: a deleted resource, or a charge not tied to one.
            $subscriptionId = & $lower (& $text $row 'SubscriptionId')
            if (-not $subscriptionId -and $resourceId -match '^/subscriptions/([^/]+)') { $subscriptionId = $Matches[1] }
            if (-not $subscriptions.Contains($subscriptionId)) { continue }
            if ($Cost['FilterGroups']) {
                if ($resourceId -notmatch '^/subscriptions/[^/]+/resourcegroups/([^/]+)') { continue }
                if (-not $resourceGroups.Contains("$subscriptionId/$($Matches[1])")) { continue }
            }
            if (-not $deleted.Contains($subscriptionId)) {
                $sub = $subscriptions[$subscriptionId]
                $node = & $newNode 'DeletedResources' "/subscriptions/$subscriptionId/deletedresources" 'Deleted resources' ''
                $node.SubscriptionId = $sub.SubscriptionId; $node.SubscriptionName = $sub.Name; $node.ManagementGroup = $sub.ManagementGroup
                $node.Parent = $sub
                $sub.Children.Add($node)
                $deleted[$subscriptionId] = $node
                $deletedIds[$subscriptionId] = [System.Collections.Generic.HashSet[string]]::new()
            }
            if ($resourceId) { [void]$deletedIds[$subscriptionId].Add($resourceId) }
            & $addCost $deleted[$subscriptionId] $month $amount $currency
        }
        foreach ($key in @($deleted.Keys)) {
            $node = $deleted[$key]
            $node.DeletedCount = $deletedIds[$key].Count
            # Nothing charged in the period: no line.
            if ($node.CostMonthToDate -eq 0 -and $node.CostLastMonth -eq 0) { [void]$node.Parent.Children.Remove($node) }
        }
        foreach ($key in @($subscriptions.Keys)) {
            $subscriptions[$key].CostStatus = if ($Cost['Status'] -and $Cost['Status'].Contains($key)) { [string]$Cost['Status'][$key] } else { 'Not read' }
        }
    }

    # --- Counts, rolled up; empty management groups left out -------------------------------------------
    $keep = @($KeepManagementGroup | ForEach-Object { & $lower $_ })
    function Measure-Node($Node) {
        $Node.TypeCounts = @{}
        $Node.ManagementGroups = 0; $Node.Subscriptions = 0; $Node.ResourceGroups = 0; $Node.Resources = 0
        $Node.Keep = $Node.Level -eq 'ManagementGroup' -and ($keep -contains (& $lower $Node.Name))
        if ($Node.Level -notin 'Resource', 'DeletedResources') {
            $Node.Healthy = 0; $Node.Unhealthy = 0; $Node.High = 0; $Node.Medium = 0; $Node.Low = 0
            if (-not $Node.OfficialScore) { $Node.ScoreCurrent = 0.0; $Node.ScoreMax = 0.0 }
            $Node.CostMonthToDate = 0.0; $Node.CostLastMonth = 0.0; $Node.Currencies = @{}
        }
        foreach ($child in @($Node.Children)) {
            Measure-Node $child
            switch ($child.Level) {
                'ManagementGroup' { $Node.ManagementGroups += 1 + $child.ManagementGroups }
                'Subscription' { $Node.Subscriptions += 1 }
                'ResourceGroup' { $Node.ResourceGroups += 1 }
                'Resource' { $Node.Resources += 1; $Node.TypeCounts[$child.Type] = 1 + [int]$Node.TypeCounts[$child.Type] }
            }
            if ($child.Level -eq 'ManagementGroup' -and $child.Keep) { $Node.Keep = $true }
            $Node.Healthy += $child.Healthy; $Node.Unhealthy += $child.Unhealthy
            $Node.CostMonthToDate += $child.CostMonthToDate; $Node.CostLastMonth += $child.CostLastMonth
            foreach ($currency in $child.Currencies.Keys) { $Node.Currencies[$currency] = $true }
            $Node.High += $child.High; $Node.Medium += $child.Medium; $Node.Low += $child.Low
            # A management group's and the tenant's score: their subscriptions' added up.
            if ($Node.Level -in 'Tenant', 'ManagementGroup' -and $child.Level -in 'Subscription', 'ManagementGroup') {
                $Node.ScoreCurrent += $child.ScoreCurrent; $Node.ScoreMax += $child.ScoreMax
            }
            if ($child.Level -ne 'Resource') {
                $Node.Subscriptions += $(if ($child.Level -eq 'Subscription') { 0 } else { $child.Subscriptions })
                $Node.ResourceGroups += $(if ($child.Level -eq 'ResourceGroup') { 0 } else { $child.ResourceGroups })
                $Node.Resources += $child.Resources
                foreach ($type in $child.TypeCounts.Keys) { $Node.TypeCounts[$type] = [int]$Node.TypeCounts[$type] + $child.TypeCounts[$type] }
            }
        }
        # A management group with no subscription below it isn't part of this
        # inventory, unless it was asked for.
        $Node.Children = [System.Collections.Generic.List[object]]@(@($Node.Children) | Where-Object {
                $_.Level -ne 'ManagementGroup' -or $_.Subscriptions -gt 0 -or $_.Keep
            })
        # Recount management groups after pruning.
        $Node.ManagementGroups = 0
        foreach ($child in $Node.Children) { if ($child.Level -eq 'ManagementGroup') { $Node.ManagementGroups += 1 + $child.ManagementGroups } }
    }
    Measure-Node $root

    # Order: management groups, then subscriptions, then groups and resources, by name.
    $order = @{ ManagementGroup = 0; Subscription = 1; ResourceGroup = 2; Resource = 3; DeletedResources = 4 }
    function Complete-Node($Node, [string] $Path, [int] $Depth, $Items) {
        $Node.Depth = $Depth
        $Node.Path = if ($Path) { "$Path / $($Node.DisplayName)" } else { $Node.DisplayName }
        $top = @($Node.TypeCounts.GetEnumerator() | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, Name | Select-Object -First 3 | ForEach-Object { "$(($_.Name -split '/')[-1]) $($_.Value)" })
        $Node.TopTypes = $top -join ', '
        if ($hasSecurity) {
            $assessed = $Node.Healthy + $Node.Unhealthy
            $Node.SecureScore = if ($Node.Level -in 'Tenant', 'ManagementGroup', 'Subscription' -and $Node.ScoreMax -gt 0) { [Math]::Round(100 * $Node.ScoreCurrent / $Node.ScoreMax) }
            elseif ($assessed -gt 0) { [Math]::Round(100 * $Node.Healthy / $assessed) }
            else { $null }
            $Node.Severity = if ($Node.High) { 'High' } elseif ($Node.Medium) { 'Medium' } elseif ($Node.Low) { 'Low' } elseif ($assessed) { 'Healthy' } else { '' }
            $Node.Rating = if ($null -eq $Node.SecureScore) { '' } elseif ($Node.SecureScore -ge 70) { 'Good' } elseif ($Node.SecureScore -ge 40) { 'Fair' } else { 'Poor' }
        }
        # One currency, or 'mixed' - never added across currencies.
        $Node.Currency = if ($Node.Currencies.Count -eq 1) { @($Node.Currencies.Keys)[0] } elseif ($Node.Currencies.Count -gt 1) { 'mixed' } else { '' }
        # Read, but nothing charged in the period: a state of its own, as Show-AACCost says it.
        if ($Node.Level -eq 'Subscription' -and $Node.CostStatus -eq 'OK' -and $Node.CostMonthToDate -eq 0 -and $Node.CostLastMonth -eq 0) { $Node.CostStatus = 'No cost' }
        $Node.Detail = switch ($Node.Level) {
            'Tenant' { $TenantId }
            'ManagementGroup' { $Node.Name }
            'Subscription' { (@($Node.SubscriptionId, $Node.State) | Where-Object { $_ }) -join ' · ' }
            'ResourceGroup' { (@($Node.Location, $(if ($Node.Resources -eq 0) { 'empty' })) | Where-Object { $_ }) -join ' · ' }
            'Resource' { (@(($Node.Type -replace '^microsoft\.', ''), $Node.Location, $Node.Sku) | Where-Object { $_ }) -join ' · ' }
            'DeletedResources' { "costs of resources no longer in Azure$(if ($Node.DeletedCount) { " ($($Node.DeletedCount))" }), and charges not tied to a resource" }
        }
        $Items.Add([pscustomobject][ordered]@{
                PSTypeName       = 'AAC.InventoryItem'
                Level            = $Node.Level
                Depth            = $Depth
                Name             = $Node.DisplayName
                Path             = $Node.Path
                ManagementGroup  = $Node.ManagementGroup
                SubscriptionName = $Node.SubscriptionName
                SubscriptionId   = $Node.SubscriptionId
                ResourceGroup    = $Node.ResourceGroup
                Type             = $Node.Type
                Kind             = $Node.Kind
                Location         = $Node.Location
                Sku              = $Node.Sku
                Zones            = $Node.Zones
                State            = $Node.State
                ManagementGroups = $Node.ManagementGroups
                Subscriptions    = $Node.Subscriptions
                ResourceGroups   = $Node.ResourceGroups
                Resources        = $Node.Resources
                TopTypes         = $Node.TopTypes
                SecureScore      = $Node.SecureScore
                ScorePoints      = $(if ($Node.Level -in 'Tenant', 'ManagementGroup', 'Subscription' -and $Node.ScoreMax -gt 0) { '{0:N1} / {1:N1}' -f $Node.ScoreCurrent, $Node.ScoreMax } else { '' })
                Rating           = $Node.Rating
                Severity         = $Node.Severity
                High             = $Node.High
                Medium           = $Node.Medium
                Low              = $Node.Low
                Findings         = $Node.Unhealthy
                TopFindings      = $Node.TopFindings
                CostMonthToDate  = $(if ($hasCost -and $Node.Currency -ne 'mixed') { [Math]::Round($Node.CostMonthToDate, 2) } else { $null })
                CostLastMonth    = $(if ($hasCost -and $Node.Currency -ne 'mixed') { [Math]::Round($Node.CostLastMonth, 2) } else { $null })
                Currency         = $Node.Currency
                CostStatus       = $Node.CostStatus
                Tags             = $Node.Tags
                Id               = $Node.Id
            })
        $sorted = @($Node.Children | Sort-Object -Property @{ Expression = { $order[$_.Level] } }, @{ Expression = { $_.DisplayName } })
        $Node.Children = [System.Collections.Generic.List[object]]@($sorted)
        foreach ($child in $sorted) { Complete-Node $child $Node.Path ($Depth + 1) $Items }
    }
    $items = [System.Collections.Generic.List[object]]::new()
    Complete-Node $root '' 0 $items

    $all = $items.ToArray()
    @{
        Root  = $root
        Items = $all
        Stats = @{
            ManagementGroups = $root.ManagementGroups
            Subscriptions    = @($all | Where-Object Level -EQ 'Subscription').Count
            ResourceGroups   = @($all | Where-Object Level -EQ 'ResourceGroup').Count
            EmptyGroups      = @($all | Where-Object { $_.Level -eq 'ResourceGroup' -and $_.Resources -eq 0 }).Count
            Resources        = $root.Resources
            Types            = $root.TypeCounts.Count
            Locations        = @($all | Where-Object { $_.Level -eq 'Resource' -and $_.Location } | Select-Object -ExpandProperty Location -Unique).Count
            HasSecurity      = $hasSecurity
            SecureScore      = $root.SecureScore
            Rating           = $root.Rating
            High             = $root.High
            Medium           = $root.Medium
            Low              = $root.Low
            Assessed         = @($all | Where-Object { $_.Level -eq 'Resource' -and $null -ne $_.SecureScore }).Count
            HasCost          = $hasCost
            # Totals per currency, largest first (never converted).
            Cost             = @(if ($hasCost) {
                    $all | Where-Object { $_.Level -in 'Resource', 'DeletedResources' -and $_.Currency } | Group-Object -Property Currency | ForEach-Object {
                        $monthToDate = 0.0; $lastMonth = 0.0
                        foreach ($item in $_.Group) { $monthToDate += [double]$item.CostMonthToDate; $lastMonth += [double]$item.CostLastMonth }
                        [pscustomobject]@{ Currency = $_.Name; MonthToDate = [Math]::Round($monthToDate, 2); LastMonth = [Math]::Round($lastMonth, 2) }
                    } | Sort-Object -Property MonthToDate -Descending
                })
            CostUnplaced     = $unplaced
        }
        Controls        = $controls
        Recommendations = $recommendations
        # Get-AACInventory -Insight adds it (ConvertTo-AACInventoryInsight).
        Insight         = $null
        TopSpend        = @(if ($hasCost) { $all | Where-Object { $_.Level -eq 'Resource' -and $_.CostMonthToDate -gt 0 } | Sort-Object -Property @{ Expression = 'CostMonthToDate'; Descending = $true }, Name | Select-Object -First 15 })
    }
}
