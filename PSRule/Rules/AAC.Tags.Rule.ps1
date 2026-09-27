# Azure.Admin.Console's own PSRule rules, run by Invoke-AACPSRule with PSRule
# for Azure's. They check what PSRule for Azure leaves to each organisation:
# which tags resources must carry, and the values they may have. Each rule
# does nothing until its setting is given, e.g.
#
#   Invoke-AACPSRule -Configuration @{
#       AAC_REQUIRED_TAGS      = @('Owner', 'CostCenter', 'Environment')
#       AAC_ALLOWED_TAG_VALUES = @{ Environment = @('prod', 'test', 'dev') }
#   }
#
# Their help (synopsis, recommendation, links) is in en\<rule name>.md next to
# this file. Leave them out with -ExcludeRule 'AAC.*'.
#
# To add rules of your own, write them the same way - PowerShell
# (*.Rule.ps1), YAML (*.Rule.yaml) or JSON (*.Rule.jsonc); see
# https://microsoft.github.io/PSRule/v2/authoring/writing-rules/ - and pass
# their files or folder to Invoke-AACPSRule -RulePath.

# A resource that can carry tags: anything under a resource provider - not a
# resource group or subscription, which have rules of their own.
function global:Test-AACTaggableResource {
    [string]$TargetObject.id -match '/providers/' -and [string]$TargetObject.type -notmatch '^microsoft\.(resources|subscription)'
}

# Synopsis: Resources carry every tag your organisation requires.
Rule 'AAC.Resource.RequiredTags' -Ref 'AAC-001' -Level Error -Tag @{ release = 'GA'; 'Azure.WAF/pillar' = 'Operational Excellence' } -If {
    (Test-AACTaggableResource) -and @($Configuration.GetStringValues('AAC_REQUIRED_TAGS')).Count -gt 0
} {
    foreach ($name in $Configuration.GetStringValues('AAC_REQUIRED_TAGS')) {
        $Assert.HasFieldValue($TargetObject, "tags.$name").Reason('The required tag ''{0}'' is missing or empty.', $name)
    }
}

# Synopsis: Resource groups carry every tag your organisation requires.
Rule 'AAC.ResourceGroup.RequiredTags' -Ref 'AAC-002' -Level Error -Type 'Microsoft.Resources/resourceGroups' -Tag @{ release = 'GA'; 'Azure.WAF/pillar' = 'Operational Excellence' } -If {
    @($Configuration.GetStringValues('AAC_REQUIRED_TAGS')).Count -gt 0
} {
    foreach ($name in $Configuration.GetStringValues('AAC_REQUIRED_TAGS')) {
        $Assert.HasFieldValue($TargetObject, "tags.$name").Reason('The required tag ''{0}'' is missing or empty.', $name)
    }
}

# Synopsis: Tags with a fixed set of values use one of them.
Rule 'AAC.Resource.AllowedTagValues' -Ref 'AAC-003' -Level Warning -Tag @{ release = 'GA'; 'Azure.WAF/pillar' = 'Operational Excellence' } -If {
    ((Test-AACTaggableResource) -or [string]$TargetObject.type -eq 'Microsoft.Resources/resourceGroups') -and
    $null -ne $Configuration.GetValueOrDefault('AAC_ALLOWED_TAG_VALUES', $null)
} {
    $allowed = $Configuration.GetValueOrDefault('AAC_ALLOWED_TAG_VALUES', $null)
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
