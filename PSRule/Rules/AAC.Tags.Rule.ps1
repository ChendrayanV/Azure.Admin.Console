# Azure.Admin.Console's own PSRule rules, run by Invoke-AACPSRule with PSRule
# for Azure's. They check what PSRule for Azure leaves to each organisation:
# which tags resources must carry, and the values they may have. They check
# the tags in Get-AACTagDefault below - empty as shipped, so they check
# nothing until tags are named there or in -Configuration (which wins):
#
#   Invoke-AACPSRule -Rule 'AAC.*' -Configuration @{
#       AAC_REQUIRED_TAGS      = @('Owner', 'CostCenter', 'Environment')
#       AAC_ALLOWED_TAG_VALUES = @{ Environment = @('prod', 'test', 'dev') }
#   }
#
# Invoke-AACPSRule says so when one of them runs with no tags to check.
# It reads Get-AACTagDefault too (without running this file): keep it a plain
# table of strings.
#
# Their help (synopsis, recommendation, links) is in en\<rule name>.md next to
# this file. Leave them out with -ExcludeRule 'AAC.*'.
#
# To add rules of your own, write them the same way - PowerShell
# (*.Rule.ps1), YAML (*.Rule.yaml) or JSON (*.Rule.jsonc); see
# https://microsoft.github.io/PSRule/v2/authoring/writing-rules/ - and pass
# their files or folder to Invoke-AACPSRule -RulePath.

# The tags checked when -Configuration names none. Add your organisation's
# here, e.g. RequiredTags = @('Owner', 'CostCenter', 'Environment') and
# AllowedValues = @{ Environment = @('prod', 'test', 'dev') }.
function global:Get-AACTagDefault {
    @{
        RequiredTags  = @()
        AllowedValues = @{}
    }
}

# The required tags: -Configuration's AAC_REQUIRED_TAGS, else the defaults.
function global:Get-AACRequiredTag {
    $configured = @($Configuration.GetStringValues('AAC_REQUIRED_TAGS') | Where-Object { $_ })
    if ($configured.Count) { return $configured }
    @((Get-AACTagDefault).RequiredTags | Where-Object { $_ })
}

# The allowed values: -Configuration's AAC_ALLOWED_TAG_VALUES, else the
# defaults - a hashtable, or an object when read from JSON; $null for none.
function global:Get-AACAllowedTagValue {
    $configured = $Configuration.GetValueOrDefault('AAC_ALLOWED_TAG_VALUES', $null)
    if ($null -ne $configured) { return $configured }
    $defaults = (Get-AACTagDefault).AllowedValues
    if ($defaults -and $defaults.Count) { return $defaults }
}

# A resource that can carry tags: anything under a resource provider - not a
# resource group or subscription, which have rules of their own.
function global:Test-AACTaggableResource {
    [string]$TargetObject.id -match '/providers/' -and [string]$TargetObject.type -notmatch '^microsoft\.(resources|subscription)'
}

# Synopsis: Resources carry every tag your organisation requires.
Rule 'AAC.Resource.RequiredTags' -Ref 'AAC-001' -Level Error -Tag @{ release = 'GA'; 'Azure.WAF/pillar' = 'Operational Excellence' } -If {
    (Test-AACTaggableResource) -and @(Get-AACRequiredTag).Count -gt 0
} {
    foreach ($name in Get-AACRequiredTag) {
        $Assert.HasFieldValue($TargetObject, "tags.$name").Reason('The required tag ''{0}'' is missing or empty.', $name)
    }
}

# Synopsis: Resource groups carry every tag your organisation requires.
Rule 'AAC.ResourceGroup.RequiredTags' -Ref 'AAC-002' -Level Error -Type 'Microsoft.Resources/resourceGroups' -Tag @{ release = 'GA'; 'Azure.WAF/pillar' = 'Operational Excellence' } -If {
    @(Get-AACRequiredTag).Count -gt 0
} {
    foreach ($name in Get-AACRequiredTag) {
        $Assert.HasFieldValue($TargetObject, "tags.$name").Reason('The required tag ''{0}'' is missing or empty.', $name)
    }
}

# Synopsis: Tags with a fixed set of values use one of them.
Rule 'AAC.Resource.AllowedTagValues' -Ref 'AAC-003' -Level Warning -Tag @{ release = 'GA'; 'Azure.WAF/pillar' = 'Operational Excellence' } -If {
    ((Test-AACTaggableResource) -or [string]$TargetObject.type -eq 'Microsoft.Resources/resourceGroups') -and
    $null -ne (Get-AACAllowedTagValue)
} {
    $allowed = Get-AACAllowedTagValue
    $names = if ($allowed -is [System.Collections.IDictionary]) { @($allowed.Keys) } else { @($allowed.PSObject.Properties.Name) }
    $checked = 0
    foreach ($name in $names) {
        $values = @($(if ($allowed -is [System.Collections.IDictionary]) { $allowed[$name] } else { $allowed.$name }) | ForEach-Object { [string]$_ })
        $tag = $TargetObject.tags.PSObject.Properties | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($tag) {
            $checked++
            $Assert.In($TargetObject, "tags.$($tag.Name)", $values).Reason('The tag ''{0}'' is ''{1}''; it should be one of: {2}.', $name, $tag.Value, ($values -join ', '))
        }
    }
    if ($checked -eq 0) {
        $Assert.Pass()
    }
}
