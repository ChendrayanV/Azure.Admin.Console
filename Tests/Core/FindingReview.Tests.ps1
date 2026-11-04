<#
    Unit tests for what the assessments share about their findings: the key that
    stays the same from run to run, the suppression file, and the comparison with
    an earlier run. Nothing signs in.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:finding = {
        param([string] $Check = 'Private API server', [string] $Cluster = 'aks-dev', [string] $Item = '', [string] $Severity = 'Medium', [string] $Detail = 'Some words')
        [pscustomobject][ordered]@{ PSTypeName = 'AAC.AksFinding'; Severity = $Severity; Check = $Check; Cluster = $Cluster; Item = $Item; Detail = $Detail }
    }
    $script:identity = { param($Row) InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $Row } { param($R) Get-AACFindingIdentity -Finding $R } }
    $script:review = {
        param([object[]] $Rows, [hashtable] $With = @{})
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = @{ Finding = $Rows } + $With } { param($P) Invoke-AACFindingReview @P }
    }
    $script:suppress = {
        param([string] $Json)
        $file = Join-Path -Path $TestDrive -ChildPath 'suppress.json'
        [System.IO.File]::WriteAllText($file, $Json)
        InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $file } { param($F) Read-AACSuppressionFile -Path $F -Now ([datetime]'2026-11-03') }
    }
}

Describe 'Azure Admin Console - a finding''s key' {
    It 'stays the same when its words and counts change' {
        $key = (& $script:identity (& $script:finding)).Key
        $key | Should -Match '^[0-9a-f]{16}$'
        (& $script:identity (& $script:finding -Detail 'Other words' -Severity 'High')).Key | Should -Be $key
        (& $script:identity (& $script:finding -Item '3 affected')).Key | Should -Be (& $script:identity (& $script:finding -Item '12 affected')).Key -Because 'a finding must not look new because it grew'
        (& $script:identity (& $script:finding -Item '50% registered')).Key | Should -Be (& $script:identity (& $script:finding -Item '80% registered')).Key
    }

    It 'differs for another rule, or what it is about' {
        $key = (& $script:identity (& $script:finding)).Key
        (& $script:identity (& $script:finding -Check 'OIDC issuer')).Key | Should -Not -Be $key
        (& $script:identity (& $script:finding -Cluster 'aks-prod')).Key | Should -Not -Be $key
        (& $script:identity (& $script:finding -Item 'pool-a')).Key | Should -Not -Be (& $script:identity (& $script:finding -Item 'pool-b')).Key
    }

    It 'reads every kind of finding, whichever fields it has' {
        $byResource = [pscustomobject]@{ PSTypeName = 'AAC.NetworkTopologyFinding'; Finding = 'Peering down'; Resource = 'vnet-a'; ResourceId = '/subscriptions/s/x' }
        $identity = & $script:identity $byResource
        "$($identity.Source)|$($identity.Rule)|$($identity.Subject)" | Should -Be 'NetworkTopology|Peering down|/subscriptions/s/x'
        $devops = [pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsFinding'; Severity = 'Low'; Organization = 'contoso'; Project = 'Pay'; Area = 'Pipeline'; Item = 'ci (#1)'; Finding = 'No tests' }
        $identity = & $script:identity $devops
        "$($identity.Source)|$($identity.Rule)|$($identity.Subject)" | Should -Be 'DevOps|No tests|contoso / Pay / Pipeline / ci (#1)'
    }
}

Describe 'Azure Admin Console - the suppression file' {
    It 'reads entries by key, and by source and rule' {
        $read = & $script:suppress '[{"key":"abc","reason":"Accepted"},{"source":"Aks","rule":"OIDC issuer","subject":"aks-*","reason":"Not used","expires":"2027-01-01"}]'
        @($read.Active).Count | Should -Be 2
        @($read.Active)[1].Expires | Should -Be ([datetime]'2027-01-01')
    }

    It 'sets expired entries aside, and takes a single entry too' {
        $read = & $script:suppress '[{"key":"abc","reason":"Old","expires":"2026-01-01"}]'
        @($read.Active).Count | Should -Be 0
        @($read.Expired).Count | Should -Be 1
    }

    It 'stops on a file it can''t understand, and says what to do' {
        foreach ($case in @(
                @{ Json = 'not json'; Says = "*isn't valid JSON*" }
                @{ Json = '{"key":"abc","reason":"x"}'; Says = '*has to be a JSON array*' }
                @{ Json = '[{"key":"abc"}]'; Says = '*entry 1 has no reason*' }
                @{ Json = '[{"key":"abc","reason":"   "}]'; Says = '*entry 1 has no reason*' }
                @{ Json = '[{"reason":"x","source":"Aks"}]'; Says = '*entry 1 needs a key, or a source and a rule*' }
                @{ Json = '[{"key":"abc","reason":"x"},{"key":"d","reason":"x","expires":"soon"}]'; Says = "*entry 2 has an expiry date that can't be read*" }
                @{ Json = '["abc"]'; Says = "*entry 1 isn't an object*" }
            )) {
            { & $script:suppress $case.Json } | Should -Throw $case.Says
        }
        { InModuleScope 'Azure.Admin.Console' { Read-AACSuppressionFile -Path 'C:\nowhere\none.json' } } | Should -Throw "*doesn't exist*Fix the file*"
    }
}

Describe 'Azure Admin Console - suppressing findings' {
    It 'takes a finding out of the findings and the counts, and keeps it with its reason' {
        $rows = @((& $script:finding), (& $script:finding -Check 'OIDC issuer' -Severity 'Low'))
        $key = (& $script:identity $rows[0]).Key
        $stats = [ordered]@{ Findings = 2; Medium = 1; Low = 1 }
        $answer = & $script:review $rows @{ Suppression = @{ Active = @(@{ Key = $key; Source = ''; Rule = ''; Subject = ''; Reason = 'Accepted'; Expires = [datetime]'2027-01-01' }); Expired = @() }; Stats = $stats }
        @($answer.Findings | ForEach-Object Check) | Should -Be @('OIDC issuer')
        "$(@($answer.Suppressed)[0].Check) | $(@($answer.Suppressed)[0].SuppressionReason) | $(@($answer.Suppressed)[0].SuppressedUntil)" | Should -Be 'Private API server | Accepted | 2027-01-01'
        "$($stats.Findings) $($stats.Medium) $($stats.Low)" | Should -Be '1 0 1'
        @($answer.Notices)[0] | Should -BeLike '1 finding(s) suppressed*'
    }

    It 'matches by source, rule and a subject with wildcards' {
        $rows = @((& $script:finding -Cluster 'aks-dev-1'), (& $script:finding -Cluster 'aks-prod-1'))
        $entry = @{ Key = ''; Source = 'aks'; Rule = 'private api*'; Subject = 'aks-dev-*'; Reason = 'Dev'; Expires = $null }
        $answer = & $script:review $rows @{ Suppression = @{ Active = @($entry); Expired = @() } }
        @($answer.Findings | ForEach-Object Cluster) | Should -Be @('aks-prod-1')
    }

    It 'reports an expired entry and one that matched nothing, and doesn''t apply them' {
        $old = @{ Key = (& $script:identity (& $script:finding)).Key; Source = ''; Rule = ''; Subject = ''; Reason = 'Old'; Expires = [datetime]'2026-01-01' }
        $stray = @{ Key = 'ffffffffffffffff'; Source = ''; Rule = ''; Subject = ''; Reason = 'Typo'; Expires = $null }
        $answer = & $script:review @(& $script:finding) @{ Suppression = @{ Active = @($stray); Expired = @($old) } }
        @($answer.Findings).Count | Should -Be 1
        ($answer.Notices -join ' ') | Should -BeLike '*1 suppression(s) have expired and were ignored*1 suppression(s) matched no finding*'
    }
}

Describe 'Azure Admin Console - comparing with an earlier run' {
    BeforeAll {
        $script:writeEarlier = {
            param([object[]] $Rows, [string] $Name = 'findings.csv')
            $null = & $script:review $Rows
            $path = Join-Path -Path $TestDrive -ChildPath $Name
            $Rows | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding utf8
            $path
        }
    }

    It 'marks each finding New or Open, and lists what was resolved' {
        $earlier = & $script:writeEarlier @((& $script:finding), (& $script:finding -Check 'Gone by now' -Severity 'High'))
        $answer = & $script:review @((& $script:finding), (& $script:finding -Check 'Brand new')) @{ PreviousPath = $earlier }
        @($answer.Findings | ForEach-Object { "$($_.Check): $($_.Change)" }) | Should -Be @('Private API server: Open', 'Brand new: New')
        @($answer.Resolved | ForEach-Object { "$($_.Severity) $($_.Finding) on $($_.Subject)" }) | Should -Be @('High Gone by now on aks-dev')
        "$($answer.Summary.New) $($answer.Summary.Open) $($answer.Summary.Resolved)" | Should -Be '1 1 1'
        ($answer.Notices -join ' ') | Should -BeLike '*1 new, 1 still open, 1 resolved*'
    }

    It 'doesn''t call a finding resolved because it was suppressed' {
        $earlier = & $script:writeEarlier @(& $script:finding)
        $entry = @{ Key = (& $script:identity (& $script:finding)).Key; Source = ''; Rule = ''; Subject = ''; Reason = 'Accepted'; Expires = $null }
        $answer = & $script:review @(& $script:finding) @{ PreviousPath = $earlier; Suppression = @{ Active = @($entry); Expired = @() } }
        @($answer.Resolved).Count | Should -Be 0
    }

    It 'takes the folder a run wrote its CSV files to' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'run1'
        $null = New-Item -ItemType Directory -Path $folder
        $null = & $script:writeEarlier @(& $script:finding) 'run1/findings.csv'
        @((& $script:review @(& $script:finding) @{ PreviousPath = $folder }).Findings)[0].Change | Should -Be 'Open'
    }

    It 'stops rather than calling everything new, when it can''t compare' {
        $path = Join-Path -Path $TestDrive -ChildPath 'old.csv'
        [pscustomobject]@{ Severity = 'High'; Check = 'x' } | Export-Csv -LiteralPath $path -NoTypeInformation
        { & $script:review @(& $script:finding) @{ PreviousPath = $path } } | Should -Throw '*no FindingKey column*'
        { & $script:review @(& $script:finding) @{ PreviousPath = (Join-Path -Path $TestDrive -ChildPath 'nope.csv') } } | Should -Throw "*couldn't find an earlier run's findings*"
    }

    It 'adds no Change column when there is nothing to compare with' {
        @((& $script:review @(& $script:finding)).Findings)[0].PSObject.Properties['Change'] | Should -BeNullOrEmpty
    }
}
