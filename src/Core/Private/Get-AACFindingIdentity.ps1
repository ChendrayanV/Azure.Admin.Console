function Get-AACFindingIdentity {
    <#
    .SYNOPSIS
        What makes a finding the same one from run to run: its source, rule and
        subject, and the FindingKey made from them.
    .DESCRIPTION
        Findings differ by type, so this reads the fields they share: the rule is
        Check, or Finding, or Item; the subject is the ID or names of what it is about.
        Detail and Recommendation are left out, because their words and numbers change
        while the finding stays.

        So is a subject field that starts with a number, such as "3 admin(s)" or "50%
        registered": that is a count, and a finding must not look new because it grew.

        A CSV row from an earlier run has lost its type, so -Source is whatever it
        has, but such a row already has its FindingKey and only needs a rule and subject.

        Returns @{ Key; Source; Rule; Subject }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Finding
    )

    $read = { param([string] $Name) $p = $Finding.PSObject.Properties[$Name]; if ($p -and $null -ne $p.Value) { ([string]$p.Value).Trim() } else { '' } }
    $type = @($Finding.PSObject.TypeNames | Where-Object { $_ -like 'AAC.*' }) | Select-Object -First 1
    $source = if ($type) { ([string]$type) -replace '^AAC\.', '' -replace 'Finding$', '' } else { '' }
    $rule = foreach ($name in 'Check', 'Finding', 'Item') { $value = & $read $name; if ($value) { $value; break } }
    $parts = [System.Collections.Generic.List[string]]::new()
    $resourceId = & $read 'ResourceId'
    if ($resourceId) { $parts.Add($resourceId) }
    else {
        foreach ($name in 'Cluster', 'Organization', 'Project', 'Vault', 'Account', 'Database', 'Container', 'Namespace', 'Entity', 'App', 'Gateway', 'VirtualNetwork', 'Space', 'Principal', 'Component', 'Resource', 'Name', 'ResourceType', 'Category', 'Area', 'Item') {
            $value = & $read $name
            # Item is the rule itself when a finding has nothing else to go by.
            # A leading number on its own is a count; 3tier-vnet is a name.
            if ($value -and $value -ne $rule -and $value -notmatch '^\d+(\.\d+)?%?(\s|$)') { $parts.Add($value) }
        }
    }
    $subject = $parts -join ' / '
    $text = "$source|$rule|$subject".ToLowerInvariant()
    $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($text))
    @{ Key = ([System.Convert]::ToHexString($hash).Substring(0, 16).ToLowerInvariant()); Source = $source; Rule = [string]$rule; Subject = $subject }
}
