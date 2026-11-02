<#
    Unit tests for Invoke-AACActivityLogAssessment, with Resource Graph,
    Resource Manager, the Activity Log REST API and Log Analytics faked over
    a made-up Contoso estate (Fixtures/ContosoActivityLog.ps1): which source
    each subscription is read from, the distinct activity, last used, idle
    and deleted resources, the findings, the views and the reports - and
    the workspace query on its own.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoActivityLog.ps1')
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 220
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - the Activity Log workspace query' {
    It 'summarises in the workspace: one row per operation, then per resource, caller, operation and status' {
        $query = InModuleScope 'Azure.Admin.Console' {
            Get-AACActivityLogQuery -SubscriptionId '11111111-1111-1111-1111-111111111111' -Start ([datetime]'2026-01-01Z') -End ([datetime]'2026-02-01Z') -ResourceGroupName 'rg-data'
        }
        $query | Should -Match "^AzureActivity"
        $query | Should -Match "TimeGenerated >= datetime\(2026-01-01T00:00:00Z\) and TimeGenerated < datetime\(2026-02-01T00:00:00Z\)"
        $query | Should -Match "CategoryValue in~ \('Administrative'\)"
        $query | Should -Match "ResourceGroup in~ \('rg-data'\)"
        $query | Should -Match "column_ifexists\('Claims_d'"
        $query | Should -Match 'arg_max\(TimeGenerated, ActivityStatusValue'
        $query | Should -Match 'summarize Count = count\(\), First = min\(TimeGenerated\)'
        $query | Should -Match 'arg_max\(TimeGenerated, CorrelationId, StatusMessage' -Because 'each row keeps its latest operation, and why it failed'
        $query | Should -Match "case\(Status =~ 'Failure', 'Failed'" -Because 'AzureActivity says Failure where the REST API says Failed'
        (InModuleScope 'Azure.Admin.Console' { Get-AACActivityLogQuery -SubscriptionId 'x' -Start ([datetime]'2026-01-01Z') -End ([datetime]'2026-02-01Z') -Category All }) | Should -Not -Match 'CategoryValue in'
    }
}

Describe 'Azure Admin Console - Invoke-AACActivityLogAssessment' {
    BeforeEach {
        $script:f = Get-AACContosoActivityLog
        $script:apiUris = [System.Collections.Generic.List[string]]::new()
        $script:logQueries = [System.Collections.Generic.List[object]]::new()
        $script:failWorkspace = $false
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { @{ Rows = @{ subscriptions = @($script:f.Subscriptions) }; Errors = @{} } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            # Every event in sub-dev's first slice of each run, so each is read once.
            $first = @($Uri | Where-Object { $_ -match 'eventtypes' -and $_ -match $script:f.Dev } | Select-Object -First 1)
            foreach ($u in $Uri) {
                $sub = ($u -split '/')[2]
                $answers[$u] = if ($u -match 'diagnosticSettings') { @{ Status = 200; Items = @($script:f.Settings[$sub]); Error = '' } }
                elseif ($u -match 'workspaces/law-central\?') { @{ Status = 200; Body = $script:f.Workspace; Items = $null; Error = '' } }
                elseif ($u -match '/resources\?') { @{ Status = 200; Items = @($script:f.Resources[$sub] | ForEach-Object { $_.Clone() }); Error = '' } }
                elseif ($u -match 'eventtypes') {
                    $script:apiUris.Add($u)
                    @{ Status = 200; Items = $(if ($first.Count -and $u -eq $first[0]) { @($script:f.Events) } else { @() }); Error = '' }
                }
                else { @{ Status = 404; Items = $null; Error = 'Not found.' } }
                if ($OnProgress) { & $OnProgress 1 $Uri.Count $u }
            }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQueryBatch -MockWith {
            $script:logQueries.Add(@{ WorkspaceId = $WorkspaceId; Query = $Query })
            $rows = @{}
            $errors = @{}
            foreach ($name in @($Query.Keys)) {
                if ($script:failWorkspace) { $rows[$name] = @(); $errors[$name] = 'Forbidden: needs Log Analytics Reader.'; continue }
                $rows[$name] = if ($name -eq 'part0') { @($script:f.Summary) } else { @() }
                if ($OnProgress) { & $OnProgress $name 1 $Query.Count }
            }
            @{ Rows = $rows; Errors = $errors }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads a subscription that exports its Activity Log from the workspace, and the other from the REST API' {
        $coverage = @(Invoke-AACActivityLogAssessment -View Coverage -NoDisplay)
        $coverage[0].PSObject.TypeNames[0] | Should -Be 'AAC.ActivityLogCoverage'
        $prod = $coverage | Where-Object Subscription -EQ 'sub-prod'
        "$($prod.Source) $($prod.Workspace) $($prod.RetentionDays)" | Should -Be 'Log Analytics law-central 90'
        ($coverage | Where-Object Subscription -EQ 'sub-dev').Source | Should -Be 'Activity Log'
        $script:logQueries.Count | Should -Be 1
        $script:logQueries[0].WorkspaceId | Should -Be 'c0ffee00-0000-0000-0000-000000000001'
        @($script:logQueries[0].Query.Keys).Count | Should -Be 3 -Because '90 days are three monthly parts, queried side by side'
        $script:logQueries[0].Query['part0'].Query | Should -Match $script:f.Prod
        $script:logQueries[0].Query['part0'].Timespan | Should -Match '^\d{4}-\d\d-\d\dT.*Z/\d{4}-'
        @($script:apiUris | Where-Object { $_ -match $script:f.Prod }).Count | Should -Be 0 -Because 'the exporting subscription is not read from the REST API'
        @($script:apiUris).Count | Should -BeGreaterThan 24 -Because 'the API window is cut into many slices read side by side'
    }

    It 'lists every resource with its state, last use and activity - deleted ones too' {
        $resources = @(Invoke-AACActivityLogAssessment -TagName CostCenter -NoDisplay)
        $resources[0].PSObject.TypeNames[0] | Should -Be 'AAC.ActivityLogResource'
        $store = $resources | Where-Object Resource -EQ 'st-prod'
        "$($store.Subscription) $($store.ResourceGroup) $($store.State) $($store.Operations) $($store.ByPeople) $($store.LastUsedSource)" | Should -Be 'sub-prod rg-data Active 8 2 Activity Log'
        $store.'Tag:CostCenter' | Should -Be 'cc-1'
        $store.Tags | Should -Be 'CostCenter=cc-1'
        ($resources | Where-Object Resource -EQ 'kv-prod').Operations | Should -Be 1 -Because 'a role assignment on the vault counts for the vault'
        $old = $resources | Where-Object Resource -EQ 'vm-old'
        "$($old.State) $($old.LastUsedSource)" | Should -Be 'Idle Last changed'
        $old.IdleDays | Should -BeGreaterThan 90
        $temp = $resources | Where-Object Resource -EQ 'vm-temp'
        "$($temp.State) $($temp.DeletedBy)" | Should -Be 'Deleted aaaaaaaa-0000-0000-0000-00000000c1c1'
        $app = $resources | Where-Object Resource -EQ 'app-dev'
        "$($app.Subscription) $($app.Failed) $($app.Writes)" | Should -Be 'sub-dev 12 1' -Because 'Started and Succeeded are one operation, and the Policy category is left out'
    }

    It 'returns distinct activity and callers, with who they are' {
        $activity = @(Invoke-AACActivityLogAssessment -View Activity -NoDisplay)
        $guest = $activity | Where-Object { $_.Resource -eq 'app-dev' -and $_.Kind -eq 'Write' }
        "$($guest.CallerKind) $($guest.Count) $($guest.Status)" | Should -Be 'Guest user 1 Succeeded'
        "$($guest.CorrelationId) $($guest.SubscriptionId)" | Should -Be "g1 $($script:f.Dev)" -Because 'a row can be piped to Show-AACActivityLogEvent'
        ($activity | Where-Object { $_.Resource -eq 'st-prod' -and $_.Caller -like 'aaaa*' }).CallerKind | Should -Be 'Service principal'
        @($activity | Where-Object Operation -Match 'policies/audit').Count | Should -Be 0
        $callers = @(Invoke-AACActivityLogAssessment -View Caller -NoDisplay)
        ($callers | Where-Object Caller -EQ 'ada@contoso.example').Operations | Should -Be 4
        ($callers | Where-Object Caller -Like 'aaaa*').Failed | Should -Be 12
    }

    It 'finds guests and people changing access, keys read, failure hotspots, hand changes, idle resources and missing tags' {
        $findings = @(Invoke-AACActivityLogAssessment -RequiredTag CostCenter -View Finding -NoDisplay)
        $findings[0].PSObject.TypeNames[0] | Should -Be 'AAC.ActivityLogFinding'
        @($findings | Where-Object Severity -EQ 'High' | ForEach-Object Finding) | Should -Be @('Changed access by hand: 1 time(s)', 'A guest user changed 1 resource(s)') -Because 'by area, then by caller: ada before eve'
        ($findings | Where-Object Area -EQ 'Secrets').Resource | Should -Be 'st-prod'
        ($findings | Where-Object { $_.Area -eq 'Operations' }).Finding | Should -Be '12 failed operation(s)'
        ($findings | Where-Object { $_.Area -eq 'Usage' }).Resource | Should -Be 'vm-old'
        ($findings | Where-Object { $_.Area -eq 'Tags' }).Resource | Should -Be 'vm-old'
        ($findings | Where-Object { $_.Area -eq 'Change' -and $_.Finding -like 'Deleted*' }).Severity | Should -Be 'Info'
        @($findings | Where-Object Area -EQ 'Coverage').Count | Should -Be 0 -Because '90 days is all either source needs'
    }

    It 'says how far back each subscription goes when the window is longer than it keeps' {
        $findings = @(Invoke-AACActivityLogAssessment -Days 180 -View Finding -NoDisplay | Where-Object Area -EQ 'Coverage')
        ($findings | Where-Object Resource -EQ 'sub-dev').Finding | Should -Be 'The Activity Log is not sent to a workspace: only 90 days are kept'
        ($findings | Where-Object Resource -EQ 'sub-prod').Finding | Should -Match 'law-central keeps 90 day\(s\)'
        @($script:logQueries[0].Query.Keys).Count | Should -Be 6 -Because '180 days are six parts'
    }

    It 'reads everything from the REST API with -Source ActivityLog, and falls back to it when the workspace refuses' {
        $null = Invoke-AACActivityLogAssessment -Source ActivityLog -NoDisplay
        $script:logQueries.Count | Should -Be 0
        @($script:apiUris | Where-Object { $_ -match $script:f.Prod }).Count | Should -BeGreaterThan 0

        $script:failWorkspace = $true
        $result = & $script:capture { Invoke-AACActivityLogAssessment -View Coverage -PassThru -NoPaging }
        ($result.Output | Where-Object Subscription -EQ 'sub-prod').Source | Should -Be 'Activity Log'
        $result.Text | Should -Match "law-central couldn't be queried"
    }

    It 'shows the view and writes HTML and CSV reports' {
        $result = & $script:capture { Invoke-AACActivityLogAssessment -NoPaging }
        $result.Text | Should -Match 'Activity Log assessment'
        $result.Text | Should -Match 'st-prod'
        $result.Text | Should -Match 'law-central'
        $html = Join-Path -Path $TestDrive -ChildPath 'activity.html'
        $csv = Join-Path -Path $TestDrive -ChildPath 'activity.csv'
        $null = Invoke-AACActivityLogAssessment -HtmlPath $html -CsvPath $csv -NoDisplay
        Get-Content -LiteralPath $html -Raw | Should -Match 'Coverage'
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 5
    }
}
