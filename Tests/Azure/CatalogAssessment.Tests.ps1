<#
    Unit tests for Invoke-AACLandingZoneAssessment and Invoke-AACResiliencyAssessment:
    the catalogues that ship with the module, run against a faked Resource Graph.
    The queries themselves can't be run here, so what is tested is what the statuses
    claim from what comes back.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    $script:sub = '55555555-5555-5555-5555-555555555555'
    $script:zone = InModuleScope 'Azure.Admin.Console' { (Get-AACServiceBaseline -Set LandingZone).Rows }
    $script:aprl = InModuleScope 'Azure.Admin.Console' { (Get-AACServiceBaseline -Set Resiliency).Rows }
    $script:graph = {
        param([hashtable] $Answers = @{}, [hashtable] $Failures = @{})
        $script:answers = $Answers
        $script:failures = $Failures
        $script:askedQueries = @()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:sub; name = 'sub-one' }) }; Errors = @{} } }
            if ($Query.Contains('types')) { return @{ Rows = @{ types = $script:answers['types'] }; Errors = @{} } }
            $script:askedQueries += @($Query.Keys)
            $rows = @{}; $errors = @{}
            foreach ($name in $Query.Keys) {
                if ($script:failures.Contains($name)) { $errors[$name] = $script:failures[$name] }
                else { $rows[$name] = @(if ($script:answers.Contains($name)) { $script:answers[$name] }) }
            }
            @{ Rows = $rows; Errors = $errors }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { @{ Subscriptions = @(@{ subscriptionId = $script:sub; name = 'sub-one' }); Ids = @($script:sub); GraphScope = @($script:sub); Names = @{ $script:sub = 'sub-one' }; Label = 'test scope' } }
    }
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
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $script:statusOf = { param([object[]] $Rows, [string] $Guid) @($Rows | Where-Object Guid -EQ $Guid)[0].Status }
}

Describe 'Azure Admin Console - the catalogues' {
    It 'ships the landing zone checklist, each query with the column the statuses read' {
        @($script:zone).Count | Should -BeGreaterThan 200
        $queryable = @($script:zone | Where-Object Queryable)
        $queryable.Count | Should -BeGreaterThan 100
        @($queryable | Where-Object { $_.Query -notmatch 'compliant' }).Count | Should -Be 0
        @($script:zone | Where-Object { -not $_.Queryable -and -not $_.Reason }).Count | Should -Be 0 -Because 'a manual check says why'
        @($script:zone | Where-Object { $_.Severity -notin 'High', 'Medium', 'Low' }).Count | Should -Be 0
    }

    It 'ships APRL''s queries, and none of those it marks as not validatable' {
        $with = @($script:aprl | Where-Object Query)
        $with.Count | Should -BeGreaterThan 100
        @($script:aprl | Where-Object { -not $_.Query }).Count | Should -BeGreaterThan 100
        @($with | Where-Object { $_.Query -match 'cannot-be-validated|under-development' }).Count | Should -Be 0
        @($with | Where-Object { $_.Query -notmatch 'recommendationId' }).Count | Should -Be 0
    }

    It 'only ever reads: no catalogue query writes' {
        foreach ($row in @($script:zone | Where-Object Query) + @($script:aprl | Where-Object Query)) { $row.Query | Should -Not -Match '(?m)^\s*\.(set|append|drop|delete)\b' }
    }
}

Describe 'Azure Admin Console - rating the landing zone checks' {
    BeforeAll {
        $script:measured = @($script:zone | Where-Object { $_.Queryable -and $_.Query -notmatch 'extend\s+compliant\s*=\s*1\s*(\||$)' -and $_.Query -notmatch "(displayName|name|mgChain)[A-Za-z]*\s+(has|contains|startswith|matches|=~)|has_any|has\s+'" })[0]
        $script:byName = @($script:zone | Where-Object { $_.Queryable -and $_.Query -match "displayNameLower has 'sandbox'" })[0]
        $script:presence = @($script:zone | Where-Object { $_.Queryable -and $_.Query -match 'extend\s+compliant\s*=\s*1\s*(\||$)' })[0]
        $script:manual = @($script:zone | Where-Object { -not $_.Queryable })[0]
    }

    It 'says what the evidence can bear' {
        & $script:graph @{
            $script:measured.Guid = @(@{ name = 'bad-one'; id = '/x/bad'; compliant = 0 }, @{ name = 'good-one'; id = '/x/good'; compliant = 1 })
            $script:byName.Guid   = @(@{ name = 'platform'; id = '/mg/platform'; compliant = 0 })
            $script:presence.Guid = @(@{ name = 'there'; id = '/x/there'; compliant = 1 })
        }
        $rows = @(Invoke-AACLandingZoneAssessment -NoDisplay)
        & $script:statusOf $rows $script:measured.Guid | Should -Be 'Fail'
        & $script:statusOf $rows $script:byName.Guid | Should -Be 'Review' -Because 'a name proves little'
        & $script:statusOf $rows $script:presence.Guid | Should -Be 'Present' -Because 'that query can only say it is there'
        & $script:statusOf $rows $script:manual.Guid | Should -Be 'Manual'
        @($rows | Where-Object Status -EQ 'No evidence').Count | Should -BeGreaterThan 50 -Because 'no rows is neither a pass nor a fail'
        @($rows | Where-Object { $_.Status -eq 'Pass' }).Count | Should -Be 0
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.LandingZoneCheck'
        $rows[0].Status | Should -Be 'Fail' -Because 'failures come first'
    }

    It 'passes when it found things and all comply, and doesn''t run manual checks' {
        & $script:graph @{ $script:measured.Guid = @(@{ name = 'good'; id = '/x/good'; compliant = 1 }) }
        $rows = @(Invoke-AACLandingZoneAssessment -NoDisplay)
        & $script:statusOf $rows $script:measured.Guid | Should -Be 'Pass'
        $script:askedQueries | Should -Not -Contain $script:manual.Guid
    }

    It 'treats true and false from a query as it does 1 and 0' {
        & $script:graph @{ $script:measured.Guid = @(@{ name = 'bad'; id = '/x'; compliant = $false }) }
        & $script:statusOf @(Invoke-AACLandingZoneAssessment -NoDisplay) $script:measured.Guid | Should -Be 'Fail'
    }

    It 'says a failed query wasn''t checked, and carries on' {
        & $script:graph @{} @{ $script:measured.Guid = 'Bad query' }
        $html = Join-Path $TestDrive 'lz-failed.html'
        $null = & $script:capture { Invoke-AACLandingZoneAssessment -HtmlPath $html }
        (Get-Content -LiteralPath $html -Raw) | Should -Match ([regex]::Escape('1 query(ies) failed'))
        & $script:statusOf @(Invoke-AACLandingZoneAssessment -NoDisplay) $script:measured.Guid | Should -Be 'Not checked'
    }

    It 'narrows by category, severity and status' {
        & $script:graph
        @(Invoke-AACLandingZoneAssessment -Category 'Network*' -NoDisplay | Where-Object { $_.Category -notlike 'Network*' }).Count | Should -Be 0
        @(Invoke-AACLandingZoneAssessment -Severity High -NoDisplay | Where-Object Severity -NE 'High').Count | Should -Be 0
        @(Invoke-AACLandingZoneAssessment -Status Manual -NoDisplay | Where-Object Status -NE 'Manual').Count | Should -Be 0
    }

    It 'reads management groups across the tenant' {
        & $script:graph
        $null = Invoke-AACLandingZoneAssessment -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -ParameterFilter { $Query.Contains($script:byName.Guid) -and $Query[$script:byName.Guid].Tenant } -Times 1 -Exactly
    }

    It 'shows it, writes findings a later run can compare with, and honours a suppression' {
        & $script:graph @{ $script:measured.Guid = @(@{ name = 'bad-one'; id = '/x/bad'; compliant = 0 }) }
        $text = (& $script:capture { Invoke-AACLandingZoneAssessment -NoPaging }).Text
        foreach ($expected in 'Azure Landing Zone assessment', '1 check(s) failed', 'Community queries') { $text | Should -Match ([regex]::Escape($expected)) }
        $csv = Join-Path $TestDrive 'lz.csv'
        $null = & $script:capture { Invoke-AACLandingZoneAssessment -CsvPath $csv }
        $first = @(Import-Csv -LiteralPath $csv)
        $first[0].FindingKey | Should -Match '^[0-9a-f]{16}$'
        $file = Join-Path $TestDrive 'lz-accepted.json'
        [System.IO.File]::WriteAllText($file, "[{`"key`":`"$($first[0].FindingKey)`",`"reason`":`"By design`"}]")
        $html = Join-Path $TestDrive 'lz.html'
        $null = & $script:capture { Invoke-AACLandingZoneAssessment -SuppressionFile $file -PreviousPath $csv -HtmlPath $html }
        foreach ($expected in 'By design', 'finding(s) suppressed') { (Get-Content -LiteralPath $html -Raw) | Should -Match ([regex]::Escape($expected)) }
        (Get-Content -LiteralPath $html -Raw) | Should -Not -Match 'Resolved since the earlier run' -Because 'suppressed isn''t resolved'
    }

    It 'writes a PDF' -Skip:(-not $script:canWritePdf) {
        & $script:graph @{ $script:measured.Guid = @(@{ name = 'bad-one'; id = '/x/bad'; compliant = 0 }) }
        $pdf = Join-Path $TestDrive 'lz.pdf'
        $null = & $script:capture { Invoke-AACLandingZoneAssessment -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}

Describe 'Azure Admin Console - rating the APRL recommendations' {
    BeforeAll {
        $storage = @($script:aprl | Where-Object ResourceType -EQ 'Microsoft.Storage/storageAccounts')
        $script:withQuery = @($storage | Where-Object Query)[0]
        $script:another = @($storage | Where-Object Query)[1]
        $script:types = @(@{ type = 'microsoft.storage/storageaccounts'; used = 4 })
    }

    It 'fails what it lists, passes what it doesn''t, and says what needs a person' {
        & $script:graph @{ types = $script:types; $script:withQuery.Guid = @(@{ recommendationId = $script:withQuery.Guid; name = 'stlegacy'; id = '/x/stlegacy'; param1 = 'sku: Standard_LRS' }) }
        $rows = @(Invoke-AACResiliencyAssessment -NoDisplay)
        & $script:statusOf $rows $script:withQuery.Guid | Should -Be 'Fail'
        & $script:statusOf $rows $script:another.Guid | Should -Be 'Pass'
        @($rows | Where-Object { $_.Status -eq 'Fail' })[0].Detail | Should -Be '1 of 4 don''t follow it.'
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.ResiliencyCheck'
    }

    It 'shows nothing for a type you don''t use, and runs no query for it' {
        & $script:graph @{ types = $script:types }
        $rows = @(Invoke-AACResiliencyAssessment -NoDisplay)
        @($rows | ForEach-Object ResourceType | Select-Object -Unique) | Should -Be @('Microsoft.Storage/storageAccounts')
        $vm = @($script:aprl | Where-Object { $_.Query -and $_.ResourceType -eq 'Microsoft.Compute/virtualMachines' })[0]
        $script:askedQueries | Should -Not -Contain $vm.Guid
    }

    It 'calls a recommendation with no query Manual for a type in use, never a pass' {
        $type = @($script:aprl | Where-Object { -not $_.Query } | Group-Object ResourceType | Select-Object -First 1)[0].Name
        & $script:graph @{ types = @(@{ type = $type.ToLowerInvariant(); used = 1 }) }
        $rows = @(Invoke-AACResiliencyAssessment -NoDisplay)
        @($rows | Where-Object Evidence -EQ 'None' | Where-Object Status -NE 'Manual').Count | Should -Be 0
        @($rows | Where-Object Status -EQ 'Manual').Count | Should -BeGreaterThan 0
    }

    It 'says a failed query wasn''t checked' {
        & $script:graph @{ types = $script:types } @{ $script:withQuery.Guid = 'Bad query' }
        & $script:statusOf @(Invoke-AACResiliencyAssessment -NoDisplay) $script:withQuery.Guid | Should -Be 'Not checked'
    }

    It 'narrows by type and impact, and lists each affected resource' {
        & $script:graph @{ types = @($script:types + @(@{ type = 'microsoft.compute/virtualmachines'; used = 2 })); $script:withQuery.Guid = @(@{ name = 'stlegacy'; id = '/x/stlegacy' }) }
        @(Invoke-AACResiliencyAssessment -ResourceType 'Microsoft.Storage/*' -NoDisplay | Where-Object ResourceType -NE 'Microsoft.Storage/storageAccounts').Count | Should -Be 0
        @(Invoke-AACResiliencyAssessment -Impact High -NoDisplay | Where-Object Severity -NE 'High').Count | Should -Be 0
        $html = Join-Path $TestDrive 'aprl.html'
        $text = (& $script:capture { Invoke-AACResiliencyAssessment -HtmlPath $html })
        (Get-Content -LiteralPath $html -Raw) | Should -Match 'stlegacy'
    }
}
