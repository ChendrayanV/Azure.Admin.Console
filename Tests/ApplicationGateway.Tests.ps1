<#
    Unit tests for Show-AACApplicationGatewayMap: the map model, flows,
    health (metrics and the live check) and findings built from a made-up
    Contoso gateway (Fixtures\ContosoApplicationGateway.ps1), with Resource
    Graph, Azure Monitor and the backend health check mocked. The page's
    layout runs in a browser and is not tested here.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoApplicationGateway.ps1')
    $script:agw = Get-AACContosoApplicationGateway
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 180
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - Show-AACApplicationGatewayMap' {
    BeforeEach {
        $script:posts = 0
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($n in @($Query.Keys)) {
                $rows[$n] = @(switch -Wildcard ($n) { 'gateways' { $script:agw.Gateways } 'subscriptions' { $script:agw.Subscriptions } 'sites' { $script:agw.Sites } 'ids*' { $script:agw.Related } })
            }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { $out = @{}; foreach ($u in $Uri) { $out[$u] = @{ Status = 200; Body = $script:agw.Metrics; Items = $null; Error = '' } }; $out }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith {
            if ($Method -eq 'Post') { $script:posts++; return @{ Status = 202; Content = ''; Headers = @{ Location = 'https://management.azure.com/operations/1' } } }
            @{ Status = 200; Content = (ConvertTo-Json -InputObject $script:agw.Live -Depth 20); Headers = @{} }
        }
    }

    It 'draws the flow in stages inside the gateway, its subnet and network' {
        $m = Show-AACApplicationGatewayMap -HtmlPath (Join-Path $TestDrive 'agw.html') -NoBrowser -PassThru
        $m.PSObject.TypeNames | Should -Contain 'AAC.ApplicationGatewayMap'
        $stage = { param([string] $Type) @($m.Nodes | Where-Object Type -EQ $Type).Name | Sort-Object }
        & $stage 'appgw/listener' | Should -Be @('http-legacy', 'http-shop', 'https-old', 'https-shop')
        & $stage 'appgw/pool' | Should -Be @('pool-api', 'pool-empty', 'pool-web')
        & $stage 'appgw/target' | Should -Be @('10.1.2.10', '10.1.2.11', 'app-api', 'vm-api-1') -Because 'an App Service and a VM are named, not their address'
        @($m.Edges | Where-Object Kind -EQ 'probe').Count | Should -Be 1
        @($m.Edges | Where-Object Kind -EQ 'redirect').Count | Should -Be 1
        @($m.Edges | Where-Object Kind -EQ 'waf').Count | Should -Be 4 -Because 'the gateway''s policy protects every listener'
        $html = Get-Content -LiteralPath (Join-Path $TestDrive 'agw.html') -Raw
        $model = [regex]::Match($html, '<script id="aac-map" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $gateway = $model.clusters | Where-Object kind -EQ 'appgw'
        ($model.clusters | Where-Object id -EQ $gateway.parent).name | Should -Be 'snet-appgw'
        ($model.clusters | Where-Object kind -EQ 'vnet').name | Should -Be 'vnet-hub'
        $gateway.elk.'elk.partitioning.activate' | Should -Be 'true'
        ($model.nodes | Where-Object name -EQ 'https-shop').elk.'elk.partitioning.partition' | Should -Be '1'
    }

    It 'lists each flow: listener, rule, path, settings, pool, with health from metrics' {
        $m = Show-AACApplicationGatewayMap -NoBrowser -PassThru -HtmlPath (Join-Path $TestDrive 'f.html')
        @($m.Flows | ForEach-Object { "$($_.Listener)|$($_.Rule)|$($_.Path)|$($_.BackendSettings)|$($_.Pool)|$($_.Redirect)|$($_.Health)" }) | Should -Be @(
            'https-shop|rule-shop|/api/*|be-api|pool-api||healthy'
            'https-shop|rule-shop|(default)|be-web|pool-web||degraded'
            'http-shop|rule-redirect|*||||rd-https'.Replace('||||rd-https', '|||https-shop|redirect')
            'http-legacy|rule-legacy|*|be-web|pool-web||degraded'
        )
        ($m.Flows | Where-Object Path -EQ '/api/*').Targets | Should -Be 'app-api, vm-api-1'
        $m.Flows[0].CertExpires | Should -BeLessThan ([datetime]::UtcNow)
        $m.Flows[0].WafMode | Should -Be 'Detection'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -Times 0 -Exactly
    }

    It 'runs the live backend health check with -IncludeHealth: each target''s state and the probe''s reason' {
        $m = Show-AACApplicationGatewayMap -IncludeHealth -NoBrowser -PassThru -HtmlPath (Join-Path $TestDrive 'h.html')
        $script:posts | Should -Be 1
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -ParameterFilter { $Method -eq 'Post' -and $Uri -like '*/applicationgateways/appgw-prod/backendhealth?api-version=*' }
        ($m.Nodes | Where-Object Name -EQ '10.1.2.11').Health | Should -Be 'unhealthy'
        ($m.Nodes | Where-Object Name -EQ 'vm-api-1').Health | Should -Be 'healthy'
        ($m.Nodes | Where-Object Name -EQ 'pool-web').Health | Should -Be 'degraded'
        $html = Get-Content -LiteralPath (Join-Path $TestDrive 'h.html') -Raw
        $html | Should -Match 'more than the timeout threshold'
    }

    It 'says so when the live check is refused, and keeps going' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith { throw 'AuthorizationFailed: does not have authorization to perform action backendhealth/action' }
        $m = Show-AACApplicationGatewayMap -IncludeHealth -NoBrowser -PassThru -HtmlPath (Join-Path $TestDrive 'r.html')
        ($m.Findings | Where-Object Finding -EQ 'Live backend health not read').Detail | Should -BeLike '*AuthorizationFailed*'
        ($m.Nodes | Where-Object Name -EQ 'pool-web').Health | Should -Be 'degraded' -Because 'the metrics still say so'
    }

    It 'finds what to fix' {
        $f = @((Show-AACApplicationGatewayMap -NoBrowser -PassThru -HtmlPath (Join-Path $TestDrive 'x.html')).Findings)
        $has = { param([string] $Severity, [string] $Finding, [string] $Name) @($f | Where-Object { $_.Severity -eq $Severity -and $_.Finding -eq $Finding -and (-not $Name -or $_.Name -eq $Name) }).Count }
        & $has 'High' 'WAF policy in Detection mode' 'waf-prod' | Should -Be 1
        & $has 'High' 'Certificate expired' 'cert-shop' | Should -Be 2 -Because 'two listeners use it'
        & $has 'Medium' 'Old TLS policy' | Should -Be 1
        & $has 'Medium' 'Certificate uploaded, not from Key Vault' | Should -Be 2
        & $has 'Medium' 'HTTP not redirected to HTTPS' 'http-legacy' | Should -Be 1
        & $has 'Medium' 'HTTP not redirected to HTTPS' 'http-shop' | Should -Be 0
        & $has 'Medium' 'No custom health probe' 'be-web' | Should -Be 1
        & $has 'Medium' 'Some targets unhealthy' 'pool-web' | Should -Be 1
        & $has 'Low' 'Old managed rule set' 'waf-prod' | Should -Be 1
        & $has 'Low' 'Listener no rule uses' 'https-old' | Should -Be 1
        & $has 'Low' 'Backend pool no rule uses' 'pool-empty' | Should -Be 1
        & $has 'Low' 'Probe no backend setting uses' 'probe-unused' | Should -Be 1
        & $has 'Low' 'Connection draining off' 'be-web' | Should -Be 1
        & $has 'Medium' 'Not zone-redundant or under 2 instances' | Should -Be 0
        $f[0].Severity | Should -Be 'High'
    }

    It 'shows the flows and findings at the prompt, opens the map, and writes the flows to CSV' {
        $csv = Join-Path $TestDrive 'flows.csv'
        $text = (& $script:capture { Show-AACApplicationGatewayMap -CsvPath $csv -HtmlPath (Join-Path $TestDrive 'c.html') }).Text
        foreach ($expected in 'Flows', 'https-shop', 'rule-shop', '/api/*', 'pool-web', 'degraded', 'WAF policy in Detection mode') { $text | Should -BeLike "*$expected*" }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -Times 1 -Exactly
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 4
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'narrows by -Name, and writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $none = (& $script:capture { Show-AACApplicationGatewayMap -Name 'appgw-test*' -NoBrowser }).Text
        $none | Should -BeLike '*No Application Gateway in that scope*'
        $pdf = Join-Path $TestDrive 'agw.pdf'
        $null = & $script:capture { Show-AACApplicationGatewayMap -PdfPath $pdf -NoBrowser -HtmlPath (Join-Path $TestDrive 'p.html') }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
