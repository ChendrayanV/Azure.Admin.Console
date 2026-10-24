function Get-AACAzureRoleAssignment {
    <#
    .SYNOPSIS
        Every Azure role assignment (RBAC) held by the given Entra object IDs,
        across the tenant, with the role's name and the scope in words.
    .DESCRIPTION
        One Azure Resource Graph batch (the Connect-AAC sign-in): the role
        assignments of the principals - users, groups, service principals,
        managed identities - joined to the role definitions' names, and the
        subscription names for the scopes.

        Returns @{ Assignments = principal ID (lower case) -> @(@{ Role;
        Scope (in words); Level - Tenant, Management group, Subscription,
        Resource group or Resource; ScopeId; Id }); Errors = what couldn't be
        read (Resource Graph's reason) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $PrincipalId
    )

    $byPrincipal = @{}
    $problems = [System.Collections.Generic.List[string]]::new()
    $ids = @($PrincipalId | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    if (-not $ids.Count) { return @{ Assignments = $byPrincipal; Errors = @() } }

    $principals = (@($ids | ForEach-Object { ConvertTo-AACKqlLiteral -Text $_ })) -join ', '
    $read = Invoke-AACGraphBatch -AllowFailure 'assignments', 'subscriptions' -Query ([ordered]@{
            assignments   = @{ Tenant = $true; Query = @"
authorizationresources
| where type =~ 'microsoft.authorization/roleassignments'
| extend principalId = tolower(tostring(properties.principalId)), scope = tostring(properties.scope), roleGuid = tolower(extract('([^/]+)$', 1, tostring(properties.roleDefinitionId)))
| where principalId in ($principals)
| join kind=leftouter (authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | extend roleGuid = tolower(name), roleName = tostring(properties.roleName) | summarize roleName = any(roleName) by roleGuid) on roleGuid
| project id, principalId, scope, roleName, roleGuid
"@ }
            subscriptions = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId = tolower(subscriptionId), name" }
        })
    foreach ($name in $read.Errors.Keys) { $problems.Add("Azure Resource Graph ($name): $($read.Errors[$name])") }
    $subscriptionName = @{}
    foreach ($s in @($read.Rows['subscriptions'] | Where-Object { $_ })) { $subscriptionName[[string]$s['subscriptionId']] = [string]$s['name'] }
    foreach ($a in @($read.Rows['assignments'] | Where-Object { $_ })) {
        $principal = ([string]$a['principalId']).ToLowerInvariant()
        $scopeId = [string]$a['scope']
        $sub = if ($scopeId -match '^/subscriptions/([^/]+)') { $Matches[1].ToLowerInvariant() } else { '' }
        $subLabel = if ($sub -and $subscriptionName.ContainsKey($sub)) { $subscriptionName[$sub] } else { $sub }
        $level, $words = if ($scopeId -eq '/' -or $scopeId -eq '') { 'Tenant', 'the tenant root' }
        elseif ($scopeId -match '/managementGroups/([^/]+)$') { 'Management group', "management group $($Matches[1])" }
        elseif ($scopeId -match '^/subscriptions/[^/]+$') { 'Subscription', "subscription $subLabel" }
        elseif ($scopeId -match '^/subscriptions/[^/]+/resourceGroups/([^/]+)$') { 'Resource group', "resource group $($Matches[1]) ($subLabel)" }
        else { 'Resource', "$(($scopeId -split '/')[-1]) ($subLabel)" }
        $role = [string]$a['roleName']
        if (-not $byPrincipal.ContainsKey($principal)) { $byPrincipal[$principal] = [System.Collections.Generic.List[hashtable]]::new() }
        $byPrincipal[$principal].Add(@{ Role = $(if ($role) { $role } else { [string]$a['roleGuid'] }); Scope = $words; Level = $level; ScopeId = $scopeId; Id = [string]$a['id'] })
    }
    @{ Assignments = $byPrincipal; Errors = $problems.ToArray() }
}
