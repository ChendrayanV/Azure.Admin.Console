function Read-AACApplicationInsightDetail {
    <#
    .SYNOPSIS
        Reads what Invoke-AACApplicationInsightAssessment needs from each
        Application Insights component through Resource Manager - its daily
        cap, API keys, diagnostic settings and role assignments - many
        requests at once.
    .DESCRIPTION
        Per component, through Invoke-AACArmParallel (Reader is enough):
          Billing      currentbillingfeatures: the daily cap (DataVolumeCap)
                       and whether its warnings are sent
          ApiKeys      the component's API keys (names, created, read or
                       write rights - never the key itself)
          Diagnostics  its diagnostic settings: a setting that sends the
                       telemetry categories to a workspace bills it twice
          Roles        role assignments at the component and above
                       (atScope()), inherited ones included
        A call fails on its own; its answer then carries Error.

        Returns @{ component id = @{ Billing; ApiKeys; Diagnostics; Roles } },
        each Invoke-AACArmParallel's answer.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $ComponentId,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [scriptblock] $OnProgress
    )

    $calls = [ordered]@{
        Billing     = '/currentbillingfeatures?api-version=2015-05-01'
        ApiKeys     = '/ApiKeys?api-version=2015-05-01'
        Diagnostics = '/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview'
        Roles       = "/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
    }
    $uris = [ordered]@{}
    foreach ($id in $ComponentId) { foreach ($k in $calls.Keys) { $uris["$id|$k"] = "$id$($calls[$k])" } }
    $answers = if ($uris.Count) { Invoke-AACArmParallel -Uri @($uris.Values) -ThrottleLimit $ThrottleLimit -OnProgress $OnProgress } else { @{} }
    $out = @{}
    foreach ($id in $ComponentId) {
        $out[$id] = @{}
        foreach ($k in $calls.Keys) { $out[$id][$k] = $answers[$uris["$id|$k"]] }
    }
    $out
}
