function Resolve-AACServiceBlueprintService {
    <#
    .SYNOPSIS
        Turns a service as you typed it into what a blueprint plans: a template's
        resources, or the resource types Azure lists for it.
    .DESCRIPTION
        Spaces, hyphens and case don't matter. In order: a template by its key or
        name; a service in Azure's list by its name; by a resource type it has;
        by part of its name, when only one service fits. A service in Azure's
        list uses a template when it has the template's type, so 'Blob Storage'
        is planned as a storage account.

        Returns @{ Name; Template (the key, or ''); ResourceTypes }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Template,

        # Get-AACServiceCatalog's services. Empty when not signed in.
        [AllowEmptyCollection()]
        [object[]] $Catalog = @()
    )

    $plain = { param([string] $Text) ($Text -replace '[^A-Za-z0-9]', '').ToLowerInvariant() }
    $wanted = & $plain $Name
    foreach ($key in $Template.Keys) {
        if ($wanted -eq (& $plain $key) -or $wanted -eq (& $plain $Template[$key].Name)) { return @{ Name = $Template[$key].Name; Template = $key; ResourceTypes = @() } }
    }

    $found = @($Catalog | Where-Object { (& $plain $_.Name) -eq $wanted })
    if (-not $found.Count) { $found = @($Catalog | Where-Object { @($_.ResourceTypes | Where-Object { $_ -ieq $Name.Trim() }).Count }) }
    if (-not $found.Count) { $found = @($Catalog | Where-Object { $_.ResourceTypes.Count -and (& $plain $_.Name).Contains($wanted) }) }

    if (-not $found.Count) {
        if ($Catalog.Count) { throw "Azure Admin Console doesn't know the service '$Name'. Press Tab after -Service for the names in Azure's list, or give a resource type such as Microsoft.Compute/virtualMachines." }
        throw "Azure Admin Console doesn't know the service '$Name' without Azure's list of services. Run Connect-AAC to read it; without it, it can plan $(@($Template.Keys) -join ', ')."
    }
    if ($found.Count -gt 1) { throw "Azure Admin Console found $($found.Count) services for '$Name': $(@($found.Name) -join ', '). Name one of them." }

    $service = $found[0]
    if (-not $service.ResourceTypes.Count) { throw "Azure Admin Console can't plan '$($service.Name)': Azure lists no resource type for it, so there is nothing to deploy." }
    foreach ($key in $Template.Keys) {
        $candidate = $Template[$key]
        $hasAnchor = @($service.ResourceTypes | Where-Object { $_ -ieq $candidate.Anchor }).Count
        $nameFits = -not $candidate.Contains('NameLike') -or $service.Name -like $candidate.NameLike
        if ($hasAnchor -and $nameFits) { return @{ Name = $candidate.Name; Template = $key; ResourceTypes = @() } }
    }
    @{ Name = $service.Name; Template = ''; ResourceTypes = @($service.ResourceTypes) }
}
