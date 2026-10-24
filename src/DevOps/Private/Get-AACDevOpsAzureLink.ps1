function Get-AACDevOpsAzureLink {
    <#
    .SYNOPSIS
        For Azure DevOps service connections' service principals (by
        application ID): their Entra display name and every Azure role they
        hold, with the scope in words.
    .DESCRIPTION
        Uses the Connect-AAC sign-in. Microsoft Graph turns the application
        IDs into service principal object IDs (15 to a request, the most an
        'in' filter takes); Get-AACAzureRoleAssignment then reads their
        role assignments across the tenant, with the role names and the
        subscription names.

        Returns @{ Link = application ID (lower case) -> @{ DisplayName;
        ObjectId; Roles = @(@{ Role; Scope (in words); Level - Tenant,
        Management group, Subscription, Resource group or Resource;
        ScopeId }) }; Errors = what couldn't be read }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $AppId
    )

    $link = @{}
    $problems = [System.Collections.Generic.List[string]]::new()
    $ids = @($AppId | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    if (-not $ids.Count) { return @{ Link = $link; Errors = @() } }

    # 1. Application IDs -> service principals.
    $queries = [ordered]@{}
    for ($i = 0; $i -lt $ids.Count; $i += 15) {
        $chunk = @($ids | Select-Object -Skip $i -First 15)
        $queries["sp$i"] = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId in ($((@($chunk | ForEach-Object { "'$_'" })) -join ','))&`$select=id,appId,displayName"
    }
    $graph = Read-AACGraphQuery -Query $queries
    foreach ($name in $graph.Errors.Keys) { $problems.Add("Microsoft Graph: $($graph.Errors[$name])") }
    $byObject = @{}
    foreach ($name in $graph.Data.Keys) {
        foreach ($sp in @($graph.Data[$name])) {
            if (-not $sp) { continue }
            $entry = @{ DisplayName = [string]$sp['displayName']; ObjectId = [string]$sp['id']; Roles = [System.Collections.Generic.List[hashtable]]::new() }
            $link[([string]$sp['appId']).ToLowerInvariant()] = $entry
            $byObject[([string]$sp['id']).ToLowerInvariant()] = $entry
        }
    }
    if (-not $byObject.Count) { return @{ Link = $link; Errors = $problems.ToArray() } }

    # 2. Their role assignments, the role names and the subscription names.
    $azure = Get-AACAzureRoleAssignment -PrincipalId @($byObject.Keys)
    foreach ($problem in $azure.Errors) { $problems.Add($problem) }
    foreach ($objectId in $azure.Assignments.Keys) {
        $entry = $byObject[$objectId]
        if ($entry) { foreach ($role in $azure.Assignments[$objectId]) { $entry.Roles.Add($role) } }
    }
    @{ Link = $link; Errors = $problems.ToArray() }
}
