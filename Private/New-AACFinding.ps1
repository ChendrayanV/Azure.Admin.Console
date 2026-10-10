function New-AACFinding {
    <#
    .SYNOPSIS
        Makes one finding in the shape every expert command (cost, access,
        attack paths, health, compliance, failover, dependencies,
        utilization, drift) returns, so findings sort, filter and export the
        same way everywhere.
    .DESCRIPTION
        Severity     Critical, High, Medium, Low or Info
        Category     what kind of finding ('Standing privileged access', ...)
        Finding      what was found, in one line
        Resource, ResourceType, ResourceGroup, Subscription, ResourceId
        Detail       the evidence
        Impact       why it matters - the business impact
        Remediation  what to do
        Effort       Low, Medium or High - to put quick wins first
        Link         where to read more (https)
        -Property adds command-specific properties after these.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a new object; nothing outside the process changes.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $TypeName,

        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string] $Severity,

        [Parameter(Mandatory)]
        [string] $Category,

        [Parameter(Mandatory)]
        [string] $Finding,

        [string] $ResourceId,

        [string] $Resource,

        [string] $ResourceType,

        [string] $ResourceGroup,

        [string] $Subscription,

        [string] $Detail,

        [string] $Impact,

        [string] $Remediation,

        [ValidateSet('', 'Low', 'Medium', 'High')]
        [string] $Effort = '',

        [string] $Link,

        [System.Collections.IDictionary] $Property = @{}
    )

    $item = [ordered]@{
        Severity      = $Severity
        Category      = $Category
        Finding       = $Finding
        Resource      = $(if ($Resource) { $Resource } elseif ($ResourceId) { ($ResourceId.TrimEnd('/') -replace '^.*/', '') } else { '' })
        ResourceType  = $(if ($ResourceType) { $ResourceType } elseif ($ResourceId -match '(?i)/providers/(.+)/[^/]+$') { ($Matches[1] -replace '/[^/]+/(?=[^/]+$)', '/').ToLowerInvariant() } else { '' })
        ResourceGroup = $(if ($ResourceGroup) { $ResourceGroup } elseif ($ResourceId -match '(?i)/resourceGroups/([^/]+)') { $Matches[1] } else { '' })
        Subscription  = $Subscription
        Detail        = $Detail
        Impact        = $Impact
        Remediation   = $Remediation
        Effort        = $Effort
        Link          = $Link
        ResourceId    = $ResourceId
    }
    foreach ($key in $Property.Keys) { $item[[string]$key] = $Property[$key] }
    $object = [pscustomobject]$item
    $object.PSObject.TypeNames.Insert(0, $TypeName)
    $object
}
