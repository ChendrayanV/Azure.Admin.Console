<#
    Unit tests for Show-AACActivityLogEvent and the readers it shares with
    Invoke-AACActivityLogAssessment and Get-AACResourceError: the error in a
    status message (Read-AACActivityLogError), the flattened event - from a
    file with no sign-in, from the pipeline, by correlation ID from the
    Activity Log or a workspace - and its views and reports. Events are made
    up (Fixtures/ContosoActivityLogEvent.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoActivityLogEvent.ps1')
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
    $script:write = {
        param($Content, [string] $Name = 'event.json')
        $file = Join-Path -Path $TestDrive -ChildPath $Name
        Set-Content -LiteralPath $file -Value (ConvertTo-Json -InputObject $Content -Depth 20)
        $file
    }
}

Describe 'Azure Admin Console - why an Activity Log event failed' {
    It 'reads the innermost code, message and target, and what to do' {
        $why = InModuleScope 'Azure.Admin.Console' {
            Read-AACActivityLogError -StatusMessage '{"error":{"code":"HCRP404","target":"sub/rg/vm","message":"The extension could not be found in location ''uksouth''."}}' -StatusCode 'NotFound' -SubStatus 'NotFound'
        }
        "$($why.Code)|$($why.Target)|$($why.Category)" | Should -Be 'HCRP404|sub/rg/vm|Not found'
        $why.Message | Should -Be "The extension could not be found in location 'uksouth'."
        $why.Fix | Should -Match 'region'
    }

    It 'goes past a deployment''s wrapper to the detail - also when the detail is JSON in a message - and falls back to the sub-status' {
        $nested = @{ error = @{ code = 'DeploymentFailed'; message = 'At least one resource deployment operation failed.'; details = @(@{ code = 'Conflict'; message = '{"error":{"code":"SkuNotAvailable","message":"The requested size is not available."}}' }) } } | ConvertTo-Json -Depth 10 -Compress
        $why = InModuleScope 'Azure.Admin.Console' -Parameters @{ S = $nested } { param($S) Read-AACActivityLogError -StatusMessage $S }
        "$($why.Code)|$($why.Category)" | Should -Be 'SkuNotAvailable|Capacity'
        (InModuleScope 'Azure.Admin.Console' { Read-AACActivityLogError -SubStatus 'Forbidden' }).Category | Should -Be 'Authorization'
    }
}

Describe 'Azure Admin Console - Show-AACActivityLogEvent' {
    BeforeEach {
        $script:f = Get-AACContosoActivityLogEvent
        $script:uris = [System.Collections.Generic.List[string]]::new()
        $script:kql = ''
        $script:signedIn = $false
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { if (-not $script:signedIn) { throw 'Run Connect-AAC first.' }; 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-arc'; state = 'Enabled'; chain = @() }) }; Errors = @{} } }
            $rows = @{}
            foreach ($name in @($Query.Keys)) { $rows[$name] = @(@{ id = $script:f.Machine.ToLowerInvariant(); location = 'uksouth'; tags = @{ Owner = 'platform' } }) }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) {
                $script:uris.Add($u)
                $answers[$u] = if ($u -match [regex]::Escape($script:f.Correlation)) { @{ Status = 200; Items = @($script:f.Failed, $script:f.Started); Error = '' } } else { @{ Status = 200; Items = @(); Error = '' } }
                if ($OnProgress) { & $OnProgress 1 $Uri.Count $u }
            }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQuery -MockWith { $script:kql = $Query; @($script:f.Workspace) }
    }

    It 'flattens an event saved from the portal - with no sign-in - into one readable row' {
        $file = & $script:write $script:f.Failed
        $e = @(Show-AACActivityLogEvent -Path $file -NoDisplay)
        $e.Count | Should -Be 1
        $e[0].PSObject.TypeNames[0] | Should -Be 'AAC.ActivityLogEvent'
        "$($e.Status)|$($e.Operation)|$($e.Phase)|$($e.Channel)|$($e.Level)" | Should -Be 'Failed|Upgrade Extensions on Azure Arc machines|End request|Operation|Error'
        "$($e.HttpStatus)|$($e.SubStatus)|$($e.ErrorCode)|$($e.ErrorCategory)" | Should -Be '404|Not Found (HTTP Status Code: 404)|HCRP404|Not found'
        $e.ErrorMessage | Should -Match "type 'azuremonitorlinuxagent' could not be found in location 'uksouth'"
        $e.ErrorTarget | Should -BeLike '*/rg-arc/arc-web-01.contoso.example'
        "$($e.CallerKind)|$($e.AppId)|$($e.ObjectId)" | Should -Be "Service principal|aaaaaaaa-1111-4222-8333-000000000abc|bbbbbbbb-1111-4222-8333-000000000def"
        "$($e.AuthMethod)|$($e.Tenant)|$($e.DirectoryRoles)" | Should -Be 'Certificate or federated credential|Home|Directory Readers'
        $e.TokenIssued | Should -Be ([DateTimeOffset]::FromUnixTimeSeconds(1793442186).UtcDateTime)
        "$($e.ResourceGroup)|$($e.ResourceType)|$($e.Resource)|$($e.Subscription)" | Should -Be "rg-arc|Microsoft.HybridCompute/machines|arc-web-01.contoso.example|$($script:f.Subscription)"
        "$($e.Action)|$($e.IngestionDelay)|$($e.Source)" | Should -Be 'Microsoft.HybridCompute/machines/upgradeExtensions/action|00:01:47|event.json'
        $e.PortalLink | Should -Be "https://portal.azure.com/#@$($script:f.Tenant)/resource$($script:f.Machine)"
        @($e.PSObject.Properties.Name | Where-Object { $_ -like 'Claim:*' }).Count | Should -Be 0 -Because 'the token''s opaque values are noise unless asked for'
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACGraphBatch -Times 0 -Because 'a file needs no sign-in'
    }

    It 'reads an array or a REST response, and adds every claim with -IncludeClaims' {
        $events = @(Show-AACActivityLogEvent -Path (& $script:write @{ value = @($script:f.Failed, $script:f.Started, $script:f.UserWrite) } 'response.json') -IncludeClaims -NoDisplay)
        @($events | ForEach-Object Status) | Should -Be @('Succeeded', 'Started', 'Failed') -Because 'oldest first'
        $events[2].'Claim:aio' | Should -Be 'opaque-aio-value'
        $events[2].'Claim:objectidentifier' | Should -Be 'bbbbbbbb-1111-4222-8333-000000000def'
        $claims = @(Show-AACActivityLogEvent -Path (& $script:write @($script:f.Failed) 'array.json') -IncludeClaims -View Claim -NoDisplay)
        $claims[0].PSObject.TypeNames[0] | Should -Be 'AAC.ActivityLogEventClaim'
        ($claims | Where-Object Claim -EQ 'appidacr').Value | Should -Be '2'
    }

    It 'decodes a user''s sign-in, name and roles' {
        $e = @(Show-AACActivityLogEvent -Path (& $script:write $script:f.UserWrite) -NoDisplay)[0]
        "$($e.CallerKind)|$($e.CallerName)|$($e.AuthMethod)" | Should -Be 'User|Ada Lovelace|User sign-in (pwd, mfa)'
        $e.DirectoryRoles | Should -Be 'Global Administrator, User (default member)'
        "$($e.Status)|$($e.ErrorCode)|$($e.HttpStatus)|$($e.CallerIp)" | Should -Be 'Succeeded||200|203.0.113.9'
    }

    It 'takes events from the pipeline - a workspace row too - and JSON text' {
        $row = @($script:f.Workspace | Show-AACActivityLogEvent -NoDisplay)[0]
        "$($row.Status)|$($row.ErrorCode)|$($row.CallerKind)|$($row.Source)" | Should -Be 'Failed|HCRP404|Service principal|Pipeline' -Because 'AzureActivity''s Failure is the REST API''s Failed'
        $text = ConvertTo-Json -InputObject $script:f.Failed -Depth 20
        (@($text | Show-AACActivityLogEvent -NoDisplay)[0]).ErrorCode | Should -Be 'HCRP404'
        (@(ConvertFrom-Json -InputObject $text | Show-AACActivityLogEvent -NoDisplay)[0]).ErrorCode | Should -Be 'HCRP404' -Because 'objects from ConvertFrom-Json work as well as hashtables'
    }

    It 'reads every event of an operation by correlation ID - and adds the subscription name, location and tags' {
        $script:signedIn = $true
        $events = @(Show-AACActivityLogEvent -CorrelationId $script:f.Correlation -NoDisplay)
        @($events | ForEach-Object Phase) | Should -Be @('Begin request', 'End request')
        "$($events[1].Subscription)|$($events[1].Location)|$($events[1].Tags)" | Should -Be 'sub-arc|uksouth|Owner=platform'
        $script:uris[0] | Should -Match "^/subscriptions/$($script:f.Subscription)/providers/Microsoft.Insights/eventtypes/management/values"
        [System.Uri]::UnescapeDataString($script:uris[0]) | Should -Match "correlationId eq '$($script:f.Correlation)'"
    }

    It 'reads them from a Log Analytics workspace with -WorkspaceId' {
        $script:signedIn = $true
        $events = @(Show-AACActivityLogEvent -CorrelationId $script:f.Correlation -WorkspaceId 'c0ffee00-0000-0000-0000-000000000001' -Days 365 -NoDisplay)
        "$($events.Count)|$($events[0].Source)|$($events[0].ErrorCode)" | Should -Be '1|Log Analytics|HCRP404'
        $script:kql | Should -Match "ago\(365d\)"
        $script:kql | Should -Match "CorrelationId in~ \('$($script:f.Correlation)'\)"
    }

    It 'looks up rows piped from the assessment by their correlation ID, in the subscription of their resource' {
        $script:signedIn = $true
        $events = @([pscustomobject]@{ Resource = 'arc-web-01'; Status = 'Failed'; CorrelationId = $script:f.Correlation; ResourceId = $script:f.Machine } | Show-AACActivityLogEvent -NoDisplay)
        $events.Count | Should -Be 2
        @($script:uris | Where-Object { $_ -match 'eventtypes' }).Count | Should -Be 1 -Because 'only the resource''s subscription is searched'
    }

    It 'groups the failures by error code, lays each event out as a card, and writes HTML and CSV' {
        $file = & $script:write @($script:f.Failed, $script:f.Started)
        $errors = @(Show-AACActivityLogEvent -Path $file -View Error -NoDisplay)
        "$($errors.ErrorCode)|$($errors.Category)|$($errors.Events)" | Should -Be 'HCRP404|Not found|1'
        $details = @(Show-AACActivityLogEvent -Path $file -View Detail -NoDisplay)
        ($details | Where-Object { $_.Section -eq 'Result' -and $_.Field -eq 'Error code' }).Value | Should -Be 'HCRP404'
        ($details | Where-Object { $_.Section -eq 'Who' -and $_.Field -eq 'Signed in with' } | Select-Object -First 1).Value | Should -Be 'Certificate or federated credential'

        $result = & $script:capture { Show-AACActivityLogEvent -Path $file -NoPaging }
        $result.Text | Should -Match 'HCRP404'
        $result.Text | Should -Match 'What to do'
        $html = Join-Path -Path $TestDrive -ChildPath 'events.html'
        $csv = Join-Path -Path $TestDrive -ChildPath 'events.csv'
        $null = Show-AACActivityLogEvent -Path $file -HtmlPath $html -CsvPath $csv -NoDisplay
        Get-Content -LiteralPath $html -Raw | Should -Match 'Event details'
        (@(Import-Csv -LiteralPath $csv) | Where-Object Status -EQ 'Failed').ErrorCode | Should -Be 'HCRP404'
    }

    It 'says what to do with nothing to show, or a file that isn''t JSON' {
        { Show-AACActivityLogEvent -NoDisplay } | Should -Throw '*no event to show*'
        $bad = Join-Path -Path $TestDrive -ChildPath 'bad.json'
        Set-Content -LiteralPath $bad -Value 'not json'
        { Show-AACActivityLogEvent -Path $bad -NoDisplay } | Should -Throw "*can't read*as JSON*"
    }
}
