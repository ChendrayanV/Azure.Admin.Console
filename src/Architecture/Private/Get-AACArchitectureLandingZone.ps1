function Get-AACArchitectureLandingZone {
    <#
    .SYNOPSIS
        Reads what a landing zone management group imposes on a design: its
        management group chain, the policy assignments in force there and
        above, and the locations an Allowed locations assignment permits.
    .DESCRIPTION
        One Azure Resource Graph batch (tenant-wide): the management group
        and its ancestors, then every policy assignment scoped to one of
        them. The built-in Allowed locations policy (e56962a6-...) and
        Allowed locations for resource groups (e765b5de-...) give the
        locations; an assignment with enforcement DoNotEnforce is listed but
        not enforced. Returns @{ ManagementGroups (root first); Policies =
        @(@{ Name; Scope; Enforcement; DefinitionId }); AllowedLocations }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $ManagementGroup
    )

    $name = (ConvertTo-AACKqlLiteral -Text $ManagementGroup.ToLowerInvariant())
    $chain = Invoke-AACGraphBatch -Query ([ordered]@{
            group = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' and tolower(name) == $name | project id, name, displayName = tostring(properties.displayName), chain = properties.details.managementGroupAncestorsChain" }
        })
    $group = @($chain.Rows['group'] | Where-Object { $_ }) | Select-Object -First 1
    if (-not $group) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console can't find the management group '$ManagementGroup'.")
        $problem.Data['AACHint'] = 'Give the management group''s ID (its name, as in the URL), not its display name - and check the account can read it. -Offline designs without it.'
        throw $problem
    }
    $groups = @(@(@($group['chain']) | Where-Object { $_ } | ForEach-Object { ([string]$_['name']).ToLowerInvariant() }) + @(([string]$group['name']).ToLowerInvariant()))
    # The chain runs from the parent up to the root: root first reads better.
    $ancestors = @($groups[0..([Math]::Max(0, $groups.Count - 2))] | Where-Object { $_ })
    [array]::Reverse($ancestors)
    $ordered = @(@($ancestors) + @($groups[-1]) | Select-Object -Unique)
    $scopes = (@($ordered | ForEach-Object { ConvertTo-AACKqlLiteral -Text "/providers/microsoft.management/managementgroups/$_" })) -join ', '
    $read = Invoke-AACGraphBatch -Query ([ordered]@{
            assignments = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | extend scope = tolower(tostring(properties.scope)) | where scope in ($scopes) | project id, name = tostring(properties.displayName), scope, enforcement = tostring(properties.enforcementMode), definitionId = tolower(tostring(properties.policyDefinitionId)), parameters = properties.parameters" }
        })
    $allowed = [System.Collections.Generic.List[string]]::new()
    $policies = @(foreach ($a in @($read.Rows['assignments'] | Where-Object { $_ })) {
            $definition = [string]$a['definitionId']
            if ($definition -match '/(e56962a6-4747-49cd-b67b-bf8b01975c4c|e765b5de-1225-4ba3-bd56-1ac6695af988)$' -and [string]$a['enforcement'] -ne 'DoNotEnforce') {
                $parameters = $a['parameters']
                $values = if ($parameters -is [System.Collections.IDictionary] -and $parameters.Contains('listOfAllowedLocations')) { $parameters['listOfAllowedLocations']['value'] } else { @() }
                foreach ($v in @($values)) { if ($v -and -not $allowed.Contains(([string]$v).ToLowerInvariant())) { $allowed.Add(([string]$v).ToLowerInvariant()) } }
            }
            @{ Name = [string]$a['name']; Scope = ([string]$a['scope'] -replace '^.*/', ''); Enforcement = $(if ([string]$a['enforcement'] -eq 'DoNotEnforce') { 'Not enforced' } else { 'Enforced' }); DefinitionId = $definition }
        })
    @{ ManagementGroups = $ordered; Policies = $policies; AllowedLocations = $allowed.ToArray() }
}
