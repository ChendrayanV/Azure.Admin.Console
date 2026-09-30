<#
    Unit tests for the parallel Azure Resource Manager reads: Invoke-AACArmParallel
    (with a fake transport: the throttle limit, paging, retries, errors) and
    Get-AACRuleData reading an API Management service's children a level at
    a time - APIs, then their operations and policies, then the operations'
    policies - in parallel batches, with the same result as reading them one
    by one.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - Invoke-AACArmParallel' {
    BeforeAll {
        # A response as HttpClient returns it, already completed.
        $script:respond = {
            param([int] $Status, $Body, [int] $RetryAfter = 0)
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
            $response.Content = [System.Net.Http.StringContent]::new($(if ($null -ne $Body) { ConvertTo-Json -InputObject $Body -Depth 10 -Compress } else { '' }))
            if ($RetryAfter) { $response.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new([TimeSpan]::FromSeconds($RetryAfter)) }
            [System.Threading.Tasks.Task]::FromResult($response)
        }
    }
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
    }

    It 'reads every URI, never more than -ThrottleLimit at once' {
        # One counter shared by the fake sender and the progress callback.
        $counter = @{ Sent = 0; Done = 0; Most = 0 }
        $respond = $script:respond
        $uris = @(1..40 | ForEach-Object { "/subscriptions/s/providers/x/items/$_" + '?api-version=1' })
        $send = {
            param($Target, $Token)
            $counter.Sent++
            $counter.Most = [Math]::Max($counter.Most, $counter.Sent - $counter.Done)
            & $respond 200 @{ id = $Target; token = $Token }
        }.GetNewClosure()
        $progress = { param($Done, $Total) $counter.Done = $Done }.GetNewClosure()
        $results = InModuleScope 'Azure.Admin.Console' -Parameters @{ U = $uris; S = $send; P = $progress } {
            param($U, $S, $P)
            Invoke-AACArmParallel -Uri $U -ThrottleLimit 5 -Send $S -OnProgress $P
        }
        $results.Count | Should -Be 40
        $results[$uris[7]].Body['id'] | Should -Be "https://management.azure.com$($uris[7])" -Because 'a path gets the ARM host'
        $results[$uris[7]].Body['token'] | Should -Be 'fake-token'
        $counter.Most | Should -BeLessOrEqual 5
        $counter.Most | Should -Be 5 -Because 'it fills up to the limit'
    }

    It 'follows nextLink to the end of a list' {
        $send = {
            param($Target, $Token)
            if ($Target -like '*page=2*') { return & $script:respond 200 @{ value = @(@{ id = 'c' }) } }
            & $script:respond 200 @{ value = @(@{ id = 'a' }, @{ id = 'b' }); nextLink = 'https://management.azure.com/list?page=2' }
        }
        $results = InModuleScope 'Azure.Admin.Console' -Parameters @{ S = $send } { param($S) Invoke-AACArmParallel -Uri '/list?api-version=1' -Send $S }
        @($results['/list?api-version=1'].Items | ForEach-Object { $_['id'] }) | Should -Be @('a', 'b', 'c')
    }

    It 'retries throttling as long as Retry-After asks, and server errors' {
        $script:calls = @{}
        $send = {
            param($Target, $Token)
            $script:calls[$Target] = 1 + [int]$script:calls[$Target]
            if ($Target -like '*throttled*' -and $script:calls[$Target] -eq 1) { return & $script:respond 429 $null 1 }
            if ($Target -like '*flaky*' -and $script:calls[$Target] -eq 1) { return & $script:respond 503 $null 1 }
            & $script:respond 200 @{ id = 'ok' }
        }
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $results = InModuleScope 'Azure.Admin.Console' -Parameters @{ S = $send } { param($S) Invoke-AACArmParallel -Uri '/throttled?x=1', '/flaky?x=1' -Send $S }
        $results['/throttled?x=1'].Body['id'] | Should -Be 'ok'
        $results['/flaky?x=1'].Body['id'] | Should -Be 'ok'
        $script:calls.Values | ForEach-Object { $_ | Should -Be 2 }
        $timer.Elapsed.TotalSeconds | Should -BeGreaterOrEqual 0.9 -Because 'Retry-After: 1 was honoured'
    }

    It 'keeps a failure with its status and ARM''s own message, and retries a dropped connection' {
        $script:drops = 0
        $send = {
            param($Target, $Token)
            if ($Target -like '*denied*') { return & $script:respond 403 @{ error = @{ code = 'AuthorizationFailed'; message = 'The client does not have authorization.' } } }
            if ($Target -like '*dropped*') {
                $script:drops++
                $source = [System.Threading.Tasks.TaskCompletionSource[System.Net.Http.HttpResponseMessage]]::new()
                if ($script:drops -eq 1) { $source.SetException([System.Net.Http.HttpRequestException]::new('The connection was reset.')) }
                else { $source.SetResult((& $script:respond 200 @{ id = 'back' }).Result) }
                return $source.Task
            }
            & $script:respond 404 @{ error = @{ message = 'Not found.' } }
        }
        $results = InModuleScope 'Azure.Admin.Console' -Parameters @{ S = $send } { param($S) Invoke-AACArmParallel -Uri '/denied?x=1', '/missing?x=1', '/dropped?x=1' -Send $S }
        $results['/denied?x=1'].Status | Should -Be 403
        $results['/denied?x=1'].Error | Should -Be 'The client does not have authorization.'
        $results['/missing?x=1'].Status | Should -Be 404
        $results['/dropped?x=1'].Body['id'] | Should -Be 'back'
        $script:drops | Should -Be 2
    }
}

Describe 'Azure Admin Console - Invoke-AACArmParallel without a fake transport' {
    It 'has its shared HttpClient variable declared (strict mode)' {
        InModuleScope 'Azure.Admin.Console' { Get-Variable -Name 'AACHttpClient' -Scope Script -ErrorAction Stop } | Should -Not -BeNullOrEmpty
    }

    It 'reports a request it can''t send instead of waiting forever' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { throw 'Not connected to Azure. Run Connect-AAC first.' }
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $results = InModuleScope 'Azure.Admin.Console' { Invoke-AACArmParallel -Uri '/subscriptions/s/providers/x?api-version=1' }
        $results['/subscriptions/s/providers/x?api-version=1'].Error | Should -BeLike '*Connect-AAC*'
        $results['/subscriptions/s/providers/x?api-version=1'].Status | Should -Be 0
        $timer.Elapsed.TotalSeconds | Should -BeLessThan 30
    }
}

Describe 'Azure Admin Console - Get-AACRuleData reads API Management in parallel, a level at a time' {
    BeforeEach {
        $script:apim = '/subscriptions/s1/resourceGroups/rg/providers/Microsoft.ApiManagement/service/apim-prod'
        $script:batches = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Method -eq 'Post' } -MockWith {
            $query = (ConvertFrom-Json -InputObject $Body -AsHashtable).query
            $rows = if ($query -like '*resourcegroups*' -or $query -like "*'microsoft.resources/subscriptions'*") { @() }
            else { @(@{ id = $script:apim; name = 'apim-prod'; type = 'microsoft.apimanagement/service'; location = 'uksouth'; resourceGroup = 'rg'; subscriptionId = 's1'; properties = @{} }) }
            @{ data = $rows }
        }
        # Two APIs with two operations each; every policy exists.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $script:batches.Add(@($Uri))
            $results = @{}
            foreach ($item in $Uri) {
                $path = ($item -split '\?')[0]
                $value = if ($path -eq "$script:apim/apis") { @(1, 2 | ForEach-Object { @{ id = "$script:apim/apis/api$_"; name = "api$_"; properties = @{ type = 'http' } } }) }
                elseif ($path -match '/apis/(api\d)/operations$') { $api = $Matches[1]; @(1, 2 | ForEach-Object { @{ id = "$script:apim/apis/$api/operations/op$_"; name = "op$_" } }) }
                elseif ($path -like '*/policies') { @(@{ id = "$path/policy"; name = 'policy'; type = 'policy' }) }
                else { @() }
                $results[$item] = @{ Status = 200; Body = @{ value = $value }; Items = [System.Collections.Generic.List[object]]@($value); Error = '' }
            }
            $results
        }
    }

    It 'reads each level in one parallel batch, and puts every child in place in order' {
        $data = InModuleScope 'Azure.Admin.Console' { Get-AACRuleData -SubscriptionId 's1' -ResourceType 'Microsoft.ApiManagement/*' }
        $script:batches.Count | Should -Be 3 -Because 'the service''s children, then each API''s, then each operation''s policy'
        @($script:batches[0] | Where-Object { $_ -like "$script:apim/apis?*" }).Count | Should -Be 1
        $script:batches[1].Count | Should -Be 4 -Because 'two APIs: a policy and the operations of each'
        $script:batches[2].Count | Should -Be 4 -Because 'four operations: a policy each'
        $service = $data.Resources | Where-Object { $_['name'] -eq 'apim-prod' }
        $children = @($service['resources'] | ForEach-Object { $_['id'] -replace '^.*/service/apim-prod', '' })
        $children | Should -Be @(
            '/apis/api1', '/apis/api2'
            '/apis/api1/policies/policy', '/apis/api1/operations/op1/policies/policy', '/apis/api1/operations/op2/policies/policy'
            '/apis/api2/policies/policy', '/apis/api2/operations/op1/policies/policy', '/apis/api2/operations/op2/policies/policy'
            '/policies/policy'
        ) -Because 'the same children in the same order as reading them one by one'
        $data.Warnings | Should -BeNullOrEmpty
    }
}

Describe 'Azure Admin Console - Invoke-AACHttp' {
    It 'retries throttling for as long as the longest retry-after header asks, then returns the text' {
        InModuleScope 'Azure.Admin.Console' {
            Mock Get-AACAccessToken { 'fake-token' }
            Mock Start-Sleep { }
            $script:httpCalls = 0
            Mock Send-AACHttpRequest {
                $script:httpCalls++
                if ($script:httpCalls -eq 1) {
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    $response.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new([TimeSpan]::FromSeconds(2))
                    $null = $response.Headers.TryAddWithoutValidation('x-ms-ratelimit-microsoft.costmanagement-qpu-retry-after', '7')
                }
                else {
                    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::OK)
                    $response.Content = [System.Net.Http.StringContent]::new('{"ok":true}')
                }
                [System.Threading.Tasks.Task]::FromResult($response)
            }
            $result = Invoke-AACHttp -Method Post -Uri '/x' -Body '{}'
            $result.Status | Should -Be 200
            $result.Content | Should -BeExactly '{"ok":true}'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 7000 }
            Should -Invoke Send-AACHttpRequest -Times 2 -Exactly -ParameterFilter { $Body -eq '{}' -and $Token -eq 'fake-token' }
        }
    }

    It 'does not retry a refusal, and throws Azure''s message with the status' {
        InModuleScope 'Azure.Admin.Console' {
            Mock Get-AACAccessToken { 'fake-token' }
            Mock Send-AACHttpRequest {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
                $response.Content = [System.Net.Http.StringContent]::new('{"error":{"code":"AuthorizationFailed","message":"No access."}}')
                [System.Threading.Tasks.Task]::FromResult($response)
            }
            $failure = $null
            try { Invoke-AACHttp -Uri '/x' } catch { $failure = $_ }
            $failure.Exception.Message | Should -BeExactly 'No access.'
            $failure.Exception.Data['StatusCode'] | Should -Be 403
            Should -Invoke Send-AACHttpRequest -Times 1 -Exactly
        }
    }

    It 'retries a dropped connection, then gives up with its reason' {
        InModuleScope 'Azure.Admin.Console' {
            Mock Get-AACAccessToken { 'fake-token' }
            Mock Start-Sleep { }
            Mock Send-AACHttpRequest { [System.Threading.Tasks.Task]::FromException[System.Net.Http.HttpResponseMessage]([System.Net.Http.HttpRequestException]::new('The connection was reset.')) }
            { Invoke-AACHttp -Uri '/x' -MaxAttempts 3 } | Should -Throw 'The connection was reset.'
            Should -Invoke Send-AACHttpRequest -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 2 -Exactly
        }
    }
}

Describe 'Azure Admin Console - Invoke-AACGraphBatch' {
    BeforeEach {
        InModuleScope 'Azure.Admin.Console' {
            Mock Get-AACAccessToken { 'fake-token' }
            Mock Start-Sleep { }
            $script:graphState = @{ Sent = [System.Collections.Generic.List[object]]::new(); InFlight = 0; Peak = 0; Throttled = 0 }
            # A fake Resource Graph: 'pages' has two pages, 'busy' is throttled
            # once, 'bad' is refused; the others answer with their query text.
            Mock Send-AACHttpRequest {
                $request = $Body | ConvertFrom-Json -AsHashtable
                $script:graphState.Sent.Add($request)
                $status = 200
                $headers = @{}
                $payload = @{ data = @(@{ q = $request.query }) }
                if ($request.query -eq 'pages' -and -not $request.options.Contains('$skipToken')) { $payload['$skipToken'] = 'page-2' }
                if ($request.query -eq 'busy' -and -not $script:graphState.Throttled++) { $status = 429; $headers['x-ms-user-quota-resets-after'] = '00:00:01' }
                if ($request.query -eq 'bad') { $status = 400; $payload = @{ error = @{ code = 'BadRequest'; message = 'Query is invalid.' } } }
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$status)
                $response.Content = [System.Net.Http.StringContent]::new(($payload | ConvertTo-Json -Depth 5 -Compress))
                foreach ($key in $headers.Keys) { $null = $response.Headers.TryAddWithoutValidation($key, $headers[$key]) }
                [System.Threading.Tasks.Task]::FromResult($response)
            }
        }
    }

    It 'runs the queries, each with its own scope, follows skipToken, and returns the rows by name' {
        InModuleScope 'Azure.Admin.Console' {
            $result = Invoke-AACGraphBatch -SubscriptionId 's1' -Query ([ordered]@{
                    a     = 'first'
                    pages = 'pages'
                    t     = @{ Tenant = $true; Query = 'tenant-wide' }
                    m     = @{ ManagementGroupId = 'mg1'; SubscriptionId = @(); Query = 'group' }
                })
            @($result.Rows['a']).q | Should -Be 'first'
            @($result.Rows['pages']).Count | Should -Be 2 -Because 'both pages are read'
            $result.Rows['a'][0] | Should -BeOfType [hashtable]
            $sent = $script:graphState.Sent
            @($sent | Where-Object { $_.query -eq 'first' })[0].subscriptions | Should -Be @('s1')
            @($sent | Where-Object { $_.query -eq 'tenant-wide' })[0].Contains('subscriptions') | Should -BeFalse
            @($sent | Where-Object { $_.query -eq 'group' })[0].managementGroups | Should -Be @('mg1')
            @($sent | Where-Object { $_.query -eq 'pages' })[1].options['$skipToken'] | Should -BeExactly 'page-2'
            $result.Errors.Count | Should -Be 0
        }
    }

    It 'returns objects with -AsObject, as Invoke-AACResourceGraphQuery does' {
        InModuleScope 'Azure.Admin.Console' {
            $result = Invoke-AACGraphBatch -AsObject -Query @{ a = 'first' }
            $result.Rows['a'][0] | Should -BeOfType [pscustomobject]
            $result.Rows['a'][0].q | Should -BeExactly 'first'
        }
    }

    It 'waits as Resource Graph''s quota header asks when throttled, then carries on' {
        InModuleScope 'Azure.Admin.Console' {
            Mock Start-Sleep { [System.Threading.Thread]::Sleep($Milliseconds) }
            $result = Invoke-AACGraphBatch -Query @{ busy = 'busy' }
            @($result.Rows['busy']).Count | Should -Be 1
            @($script:graphState.Sent | Where-Object { $_.query -eq 'busy' }).Count | Should -Be 2
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -ge 900 -and $Milliseconds -le 1100 }
        }
    }

    It 'throws Azure''s reason for a failed query, unless it is allowed to fail' {
        InModuleScope 'Azure.Admin.Console' {
            { Invoke-AACGraphBatch -Query @{ bad = 'bad'; a = 'first' } } | Should -Throw 'Query is invalid.'
            $result = Invoke-AACGraphBatch -Query ([ordered]@{ bad = 'bad'; a = 'first' }) -AllowFailure 'bad'
            $result.Errors['bad'] | Should -BeExactly 'Query is invalid.'
            @($result.Rows['bad']).Count | Should -Be 0
            @($result.Rows['a']).Count | Should -Be 1
        }
    }

    It 'reports each finished query' {
        InModuleScope 'Azure.Admin.Console' {
            $script:graphSeen = [System.Collections.Generic.List[string]]::new()
            $null = Invoke-AACGraphBatch -Query ([ordered]@{ a = 'first'; b = 'second' }) -OnProgress { param($Name, $Done, $Total) $script:graphSeen.Add("$Name $Done/$Total") }
            @($script:graphSeen | Sort-Object) | Should -Be @('a 1/2', 'b 2/2') -Because 'the fake answers in order'
        }
    }
}
