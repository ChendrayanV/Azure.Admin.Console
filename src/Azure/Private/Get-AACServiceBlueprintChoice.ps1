function Get-AACServiceBlueprintChoice {
    <#
    .SYNOPSIS
        What -Service tab completes to: the services with a template, and, when
        signed in, every service Azure lists with a resource type.
    .DESCRIPTION
        Tab completion must never fail or ask for a sign-in, so without a sign-in,
        or when the list can't be read, only the templates are offered. Names are
        quoted when they need it, ready to be typed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Word = ''
    )

    $names = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($template in (Get-AACServiceTemplate).Values) { $null = $names.Add($template.Name) }
    if ($script:AACSession) {
        try { foreach ($service in @(Get-AACServiceCatalog)) { if ($service.ResourceTypes.Count) { $null = $names.Add($service.Name) } } }
        catch { Write-Verbose -Message "Azure's list of services couldn't be read: $($_.Exception.Message)" }
    }
    $typed = $Word.Trim("'", '"')
    foreach ($name in $names) {
        if ($name -notlike "*$([System.Management.Automation.WildcardPattern]::Escape($typed))*") { continue }
        if ($name -match '^[\w.-]+$') { $name } else { "'$($name -replace "'", "''")'" }
    }
}
