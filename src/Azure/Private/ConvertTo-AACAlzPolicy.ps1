function ConvertTo-AACAlzPolicy {
    <#
    .SYNOPSIS
        Compares the policy assignments deployed on each management group
        with what the Azure Landing Zones archetypes assign there:
        Test-AACAlzPolicy's list (AAC.AlzPolicyCheck).
    .DESCRIPTION
        No Azure calls. -Library is Read-AACAlzLibrary's result;
        -Assignment the deployed assignments (Resource Graph rows: id, name,
        displayName, scope, definitionId, enforcement); -ManagementGroup the
        tenant's management group names; -Map the library's management group
        IDs -> yours (unmapped ones keep the library's ID).

        A row per assignment an archetype makes on a management group:
          Missing   nothing with that name - or that definition - is
                    assigned there (Medium)
          Different assigned, but with another definition (an older or
                    newer version, or a replacement - Low), or not enforced
                    where the library enforces (Low)
          Present   assigned as the library has it
        A management group of the architecture that doesn't exist is one
        Info row, and its assignments aren't checked.
        Returns @{ Checks; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Library,

        [AllowEmptyCollection()]
        [object[]] $Assignment = @(),

        [AllowEmptyCollection()]
        [string[]] $ManagementGroup = @(),

        [hashtable] $Map = @{}
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $leaf = { param([string] $Id) ($Id -split '/')[-1].ToLowerInvariant() }
    $exists = @{}; foreach ($m in $ManagementGroup) { if ($m) { $exists[$m.ToLowerInvariant()] = $true } }
    $atScope = @{}
    foreach ($a in @($Assignment | Where-Object { $_ })) {
        $scope = (& $text $a 'scope').ToLowerInvariant()
        if (-not $atScope.Contains($scope)) { $atScope[$scope] = [System.Collections.Generic.List[object]]::new() }
        $atScope[$scope].Add($a)
    }
    $notices = [System.Collections.Generic.List[string]]::new()
    $checks = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Severity, [string] $Status, [string] $Archetype, $Group, [string] $Mine, [hashtable] $Expected, $Found, [string] $Finding)
        $item = [pscustomobject][ordered]@{
            Severity            = $Severity
            Status              = $Status
            Archetype           = $Archetype
            ManagementGroup     = $Mine
            LibraryGroup        = "$($Group.DisplayName) ($($Group.Id))"
            Assignment          = $(if ($Expected) { $Expected.Name } else { '' })
            DisplayName         = $(if ($Expected) { $Expected.DisplayName } else { '' })
            Finding             = $Finding
            Expected            = $(if ($Expected) { & $leaf $Expected.DefinitionId } else { '' })
            Deployed            = $(if ($Found) { & $leaf (& $text $Found 'definitionId') } else { '' })
            DeployedName        = $(if ($Found) { & $text $Found 'name' } else { '' })
            DeployedEnforcement = $(if ($Found) { $e = & $text $Found 'enforcement'; if ($e) { $e } else { 'Default' } } else { '' })
            LibraryFile         = $(if ($Expected) { $Expected.File } else { '' })
            ScopeId             = "/providers/microsoft.management/managementgroups/$Mine"
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.AlzPolicyCheck')
        $checks.Add($item)
    }

    foreach ($g in @($Library.ManagementGroups)) {
        $mine = $(if ($Map.Contains($g.Id)) { [string]$Map[$g.Id] } else { $g.Id }).ToLowerInvariant()
        if (-not $exists.Contains($mine)) {
            & $add 'Info' 'Not found' (@($g.Archetypes) -join ', ') $g $mine $null $null "No management group '$mine' in the tenant: map the library's '$($g.Id)' to yours with -ManagementGroupMap, or it isn't part of your design."
            continue
        }
        $deployed = @(if ($atScope.Contains("/providers/microsoft.management/managementgroups/$mine")) { $atScope["/providers/microsoft.management/managementgroups/$mine"] })
        foreach ($archetype in @($g.Archetypes)) {
            foreach ($name in @(if ($Library.Archetypes.Contains($archetype)) { $Library.Archetypes[$archetype] })) {
                $expected = if ($Library.Assignments.Contains(([string]$name).ToLowerInvariant())) { $Library.Assignments[([string]$name).ToLowerInvariant()] } else { $null }
                if (-not $expected) { $notices.Add("The library's archetype '$archetype' names an assignment '$name' it has no file for."); continue }
                $found = @($deployed | Where-Object { (& $text $_ 'name') -eq $expected.Name }) | Select-Object -First 1
                $byDefinition = $false
                if (-not $found) { $found = @($deployed | Where-Object { (& $leaf (& $text $_ 'definitionId')) -eq (& $leaf $expected.DefinitionId) }) | Select-Object -First 1; $byDefinition = [bool]$found }
                if (-not $found) {
                    & $add 'Medium' 'Missing' $archetype $g $mine $expected $null "Not assigned on ${mine}: the ALZ '$archetype' archetype assigns '$($expected.DisplayName)' here ($($expected.File) in the library has the assignment to deploy)."
                    continue
                }
                $differences = [System.Collections.Generic.List[string]]::new()
                if ((& $leaf (& $text $found 'definitionId')) -ne (& $leaf $expected.DefinitionId)) { $differences.Add("assigned with definition '$(& $leaf (& $text $found 'definitionId'))', the library uses '$(& $leaf $expected.DefinitionId)' (an older or newer version, or a replacement)") }
                $enforcement = & $text $found 'enforcement'
                if ($expected.Enforcement -eq 'Default' -and $enforcement -eq 'DoNotEnforce') { $differences.Add('not enforced (DoNotEnforce) where the library enforces') }
                if ($byDefinition) { $differences.Add("assigned as '$(& $text $found 'name')'") }
                if ($differences.Count -and -not ($byDefinition -and $differences.Count -eq 1)) { & $add 'Low' 'Different' $archetype $g $mine $expected $found ("Present, but " + ($differences -join '; ') + '.') }
                else { & $add 'Info' 'Present' $archetype $g $mine $expected $found $(if ($byDefinition) { "Present, $($differences[0])." } else { '' }) }
            }
        }
    }
    $rank = (Get-AACSeverityRank).Rank
    $order = @{ Missing = 0; Different = 1; 'Not found' = 2; Present = 3 }
    $sorted = @($checks | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, @{ Expression = { $order[$_.Status] } }, ManagementGroup, Assignment)
    $expectedCount = @($sorted | Where-Object Status -NE 'Not found').Count
    @{
        Checks  = $sorted
        Notices = @($notices)
        Stats   = @{
            Expected  = $expectedCount
            Present   = @($sorted | Where-Object Status -EQ 'Present').Count
            Missing   = @($sorted | Where-Object Status -EQ 'Missing').Count
            Different = @($sorted | Where-Object Status -EQ 'Different').Count
            NotFound  = @($sorted | Where-Object Status -EQ 'Not found').Count
            Coverage  = $(if ($expectedCount) { [Math]::Round(100.0 * @($sorted | Where-Object Status -In 'Present', 'Different').Count / $expectedCount, 1) } else { 0 })
        }
    }
}
