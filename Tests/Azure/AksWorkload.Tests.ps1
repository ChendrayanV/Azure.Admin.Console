<#
    Unit tests for Invoke-AACAksAssessment -IncludeWorkload: the read through AKS
    run command, the checks on what runs in a cluster, and readiness for AKS
    Automatic, on a made-up cluster (Fixtures\ContosoAksKubernetes). Nothing signs
    in. The one test that needs jq runs the real filters against a fake kubectl.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:hasJq = [bool](Get-Command -Name 'jq' -ErrorAction Ignore) -and [bool](Get-Command -Name 'bash' -ErrorAction Ignore)
}

BeforeAll {
    $fixtures = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures'
    . (Join-Path -Path $fixtures -ChildPath 'ContosoAksKubernetes.ps1')
    . (Join-Path -Path $fixtures -ChildPath 'ContosoAks.ps1')
    $script:rawPath = Join-Path -Path $fixtures -ChildPath 'ContosoAksKubernetes.json'
    $script:logs = Get-AACContosoAksKubernetes
    $script:clusterId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks'
    # The read, as Get-AACAksWorkload does it, from what each command answers.
    $script:read = {
        param([string] $Workloads = $script:logs.Workloads, [string] $Cluster = $script:logs.Cluster)
        $script:answer = @{ Workloads = $Workloads; Cluster = $Cluster }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACAksRunCommand -MockWith {
            @{ Status = 'OK'; Logs = $(if ($Command -match '(?m)^q pods ') { $script:answer.Workloads } else { $script:answer.Cluster }) }
        }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ Id = $script:clusterId } { param($Id) Get-AACAksWorkload -ClusterId $Id }
    }
    $script:convert = {
        param([hashtable] $From, [hashtable] $With = @{})
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = @{ Read = $From; ClusterName = 'aks'; ClusterId = 'id' } + $With } { param($P) ConvertTo-AACAksWorkload @P }
    }
    $script:model = & $script:convert (& $script:read)
    $script:checkOf = { param([string] $Check, $From = $script:model) $From.Checks | Where-Object Check -EQ $Check | Select-Object -First 1 }
    $script:found = { param([string] $Check, $From = $script:model) @($From.Items | Where-Object Check -EQ $Check | ForEach-Object Name) }
}

Describe 'Azure Admin Console - reading what runs in a cluster' {
    It 'reads every record, and has nothing unread when both commands finish' {
        $result = & $script:read
        $result.Status | Should -Be 'OK'
        @($result.Unread).Count | Should -Be 0
        @($result.Rows | Where-Object { $_['t'] -eq 'pod' }).Count | Should -Be 6
    }

    It 'runs only kubectl get, and never asks for secrets or configmaps' {
        foreach ($entry in (InModuleScope 'Azure.Admin.Console' { Get-AACAksWorkloadCommand })) {
            $verbs = @([regex]::Matches($entry.Command, 'kubectl (\w+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            $verbs | Should -Be @('get')
            $entry.Command | Should -Not -Match '(?m)^q (secrets|configmaps)'
            $entry.Command | Should -Not -Match '\.value\b(?!\s*(!=|==))' -Because 'no environment value may leave the cluster'
            foreach ($kind in $entry.Kinds) { $entry.Command | Should -Match "(?m)^q $([regex]::Escape($kind)) '" }
        }
    }

    It 'keeps the filters free of single quotes, which would end them in the shell' {
        foreach ($entry in (InModuleScope 'Azure.Admin.Console' { Get-AACAksWorkloadCommand })) {
            foreach ($line in $entry.Command -split "`n" | Where-Object { $_ -like 'q *' }) { ([regex]::Matches($line, "'")).Count | Should -Be 2 }
        }
    }

    It 'notices an answer cut off at 512 kB: no end marker, or a broken line' {
        $cut = $script:logs.Workloads -replace '\nAAC_END$', ''
        @((& $script:read -Workloads $cut).Unread) | Should -Contain 'pods'
        $broken = '{"t":"pod","ns":"sh' + "`n" + $script:logs.Workloads
        @((& $script:read -Workloads $broken).Unread) | Should -Contain 'pods'
    }

    It 'notes a kind kubectl was refused, and still reads the others' {
        $result = & $script:read -Cluster ('{"t":"error","k":"clusterrolebindings"}' + "`n" + $script:logs.Cluster)
        @($result.Unread) | Should -Be @('clusterrolebindings')
        @($result.Rows | Where-Object { $_['t'] -eq 'error' }).Count | Should -Be 0
    }

    It 'says why when neither command could run' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACAksRunCommand -MockWith { @{ Status = "Couldn't start the command: Run command is disabled"; Logs = '' } }
        (InModuleScope 'Azure.Admin.Console' -Parameters @{ Id = $script:clusterId } { param($Id) Get-AACAksWorkload -ClusterId $Id }).Status | Should -BeLike '*Run command is disabled*'
    }

    It 'gets the same answers from the real filters' -Skip:(-not $script:hasJq) {
        $answers = foreach ($entry in (InModuleScope 'Azure.Admin.Console' { Get-AACAksWorkloadCommand })) {
            $script = Join-Path -Path $TestDrive -ChildPath 'run.sh'
            $fake = 'kubectl() { jq -c --arg k "$2" ''.[$k]'' "$AAC_FIXTURE"; }'
            [System.IO.File]::WriteAllText($script, ($fake + "`n" + $entry.Command + "`n"))
            $env:AAC_FIXTURE = $script:rawPath
            (& bash $script) -join "`n"
        }
        $real = & $script:convert (& $script:read -Workloads $answers[0] -Cluster $answers[1])
        $real.Checks | ForEach-Object { "$($_.Check): $($_.Status) $($_.Affected)" } | Should -Be @($script:model.Checks | ForEach-Object { "$($_.Check): $($_.Status) $($_.Affected)" })
        @($real.Items | ForEach-Object { "$($_.Check)|$($_.Name)|$($_.Detail)" }) | Should -Be @($script:model.Items | ForEach-Object { "$($_.Check)|$($_.Name)|$($_.Detail)" })
    }
}

Describe 'Azure Admin Console - the in-cluster checks' {
    It 'passes the healthy namespace and fails the other, workload by workload' {
        foreach ($check in 'Resource requests', 'Readiness and liveness probes', 'Privileged containers', 'Host namespaces', 'hostPath volumes', 'Host ports', 'Added Linux capabilities', 'Unconfined seccomp profile', 'Images without a version') {
            (& $script:checkOf $check).Status | Should -Be 'Fail' -Because $check
            & $script:found $check | Should -Contain 'api' -Because $check
            & $script:found $check | Should -Not -Contain 'web' -Because $check
        }
    }

    It 'finds the failing, pending and restarting, by their workloads' {
        (& $script:found 'Containers failing to start or run') | Should -Be @('api')
        (& $script:found 'Failed pods') | Should -Be @('nightly')
        (& $script:found 'Pending pods') | Should -Be @('debug')
        (& $script:found 'Containers killed for memory') | Should -Be @('api')
        (& $script:found 'Containers restarting often') | Should -Be @('api')
        (& $script:found 'Workloads short of replicas') | Should -Be @('api')
        (& $script:found 'Nodes not ready') | Should -Be @('aks-apps-2')
        (& $script:found 'Nodes under pressure') | Should -Be @('aks-apps-2')
        (& $script:found 'Services with no ready endpoints') | Should -Be @('api')
        (& $script:found 'Persistent volume claims not bound') | Should -Be @('ledger')
        (& $script:found 'Autoscalers with no target') | Should -Be @('old')
    }

    It 'turns a pod''s owner into its workload, and counts pods with no controller' {
        (& $script:found 'Pods with no controller') | Should -Be @('debug')
        ($script:model.Items | Where-Object { $_.Check -eq 'Failed pods' }).Kind | Should -Be 'CronJob'
    }

    It 'says what is wrong, down to the container' {
        ($script:model.Items | Where-Object { $_.Check -eq 'Added Linux capabilities' }).Detail | Should -Be 'api: SYS_ADMIN' -Because 'NET_BIND_SERVICE is in the baseline standard'
        ($script:model.Items | Where-Object { $_.Check -eq 'Containers that may run as root' -and $_.Name -eq 'api' }).Detail | Should -BeLike '*seed: runAsUser 0*' -Because 'init containers count for security'
        (& $script:found 'Containers that may run as root') | Should -Not -Contain 'web' -Because 'the pod sets it, and its containers inherit it'
        (& $script:checkOf 'Unconfined seccomp profile').Detail | Should -Be '1 found: payments/api'
    }

    It 'leaves out probes for jobs, and single replicas for daemon sets' {
        (& $script:found 'Readiness and liveness probes') | Should -Not -Contain 'nightly'
        (& $script:found 'Single-replica workloads') | Should -Be @('ingress-nginx-controller')
    }

    It 'matches disruption budgets to workloads by their labels' {
        (& $script:found 'Pod disruption budgets') | Should -BeNullOrEmpty
        (& $script:found 'Disruption budgets that block node drains') | Should -Be @('api')
        (& $script:found 'Replicas spread across nodes') | Should -Be @('api')
    }

    It 'leaves the system namespaces out, unless asked' {
        (& $script:found 'Privileged containers') | Should -Not -Contain 'coredns'
        (& $script:found 'Namespaces with no network policy') | Should -Not -Contain 'kube-system'
        $all = & $script:convert (& $script:read) @{ IncludeSystemNamespace = $true }
        (& $script:found 'Privileged containers' $all) | Should -Contain 'coredns'
    }

    It 'finds namespaces missing their safeguards' {
        (& $script:found 'Namespaces with no network policy') | Should -Be @('default', 'payments')
        (& $script:found 'Namespaces with no Pod Security label') | Should -Be @('default', 'payments')
    }

    It 'counts only access someone holds, and not AKS''s own' {
        (& $script:found 'cluster-admin bindings to review') | Should -Be @('ops-admins', 'default-admin')
        (& $script:found 'Roles bound to anyone or every signed-in user') | Should -Be @('everyone') -Because 'system:basic-user is meant for everyone'
        (& $script:found 'Default service accounts with wide access') | Should -Be @('default-admin')
        (& $script:found 'Wildcard roles in use') | Should -Be @('all-of-it') -Because 'nobody holds unused-wide'
        (& $script:found 'Roles that can gain more access') | Should -Be @('act-as')
    }

    It 'reads services and storage' {
        (& $script:found 'Public load balancer services') | Should -Be @('api') -Because 'private has the internal annotation'
        (& $script:found 'Services with external IPs') | Should -Be @('legacy')
        (& $script:found 'Services sharing a selector') | Should -Be @('api', 'api-copy')
        (& $script:found 'Community ingress-nginx in use') | Should -Be @('ingress-nginx-controller')
        (& $script:found 'In-tree storage provisioners') | Should -Be @('old-disk')
    }
}

Describe 'Azure Admin Console - gaps in what was read' {
    It 'doesn''t pass what it couldn''t read, and still fails what it could' {
        $read = & $script:read -Cluster ('{"t":"error","k":"clusterrolebindings"}' + "`n" + ($script:logs.Cluster -replace '(?m)^.*"kind":"ClusterRoleBinding".*\n', ''))
        $gaps = & $script:convert $read
        (& $script:checkOf 'cluster-admin bindings to review' $gaps).Status | Should -Be 'Not checked'
        (& $script:checkOf 'cluster-admin bindings to review' $gaps).Detail | Should -BeLike '*clusterrolebindings*'
        $partial = & $script:read -Workloads ($script:logs.Workloads -replace '\nAAC_END$', '')
        $model = & $script:convert $partial
        (& $script:checkOf 'Privileged containers' $model).Status | Should -Be 'Fail'
        (& $script:checkOf 'Privileged containers' $model).Detail | Should -BeLike '*There may be more*'
        (& $script:checkOf 'Host namespaces' $model).Status | Should -Be 'Fail'
    }

    It 'says Not fully checked for AKS Automatic rather than No blockers found' {
        $clean = @{ Rows = @(); Unread = @('pods'); Status = 'OK' }
        (& $script:convert $clean).Readiness.Verdict | Should -Be 'Not fully checked'
        (& $script:convert @{ Rows = @(); Unread = @(); Status = 'OK' }).Readiness.Verdict | Should -Be 'No blockers found'
    }
}

Describe 'Azure Admin Console - moving to AKS Automatic' {
    It 'sorts what it found by what Automatic would do' {
        $script:model.Readiness.Verdict | Should -Be 'Fix first'
        (& $script:checkOf 'Readiness and liveness probes').Readiness | Should -Be 'Fix first' -Because 'Deployment Safeguards has no mutation for probes, so it refuses them'
        (& $script:checkOf 'Resource requests').Readiness | Should -Be 'Changed by Automatic' -Because 'the mutator sets default requests'
        (& $script:checkOf 'Replicas spread across nodes').Readiness | Should -Be 'Changed by Automatic' -Because 'the mutator adds anti-affinity'
        (& $script:checkOf 'Containers that may run as root').Readiness | Should -Be 'Review' -Because 'only the restricted standard refuses root'
        $script:model.Readiness.FixFirst | Should -BeGreaterThan 0
    }

    It 'says so when the cluster already is AKS Automatic' {
        (& $script:convert (& $script:read) @{ ClusterSku = 'Automatic' }).Readiness.Verdict | Should -Be 'Already AKS Automatic'
    }
}

Describe 'Azure Admin Console - Invoke-AACAksAssessment with what runs in the cluster' {
    BeforeAll {
        $script:f = Get-AACContosoAks
        $script:assess = {
            param([hashtable] $Reads)
            InModuleScope 'Azure.Admin.Console' -Parameters @{ P = @{ Cluster = $script:f.Clusters; Workload = $Reads; Now = [datetime]'2026-10-05' } } { param($P) ConvertTo-AACAksAssessment @P }
        }
        $script:good = & $script:read
        $script:with = & $script:assess @{ $script:f.ProdId.ToLowerInvariant() = $script:good }
        $script:without = & $script:assess @{}
        $script:capture = {
            param([scriptblock] $Render)
            $real = [Spectre.Console.AnsiConsole]::Console
            $buffer = [System.IO.StringWriter]::new()
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            $settings.Enrichment.UseDefaultEnrichers = $false
            $console = [Spectre.Console.AnsiConsole]::Create($settings)
            $console.Profile.Width = 200
            try { [Spectre.Console.AnsiConsole]::Console = $console; $null = & $Render }
            finally { [Spectre.Console.AnsiConsole]::Console = $real }
            $buffer.ToString()
        }
    }

    It 'adds failures to the findings, and leaves the Well-Architected score alone' {
        @($script:with.Findings | Where-Object Source -EQ 'In-cluster').Count | Should -BeGreaterThan 20
        @($script:without.Findings | Where-Object Source -EQ 'In-cluster').Count | Should -Be 0
        $script:with.Stats.WafScore | Should -Be $script:without.Stats.WafScore
        @($script:with.Clusters | Where-Object Name -EQ 'aks-prod-weu')[0].AutomaticReadiness | Should -Be 'Fix first'
        @($script:with.Clusters | Where-Object Name -EQ 'aks-dev')[0].AutomaticReadiness | Should -Be ''
    }

    It 'shows it at the prompt, and writes it to the CSV files and reports' {
        $text = & $script:capture { InModuleScope 'Azure.Admin.Console' -Parameters @{ A = $script:with } { param($A) Show-AACAksView -Assessment $A } }
        foreach ($expected in 'In the cluster', 'Fix first', 'not in the WAF score') { $text | Should -Match ([regex]::Escape($expected)) }
        $folder = Join-Path -Path $TestDrive -ChildPath 'aks'
        $null = InModuleScope 'Azure.Admin.Console' -Parameters @{ A = $script:with; Folder = $folder } { param($A, $Folder) Write-AACAksCsv -Assessment $A -Path $Folder }
        foreach ($name in 'in-cluster-checks.csv', 'in-cluster-items.csv', 'automatic-readiness.csv') { Join-Path -Path $folder -ChildPath $name | Should -Exist }
        $html = Join-Path -Path $TestDrive -ChildPath 'aks.html'
        $null = InModuleScope 'Azure.Admin.Console' -Parameters @{ A = $script:with; File = $html } { param($A, $File) Write-AACAksHtml -Assessment $A -Path $File -Title 'AKS' -Detail ([ordered]@{}) }
        foreach ($expected in 'Moving to AKS Automatic', 'Community ingress-nginx in use') { (Get-Content -LiteralPath $html -Raw) | Should -Match ([regex]::Escape($expected)) }
    }

    It 'writes it to the PDF' -Skip:(-not ($IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4')) {
        $pdf = Join-Path -Path $TestDrive -ChildPath 'aks.pdf'
        $null = InModuleScope 'Azure.Admin.Console' -Parameters @{ A = $script:with; File = $pdf } { param($A, $File) Write-AACAksPdf -Assessment $A -Path $File -Title 'AKS' -Detail ([ordered]@{ Scope = 'test' }) }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }

    It 'adds nothing to the reports when it wasn''t asked for' {
        @($script:without.WorkloadChecks).Count | Should -Be 0
        $text = & $script:capture { InModuleScope 'Azure.Admin.Console' -Parameters @{ A = $script:without } { param($A) Show-AACAksView -Assessment $A } }
        $text | Should -Not -Match 'not in the WAF score'
    }
}
