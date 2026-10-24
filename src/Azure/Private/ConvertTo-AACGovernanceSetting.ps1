function ConvertTo-AACGovernanceSetting {
    <#
    .SYNOPSIS
        Builds Get-AACGovernanceSetting's list (AAC.GovernanceSetting) from
        the tenant's management group settings and each subscription's
        details, Defender security contacts, classic administrators,
        preview features and resource providers.
    .DESCRIPTION
        No Azure calls.
          -Hierarchy      the root management group's settings/default
                          (properties: defaultManagementGroup,
                          requireAuthorizationForGroupCreation), or $null
          -HierarchyError why it couldn't be read
          -Subscription   Resolve-AACScope's subscription rows, with
                          quotaId and spendingLimit when Resource Graph had
                          them
          -GroupDiagnostics management group name -> @{ Items } (its
                          diagnostic settings) or @{ Error }
          -PerSubscription  subscription ID -> @{ Contacts; Classic;
                          Features; Providers } (each the items, or $null
                          when not read) and Errors (name -> why)
        Rows: Area, Scope, Setting, Value, Status (Warning, Info, OK) and
        Recommendation. What is checked:
          Management groups   who may create one (Warning when anyone can);
                              where new subscriptions land (Warning when the
                              root)
          Diagnostics         each management group's activity log exported
                              (Warning when nowhere)
          Subscription        offer (quota ID), state, spending limit
          Defender contacts   an email for security alerts (Warning when
                              none), alert notifications and their minimum
                              severity, notifications to the Owner role
          Classic admins      co-administrators left (Warning: the role is
                              retired)
          Preview features    each registered preview feature (Info)
          Resource providers  each provider registered in some subscriptions
                              but not all (Info)
        Returns @{ Settings; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        $Hierarchy,

        [string] $HierarchyError = '',

        [string] $TenantId = '',

        [object[]] $Subscription = @(),

        [hashtable] $PerSubscription = @{},

        [System.Collections.IDictionary] $GroupDiagnostics = @{}
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $notices = [System.Collections.Generic.List[string]]::new()
    $settings = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Area, [string] $Scope, [string] $Setting, [string] $Value, [string] $Status, [string] $Recommendation = '', [string] $ScopeId = '')
        $item = [pscustomobject][ordered]@{ Status = $Status; Area = $Area; Scope = $Scope; Setting = $Setting; Value = $Value; Recommendation = $Recommendation; ScopeId = $ScopeId }
        $item.PSObject.TypeNames.Insert(0, 'AAC.GovernanceSetting')
        $settings.Add($item)
    }

    # --- Management group hierarchy settings ---------------------------------------------------------------------------------
    if ($null -ne $Hierarchy) {
        $p = & $get $Hierarchy 'properties'
        $require = & $text $p 'requireAuthorizationForGroupCreation'
        $default = & $text $p 'defaultManagementGroup'
        $rootId = "/providers/Microsoft.Management/managementGroups/$TenantId"
        if ($require -eq 'True') { & $add 'Management groups' 'Tenant root group' 'Who can create management groups' 'Only those with write permission on the root' 'OK' '' $rootId }
        else { & $add 'Management groups' 'Tenant root group' 'Who can create management groups' 'Any user in the tenant' 'Warning' 'Require authorization for management group creation (Management groups > Settings), so only those with write permission on the root group can add one.' $rootId }
        $defaultName = ($default -split '/')[-1]
        if (-not $default -or ($TenantId -and $defaultName -eq $TenantId)) { & $add 'Management groups' 'Tenant root group' 'Default management group for new subscriptions' 'The tenant root group' 'Warning' 'Set a default management group (a sandbox or onboarding group with guardrail policies), so new subscriptions don''t land in the root with only the root''s policies.' $rootId }
        else { & $add 'Management groups' 'Tenant root group' 'Default management group for new subscriptions' $defaultName 'OK' '' $rootId }
    }
    elseif ($HierarchyError) { $notices.Add("The management group hierarchy settings couldn't be read ($HierarchyError): reading them needs Reader on the tenant root group.") }

    # --- Management groups' activity log -------------------------------------------------------------------------------------
    $destinations = [ordered]@{ workspaceId = 'Log Analytics'; storageAccountId = 'storage'; eventHubAuthorizationRuleId = 'Event Hubs' }
    foreach ($g in @($GroupDiagnostics.Keys)) {
        $entry = $GroupDiagnostics[$g]
        $gid = "/providers/Microsoft.Management/managementGroups/$g"
        if ($entry.Contains('Error')) { $notices.Add("The diagnostic settings of management group $g couldn't be read: $($entry.Error)"); continue }
        $exports = @(foreach ($d in @(& $list $entry.Items)) {
                $p = & $get $d 'properties'
                $enabled = @(@(& $list (& $get $p 'logs')) | Where-Object { (& $text $_ 'enabled') -eq 'True' } | ForEach-Object { & $text $_ 'category' })
                if (-not $enabled.Count) { continue }
                $to = @(foreach ($key in $destinations.Keys) { $target = & $text $p $key; if ($target) { "$($destinations[$key]) $(($target -split '/')[-1])" } })
                "$($to -join ', ') ($($enabled -join ', '))"
            })
        if ($exports.Count) { & $add 'Diagnostics' "management group $g" 'Activity log exported' ($exports -join '; ') 'OK' '' $gid }
        else { & $add 'Diagnostics' "management group $g" 'Activity log exported' 'Nowhere' 'Warning' "Export the management group's activity log (administrative and policy events) to a Log Analytics workspace: it records who changed policy and access at this level, and is kept only 90 days otherwise." $gid }
    }

    # --- Per subscription ----------------------------------------------------------------------------------------------------
    $providerSubs = @{}
    $subscriptionCount = 0
    foreach ($s in @($Subscription)) {
        $id = ([string]$s['subscriptionId']).ToLowerInvariant()
        $name = [string]$s['name']
        $sid = "/subscriptions/$id"
        $subscriptionCount++
        $quota = & $text $s 'quotaId'
        if ($quota) {
            $offer = switch -Regex ($quota) { '^MSDN|^MSDNDevTest|Visual' { 'Visual Studio / MSDN (dev and test)' } 'FreeTrial' { 'Free trial' } 'EnterpriseAgreement' { 'Enterprise Agreement' } 'PayAsYouGo' { 'Pay-as-you-go' } 'CSP' { 'Cloud Solution Provider' } 'Sponsored' { 'Sponsored' } default { $quota } }
            & $add 'Subscription' $name 'Offer' $offer $(if ($quota -match 'FreeTrial|MSDN') { 'Info' } else { 'OK' }) $(if ($quota -match 'FreeTrial|MSDN') { 'A dev/test or trial offer has no SLA - keep production workloads off it.' } else { '' }) $sid
        }
        $state = & $text $s 'state'
        if ($state -and $state -ne 'Enabled') { & $add 'Subscription' $name 'State' $state 'Warning' 'A subscription that is not Enabled stops its resources - reactivate or cancel it deliberately.' $sid }
        if ((& $text $s 'spendingLimit') -eq 'On') { & $add 'Subscription' $name 'Spending limit' 'On' 'Info' 'Resources stop when the limit is reached.' $sid }

        $data = if ($PerSubscription.Contains($id)) { $PerSubscription[$id] } else { @{} }
        $errors = if ($data.Contains('Errors')) { $data.Errors } else { @{} }

        # Defender security contacts.
        if ($data.Contains('Contacts') -and $null -ne $data.Contacts) {
            $contacts = @(& $list $data.Contacts)
            $emails = @($contacts | ForEach-Object { & $text (& $get $_ 'properties') 'emails'; & $text (& $get $_ 'properties') 'email' } | Where-Object { $_ } | ForEach-Object { $_ -split '[;,]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
            if (-not $emails.Count) { & $add 'Defender contacts' $name 'Security contact email' 'None' 'Warning' 'Add a security contact email (Defender for Cloud > Environment settings > Email notifications), so high-severity alerts reach someone.' $sid }
            else { & $add 'Defender contacts' $name 'Security contact email' ($emails -join ', ') 'OK' '' $sid }
            foreach ($c in $contacts) {
                $p = & $get $c 'properties'
                $alertState = & $text $p 'alertNotifications.state'
                if ($alertState) {
                    $minimal = & $text $p 'alertNotifications.minimalSeverity'
                    & $add 'Defender contacts' $name 'Alert notifications' $(if ($alertState -eq 'On') { "On (from $minimal severity)" } else { 'Off' }) $(if ($alertState -eq 'On') { 'OK' } else { 'Warning' }) $(if ($alertState -eq 'On') { '' } else { 'Turn alert notifications on, so security alerts are emailed.' }) $sid
                }
                $roleState = & $text $p 'notificationsByRole.state'
                if ($roleState) {
                    $roles = @(& $list (& $get $p 'notificationsByRole.roles'))
                    $toOwners = $roleState -eq 'On' -and $roles -contains 'Owner'
                    & $add 'Defender contacts' $name 'Notifications to roles' $(if ($roleState -eq 'On') { $roles -join ', ' } else { 'Off' }) $(if ($toOwners) { 'OK' } else { 'Info' }) $(if ($toOwners) { '' } else { 'Notify the Owner role too, so the subscription''s owners hear about alerts.' }) $sid
                }
            }
        }
        elseif ($errors.Contains('Contacts')) { $notices.Add("Defender security contacts couldn't be read for $($name): $($errors.Contacts)") }

        # Classic administrators.
        if ($data.Contains('Classic') -and $null -ne $data.Classic) {
            $co = @(@(& $list $data.Classic) | Where-Object { (& $text (& $get $_ 'properties') 'role') -match 'CoAdministrator' })
            if ($co.Count) { & $add 'Classic administrators' $name 'Co-administrators' (@($co | ForEach-Object { & $text (& $get $_ 'properties') 'emailAddress' }) -join ', ') 'Warning' 'Classic administrators are retired: give these people an Azure role (Owner or narrower) and remove them as co-administrators.' $sid }
        }

        # Preview features.
        if ($data.Contains('Features') -and $null -ne $data.Features) {
            foreach ($f in @(& $list $data.Features)) {
                if ((& $text (& $get $f 'properties') 'state') -ne 'Registered') { continue }
                & $add 'Preview features' $name (& $text $f 'name') 'Registered' 'Info' 'A preview feature has no SLA and can change: check it is still needed, especially in production.' $sid
            }
        }
        elseif ($errors.Contains('Features')) { $notices.Add("Preview features couldn't be read for $($name): $($errors.Features)") }

        # Resource providers: registered here?
        if ($data.Contains('Providers') -and $null -ne $data.Providers) {
            foreach ($p in @(& $list $data.Providers)) {
                $ns = & $text $p 'namespace'
                if (-not $ns) { continue }
                if (-not $providerSubs.Contains($ns)) { $providerSubs[$ns] = [System.Collections.Generic.List[string]]::new() }
                if ((& $text $p 'registrationState') -eq 'Registered') { $providerSubs[$ns].Add($name) }
            }
        }
        elseif ($errors.Contains('Providers')) { $notices.Add("Resource providers couldn't be read for $($name): $($errors.Providers)") }
    }
    $readProviders = @($Subscription | Where-Object { $i = ([string]$_['subscriptionId']).ToLowerInvariant(); $PerSubscription.Contains($i) -and $PerSubscription[$i].Contains('Providers') -and $null -ne $PerSubscription[$i].Providers }).Count
    foreach ($ns in @($providerSubs.Keys | Sort-Object)) {
        $n = $providerSubs[$ns].Count
        if ($n -eq 0 -or $n -eq $readProviders) { continue }
        & $add 'Resource providers' "$n of $readProviders subscription(s)" $ns "Registered in: $((@($providerSubs[$ns] | Sort-Object)) -join ', ')" 'Info' 'Registered in some subscriptions only: deployments that need it fail elsewhere until it is registered (or a policy blocks it on purpose).'
    }

    $order = @{ Warning = 0; Info = 1; OK = 2 }
    $areas = @{ 'Management groups' = 0; Diagnostics = 0.5; Subscription = 1; 'Defender contacts' = 2; 'Classic administrators' = 3; 'Preview features' = 4; 'Resource providers' = 5 }
    $sorted = @($settings | Sort-Object -Property @{ Expression = { $order[$_.Status] } }, @{ Expression = { $areas[$_.Area] } }, Scope, Setting)
    @{
        Settings = $sorted
        Notices  = @($notices)
        Stats    = @{ Settings = $sorted.Count; Warning = @($sorted | Where-Object Status -EQ 'Warning').Count; Subscriptions = $subscriptionCount }
    }
}
