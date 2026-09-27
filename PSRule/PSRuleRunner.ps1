<#
    Runs PSRule for Azure in a PowerShell process of its own, for
    Invoke-AACPSRule - not meant to be run directly.

    PSRule loads its own YamlDotNet.dll, and .NET can hold only one version
    of an assembly per process. platyPS, powershell-yaml, Az.Aks and others
    ship different YamlDotNet versions, so in a session where one of them
    loaded first, running PSRule fails ("Could not load file or assembly
    ... YamlDotNet.dll ... manifest definition does not match") - and
    running PSRule first would break them instead. A child process avoids
    both.

    Reads the objects to check from -InputPath (JSON, the Export-AzRuleData
    shape) and the settings from -SettingPath:

      Rule           only these rules - names or wildcards
      ExcludeRule    leave out these rules - names or wildcards
      Baseline       a PSRule for Azure baseline
      Configuration  PSRule configuration values (PSRule for Azure's
                     AZURE_* options, and custom rules' own)
      RulePath       custom rule files or folders (*.Rule.ps1, *.Rule.yaml,
                     *.Rule.jsonc), run with PSRule for Azure's rules

    Writes each result, flattened to plain data, to -OutputPath as JSON.
    While it runs it writes 'PROGRESS <objects taken in>' lines to standard
    output and 'RULES <count>' once the rules are known; a failure is
    written as 'ERROR <message>' with exit code 1.
#>
param(
    [Parameter(Mandatory)] [string] $ModulePath,
    [Parameter(Mandatory)] [string] $InputPath,
    [Parameter(Mandatory)] [string] $SettingPath,
    [Parameter(Mandatory)] [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    $setting = Get-Content -LiteralPath $SettingPath -Raw | ConvertFrom-Json -AsHashtable
    Import-Module -Name $ModulePath -ErrorAction Stop -Verbose:$false -WarningAction SilentlyContinue

    $configuration = if ($setting.Configuration) { $setting.Configuration } else { @{} }
    $rulePath = @($setting.RulePath | Where-Object { $_ })
    $include = @($setting.Rule | Where-Object { $_ })
    $exclude = @($setting.ExcludeRule | Where-Object { $_ })
    $source = @{ Module = 'PSRule.Rules.Azure'; WarningAction = 'SilentlyContinue' }
    if ($rulePath) { $source.Path = $rulePath }

    # The rules to run: every rule of PSRule for Azure and the custom rule
    # files, narrowed by Rule and ExcludeRule - both matched as wildcards,
    # so 'Azure.Storage.*' or 'AAC.*' work.
    # PSRule for Azure's binding - what a resource's type and name are - for
    # every rule, so custom rules can use -Type 'Microsoft.Storage/...' too.
    $options = @{
        'Execution.UnprocessedObject' = 'Ignore'
        'Binding.TargetType'          = @('resourceType', 'type')
        'Binding.TargetName'          = @('ResourceName', 'name')
    }
    # The cultures PSRule reads rule help (synopsis, recommendation, link) in:
    # this session's, then en-US - each with its parents (en-US, then en), as
    # PSRule looks only in the folders named. Linux often runs with the
    # invariant culture (LANG=C.UTF-8), which on its own matches no help
    # folder at all.
    $cultures = [System.Collections.Generic.List[string]]::new()
    foreach ($culture in [System.Globalization.CultureInfo]::CurrentUICulture, [System.Globalization.CultureInfo]::GetCultureInfo('en-US')) {
        for ($c = $culture; $c.Name; $c = $c.Parent) {
            if (-not $cultures.Contains($c.Name)) { $cultures.Add($c.Name) }
        }
    }
    $options['Output.Culture'] = $cultures.ToArray()
    $all = @(Get-PSRule @source -Option (New-PSRuleOption -Option $options -Configuration $configuration) -ErrorAction Stop |
            ForEach-Object { [string]$_.Name } | Select-Object -Unique)
    $names = @($all | Where-Object {
            $name = $_
            ($include.Count -eq 0 -or @($include | Where-Object { $name -like $_ }).Count -gt 0) -and
            @($exclude | Where-Object { $name -like $_ }).Count -eq 0
        })
    [Console]::Out.WriteLine("RULES $($names.Count)")
    if ($names.Count -eq 0) {
        [System.IO.File]::WriteAllText($OutputPath, '[]', [System.Text.UTF8Encoding]::new($false))
        return
    }
    $invoke = @{
        Option  = (New-PSRuleOption -Option $options -Configuration $configuration)
        Outcome = 'Pass', 'Fail', 'Error'
    } + $source
    # When rules are left out, name the ones to run.
    if ($names.Count -lt $all.Count) {
        $invoke.Name = $names
    }
    if ($setting.Baseline) { $invoke.Baseline = $setting.Baseline }

    $objects = @(Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -Depth 100)
    $step = 0
    # A rule that fails on one resource (a setting it didn't expect) must be
    # that rule's Error result, not the end of the run: under 'Stop' its
    # error would stop every rule. PSRule records it in the result.
    $ErrorActionPreference = 'Continue'
    $results = @($objects | ForEach-Object {
            # Progress as PSRule takes each object in, in batches.
            if (++$step % 10 -eq 0) { [Console]::Out.WriteLine("PROGRESS $step") }
            $_
        } | Invoke-PSRule @invoke -ErrorAction SilentlyContinue)
    $ErrorActionPreference = 'Stop'

    $field = {
        param($Object, [string] $Name)
        if ($null -eq $Object) { return '' }
        $property = $Object.PSObject.Properties[$Name]
        if ($property -and $null -ne $property.Value) { [string]$property.Value } else { '' }
    }
    $flat = @(foreach ($result in $results) {
            $info = $result.Info
            $annotations = if ($info) { $info.Annotations } else { $null }
            $target = $result.TargetObject
            [ordered]@{
                RuleName          = [string]$result.RuleName
                ModuleName        = $(if ($info) { [string]$info.ModuleName } else { '' })
                Ref               = [string]$result.Ref
                Outcome           = [string]$result.Outcome
                Level             = [string]$result.Level
                Reason            = @($result.Reason | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() })
                Recommendation    = (([string]$result.Recommendation) -replace '\s+', ' ').Trim()
                ErrorMessage      = $(if ($result.Error) { [string]$result.Error.Message } else { '' })
                DisplayName       = $(if ($info) { [string]$info.DisplayName } else { '' })
                Synopsis          = $(if ($info) { [string]$info.Synopsis } else { '' })
                Link              = $(if ($annotations -and $annotations['online version']) { [string]$annotations['online version'] } else { '' })
                Severity          = $(if ($annotations -and $annotations['severity']) { [string]$annotations['severity'] } else { '' })
                Pillar            = $(if ($result.Tag) { [string]$result.Tag['Azure.WAF/pillar'] } else { '' })
                TargetName        = [string]$result.TargetName
                Name              = & $field $target 'name'
                Id                = & $field $target 'id'
                Type              = & $field $target 'type'
                ResourceGroupName = & $field $target 'resourceGroupName'
                SubscriptionId    = & $field $target 'subscriptionId'
            }
        })
    [System.IO.File]::WriteAllText($OutputPath, (ConvertTo-Json -InputObject $flat -Depth 5 -Compress), [System.Text.UTF8Encoding]::new($false))
    [Console]::Out.WriteLine("PROGRESS $($objects.Count)")
}
catch {
    [Console]::Out.WriteLine("ERROR $($_.Exception.Message -replace '\s+', ' ')")
    exit 1
}
