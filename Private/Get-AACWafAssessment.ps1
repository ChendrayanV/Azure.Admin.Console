function Get-AACWafAssessment {
    <#
    .SYNOPSIS
        The Well-Architected assessment Invoke-AACWafAssessment and
        Test-AACGoLiveReadiness share: the scope, the one Resource Graph batch
        (Get-AACWafQuery), the questionnaire's answers, and the scores
        (ConvertTo-AACWafAssessment) - with progress.
    .DESCRIPTION
        -Request: @{ SubscriptionId; ManagementGroupId; ResourceGroupName;
        Pillar; HeatMapBy; ExcludeCheck; NoAdvisor; NoDefender;
        AttestationPath (a full path, or empty); CostTag; OwnerTag;
        KeepDuplicates }.
        Returns @{ Result; Scope; Notices; Catalog }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Request
    )

    Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        $catalog = Get-AACWafCatalog
        $types = @($catalog.Checks | Where-Object { $_.Pillar -in $request.Pillar } | ForEach-Object { $_.Type } | Select-Object -Unique)
        $advisorCategory = @{ Reliability = 'HighAvailability'; Security = 'Security'; 'Cost Optimization' = 'Cost'; 'Operational Excellence' = 'OperationalExcellence'; 'Performance Efficiency' = 'Performance' }
        $categories = if ($request.NoAdvisor) { @() } else { @($request.Pillar | ForEach-Object { $advisorCategory[$_] }) }
        $queries = Get-AACWafQuery -ResourceType $types -ResourceGroupName $request.ResourceGroupName -AdvisorCategory $categories -NoDefender:($request.NoDefender -or 'Security' -notin $request.Pillar)
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading resources, backups, Advisor and Defender for Cloud (one Resource Graph batch)'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @($queries.Keys | Where-Object { $_ -ne 'resources' }) -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
        }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} resource(s) to check, {1:N0} Advisor recommendation(s), {2:N0} Defender assessment(s)' -f @($read.Rows['resources']).Count, @(if ($read.Rows.Contains('advisor')) { $read.Rows['advisor'] }).Count, @(if ($read.Rows.Contains('assessments')) { $read.Rows['assessments'] }).Count)
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read, so its checks are left out: $($read.Errors[$key] -replace '\s+', ' ')") }

        $attestation = @(if ($request.AttestationPath) { Read-AACWafAttestation -Path $request.AttestationPath -Catalog $catalog })
        if ($request.AttestationPath) { $notices.Add("$($attestation.Count) answer(s) read from the questionnaire $(Split-Path -Leaf $request.AttestationPath).") }

        Update-AACProgress -Id 'score' -Indeterminate -Description 'Evaluating the checks and scoring the principles'
        $names = @{}
        foreach ($id in $scope.Ids) { $names[$id.ToLowerInvariant()] = if ($scope.Names.Contains($id.ToLowerInvariant())) { $scope.Names[$id.ToLowerInvariant()] } else { $id } }
        $result = ConvertTo-AACWafAssessment -Read $read.Rows -Catalog $catalog -Pillar $request.Pillar -SubscriptionName $names -HeatMapBy $request.HeatMapBy -ExcludeCheck $request.ExcludeCheck -CostTag $request.CostTag -OwnerTag $request.OwnerTag -Attestation $attestation -KeepDuplicates:([bool]$request.KeepDuplicates)
        Update-AACProgress -Id 'score' -Complete -Description ('{0:N0} check(s) on {1:N0} resource(s): {2:N0} result(s), {3:N0} failed ({4:N0} high)' -f $result.Stats.Assessed, $result.Stats.Resources, $result.Stats.Results, $result.Stats.Failed, $result.Stats.High)
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray(); Catalog = $catalog }
    }
}
