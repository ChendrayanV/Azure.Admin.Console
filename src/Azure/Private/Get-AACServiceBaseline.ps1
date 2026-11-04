function Get-AACServiceBaseline {
    <#
    .SYNOPSIS
        The alerts Azure Monitor Baseline Alerts (AMBA) suggests and the
        recommendations of the Azure Proactive Resiliency Library (APRL), for
        resource types.
    .DESCRIPTION
        From src\Azure\Private\ServiceBaseline.json, which
        tools\Update-AACServiceBaseline.ps1 writes from one commit of each
        project. It ships with the module, so this works offline, and it is read
        once per session. Types are matched without regard to case: Azure's list
        of services sends them in upper case.

        LandingZone is the Azure Landing Zone checklist's queries, which are for no one
        resource type, so -ResourceType leaves them alone.

        -ResourceType takes wildcards. -Kind is a resource's kind, such as
        functionapp,linux: an alert written for other kinds of the type is left
        out, and one that names no kind stays.

        Returns @{ Rows (AAC.AlertBaseline or AAC.ResiliencyRecommendation);
        Source (@{ Name; Repository; Commit; License; Url }); Types (every type
        there is, as the project spells it) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Alerts', 'Resiliency', 'LandingZone')]
        [string] $Set,

        [string[]] $ResourceType = @('*'),

        [string] $Kind
    )

    if ($null -eq $script:AACServiceBaseline) {
        $path = Join-Path -Path $script:AACModuleRoot -ChildPath 'src/Azure/Private/ServiceBaseline.json'
        if (-not (Test-Path -LiteralPath $path)) { throw "Azure Admin Console couldn't find $path. Reinstall the module." }
        $data = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($path)) -AsHashtable -Depth 10
        $alerts = @(foreach ($row in $data.Alerts) {
                $condition = if ($row.Type -eq 'Metric' -and $row.Criterion -match 'Dynamic') { "$($row.Aggregation) $($row.Metric): dynamic threshold" }
                elseif ($row.Type -eq 'Metric') { "$($row.Aggregation) $($row.Metric) $($row.Operator) $($row.Threshold)" }
                elseif ($row.Type -eq 'Log') { "Query result $($row.Operator) $($row.Threshold)" }
                else { '' }
                [pscustomobject][ordered]@{
                    PSTypeName = 'AAC.AlertBaseline'; ResourceType = $row.ResourceType; Name = $row.Name; AlertType = $row.Type; Severity = $(if ($null -ne $row.Severity) { "Sev$($row.Severity)" } else { '' }); Condition = $condition
                    Window = $row.Window; Frequency = $row.Frequency; Verified = $row.Verified; Description = $row.Description; Query = $row.Query; Kinds = @($row.Kinds); Link = $row.Link; Guid = $row.Guid
                }
            })
        $resiliency = @(foreach ($row in $data.Resiliency) {
                [pscustomobject][ordered]@{
                    PSTypeName = 'AAC.ResiliencyRecommendation'; ResourceType = $row.ResourceType; Name = $row.Name; Impact = $row.Impact; Control = $row.Control; Benefit = $row.Benefit
                    Verified = $row.Verified; Automated = $row.Automated; Description = $row.Description; Link = $row.Link; Guid = $row.Guid; Query = $row.Query
                }
            })
        $landingZone = @(foreach ($row in $data.LandingZone) {
                [pscustomobject][ordered]@{ PSTypeName = 'AAC.LandingZoneItem'; Category = $row.Category; Subcategory = $row.Subcategory; Name = $row.Name; Severity = $row.Severity; Queryable = $row.Queryable; Reason = $row.Reason; Query = $row.Query; Guid = $row.Guid; ResourceType = '' }
            })
        $script:AACServiceBaseline = @{ Sources = $data.Sources; Alerts = $alerts; Resiliency = $resiliency; LandingZone = $landingZone }
    }

    $all = @($script:AACServiceBaseline[$Set])
    $rows = @($all | Where-Object {
            $row = $_
            $typeFits = @($ResourceType | Where-Object { $row.ResourceType -like $_ }).Count
            ($typeFits -or $Set -eq 'LandingZone') -and (-not $Kind -or $Set -ne 'Alerts' -or -not $row.Kinds.Count -or $row.Kinds -contains $Kind)
        })
    @{ Rows = $rows; Source = $script:AACServiceBaseline.Sources[$Set]; Types = @($all.ResourceType | Sort-Object -Unique) }
}
