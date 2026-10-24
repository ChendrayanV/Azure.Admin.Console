function ConvertTo-AACSecurityRecommendation {
    <#
    .SYNOPSIS
        Turns Defender for Cloud's unhealthy assessments (the Recommendations
        query of Get-AACDefenderQuery) into AAC.SecurityRecommendation
        objects - one per recommendation and resource, most severe first.
        Shared by Get-AACInventory and Get-AACSecurityPosture.
    .DESCRIPTION
        The resource's name, type and resource group come from its ID;
        -SubscriptionName names the subscriptions; -ControlOf (assessment key
        -> secure score control) names the control each recommendation
        belongs to. RemediationUrl is the recommendation's page in the Azure
        portal.
    #>
    [CmdletBinding()]
    [OutputType('AAC.SecurityRecommendation')]
    param(
        [AllowEmptyCollection()]
        [object[]] $Row = @(),

        [hashtable] $SubscriptionName = @{},

        [hashtable] $ControlOf = @{}
    )

    $value = { param($Object, [string] $Key) if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Key)) { $Object[$Key] } } else { Get-AACPropertyValue -InputObject $Object -Name $Key } }
    $text = { param($Object, [string] $Key) $v = & $value $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $severityRank = @{ High = 0; Medium = 1; Low = 2 }
    $items = @(foreach ($entry in $Row) {
            $id = & $text $entry 'resourceId'
            $subscriptionId = (& $text $entry 'subscriptionId').ToLowerInvariant()
            if (-not $subscriptionId -and $id -match '^/subscriptions/([^/]+)') { $subscriptionId = $Matches[1] }
            $type = if ($id -match '/providers/(.+)$') {
                $segments = $Matches[1] -split '/'
                # Namespace, then every other segment: microsoft.sql/servers/databases.
                ((@($segments[0]) + @(for ($i = 1; $i -lt $segments.Count; $i += 2) { $segments[$i] })) -join '/').ToLowerInvariant()
            }
            elseif ($id -match '^/subscriptions/[^/]+/resourcegroups/[^/]+$') { 'microsoft.resources/resourcegroups' }
            elseif ($id -match '^/subscriptions/[^/]+$') { 'microsoft.resources/subscriptions' }
            else { '' }
            $subscriptionLabel = if ($SubscriptionName.Contains($subscriptionId)) { $SubscriptionName[$subscriptionId] } else { $subscriptionId }
            $key = (& $text $entry 'key').ToLowerInvariant()
            $link = & $text $entry 'link'
            $since = [datetime]::MinValue
            [pscustomobject][ordered]@{
                PSTypeName       = 'AAC.SecurityRecommendation'
                Recommendation   = & $text $entry 'name'
                Severity         = & $text $entry 'severity'
                Impact           = & $text $entry 'impact'
                Effort           = & $text $entry 'effort'
                Category         = & $text $entry 'categories'
                Control          = $(if ($key -and $ControlOf.Contains($key)) { $ControlOf[$key] } else { '' })
                Resource         = $(if ($type -eq 'microsoft.resources/subscriptions') { $subscriptionLabel } elseif ($id) { ($id -split '/')[-1] } else { '' })
                Type             = $type
                ResourceGroup    = $(if ($id -match '/resourcegroups/([^/]+)') { $Matches[1] } else { '' })
                SubscriptionName = $subscriptionLabel
                SubscriptionId   = $subscriptionId
                Cause            = & $text $entry 'cause'
                Description      = & $text $entry 'description'
                Remediation      = & $text $entry 'remediation'
                RemediationUrl   = $(if ($link) { if ($link -match '^https?://') { $link } else { "https://$link" } } else { '' })
                Since            = $(if ([datetime]::TryParse((& $text $entry 'since'), [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$since)) { $since } else { $null })
                ResourceId       = $id
                AssessmentKey    = $key
            }
        })
    @($items | Sort-Object -Property @{ Expression = { if ($severityRank.Contains($_.Severity)) { $severityRank[$_.Severity] } else { 3 } } }, Recommendation, Resource)
}
