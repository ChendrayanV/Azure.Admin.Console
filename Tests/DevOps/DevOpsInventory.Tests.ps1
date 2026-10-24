<#
    Unit tests for Get-AACADOInventory: an Azure DevOps organization's
    projects, YAML and classic pipelines, last runs, last pushes, the tasks
    and tools found in the YAML (and its templates, across repositories) and
    in classic pipelines, the security posture (service connections,
    variable groups, environments, branch policies, Advanced Security),
    delivery metrics, several organizations, saved YAML, the Azure link,
    and the findings - with the Azure DevOps REST API faked
    (Fixtures\ContosoDevOps.ps1). Also the parallel reader's Azure DevOps
    paging.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoDevOps.ps1')
    $script:ado = Get-AACContosoDevOps
    $script:pat = ConvertTo-SecureString -String 'fake-pat-value' -AsPlainText -Force
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 170
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - Get-AACADOInventory' {
    BeforeEach {
        $script:asked = [System.Collections.Generic.List[string]]::new()
        $script:authorizations = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-entra-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $script:authorizations.Add($Authorization)
            $out = @{}
            foreach ($u in $Uri) { $script:asked.Add($u); $out[$u] = Get-AACContosoDevOpsAnswer -Data $script:ado -Uri $u }
            $out
        }
    }

    It 'reads every project''s pipelines - YAML, classic build, classic release - with the last run and the last push, signed in with the PAT' {
        $rows = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -NoDisplay)
        @($rows | ForEach-Object { "$($_.Project) | $($_.Pipeline) | $($_.Kind) | $($_.LastResult) | $($_.Yaml)" }) | Should -Be @(
            'Payments | payments-ci | YAML | succeeded | Read'
            'Payments | payments-cd | Classic build | failed | Classic'
            'Payments | payments-release | Classic release | Release-41 | Classic'
            'Platform | infra | YAML | Never run | Read'
            'Platform | web | YAML | partiallySucceeded | Not read'
        )
        $ci = $rows | Where-Object Pipeline -EQ 'payments-ci'
        "$($ci.DaysSinceRun) $($ci.LastRunBy) $($ci.DaysSincePush) $($ci.LastPushBy) $($ci.YamlFile)" | Should -Be '2 Alex Contoso 1 Alex Contoso azure-pipelines.yml'
        $ci.Url | Should -Be 'https://dev.azure.com/contoso/Payments/_build?definitionId=1'
        $ci.PSObject.TypeNames | Should -Contain 'AAC.DevOpsPipeline'
        # Basic ":" + PAT - and no Azure sign-in needed.
        @($script:authorizations | Select-Object -Unique) | Should -Be ('Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':fake-pat-value')))
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -Times 0 -Exactly
    }

    It 'finds the tools in the YAML and its templates - nested, and from another repository - and in classic pipelines, not in comments, by category' {
        $rows = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -NoDisplay)
        $ci = $rows | Where-Object Pipeline -EQ 'payments-ci'
        "$($ci.Build) | $($ci.Test) | $($ci.Security) | $($ci.Lint)" | Should -Be '.NET, npm, Make | dotnet test, Pester, Test results published, go test | Microsoft Security DevOps, Trivy, Gitleaks | dotnet format, ESLint, Prettier, golangci-lint'
        $ci.Security | Should -Not -Match 'Sonar' -Because 'the SonarCloud task is commented out'
        $ci.Templates | Should -Be 'templates/lint.yml, steps/scan.yml@shared, common/gitleaks.yml@shared-templates'
        @($script:asked | Where-Object { $_ -like '*/repositories/shared-templates/items?path=%2Fcommon%2Fgitleaks.yml*' }).Count | Should -Be 1 -Because '../common/gitleaks.yml is relative to the template that includes it'
        $cd = $rows | Where-Object Pipeline -EQ 'payments-cd'
        "$($cd.Build) | $($cd.Test) | $($cd.Security) | $($cd.Deploy) | $($cd.Tasks)" | Should -Be 'MSBuild, npm | VSTest |  | Azure App Service, Helm | 4'
        $infra = Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -NoDisplay | Where-Object Pipeline -EQ 'infra'
        "$($infra.Build) | $($infra.Security) | $($infra.Deploy) | $($infra.GitOps) | $($infra.Lint) | $($infra.Images)" | Should -Be 'Terraform | Checkov | Terraform apply, Environments (approvals) | Flux | yamllint | ubuntu-20.04'
        $tools = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Tool -NoDisplay)
        ($tools | Where-Object Tool -EQ 'Microsoft Security DevOps') | ForEach-Object { "$($_.Category) $($_.Pipelines) $($_.Projects)" } | Should -Be 'Security 1 1'
    }

    It 'finds what to fix - and never repeats a secret it found' {
        $findings = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Finding -NoDisplay)
        $have = @($findings | ForEach-Object { "$($_.Severity) | $($_.Item) | $($_.Finding)" })
        foreach ($expected in @(
                'High | infra (#3) | Possible secret in the YAML'
                'Medium | payments-cd (#2) | Classic build pipeline (no YAML)'
                'Medium | payments-cd (#2) | Last run failed'
                'Medium | infra (#3) | Retired hosted image'
                'Low | payments-release (release #5) | Classic release pipeline'
                'Low | payments-release (release #5) | No release in 90 days'
                'Medium | payments-cd (#2) | No security scanning'
                'Medium | payments-cd (#2) | Deprecated task'
                'Low | payments-ci (#1) | Older task version'
                'Low | infra (#3) | Container image not pinned'
                'Low | infra (#3) | Never run'
                'Low | infra (#3) | No tests'
                'Low | web (#4) | Last run partially succeeded'
                'Info | web (#4) | YAML not read'
                'Low | payments-docs (repository) | No push in 180 days'
                'Info | payments-docs (repository) | Repository with no pipeline'
            )) { $have | Should -Contain $expected }
        $have | Should -Not -Contain 'Medium | payments-ci (#1) | No security scanning'
        $have | Should -Not -Contain 'Low | infra (#3) | No linting' -Because 'yamllint runs in scripts/helper.sh, which scripts/deploy.sh runs'
        ($findings | Where-Object Finding -EQ 'Possible secret in the YAML').Detail | Should -Be "Key 'adminPassword' on line 4 of infra/pipeline.yml has a literal value."
        ($findings | ConvertTo-Json -Depth 5) | Should -Not -Match ([regex]::Escape($script:ado.Secret))
        ($findings | ConvertTo-Json -Depth 5) | Should -Not -Match ([regex]::Escape($script:ado.VariableValue))
        $findings[0].Severity | Should -Be 'High'
    }

    It 'narrows to projects and pipelines, says which projects exist, and reads tools of your own' {
        @(Get-AACADOInventory -Organization contoso -Project payments -PipelineId 1 -PersonalAccessToken $script:pat -NoDisplay).Pipeline | Should -Be 'payments-ci'
        @($script:asked | Where-Object { $_ -match 'vsrm' }).Count | Should -Be 0 -Because '-PipelineId leaves the classic releases out'
        { Get-AACADOInventory -Organization contoso -Project 'Nope' -PersonalAccessToken $script:pat -NoDisplay } | Should -Throw "*found no project 'Nope'*Legacy, Payments, Platform*"
        $custom = Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -ToolRule @(@{ Category = 'Security'; Tool = 'Acme Scan'; Pattern = 'checkov' }) -NoDisplay | Where-Object Pipeline -EQ 'infra'
        $custom.Security | Should -Be 'Checkov, Acme Scan'
        { Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -ToolRule @(@{ Category = 'Nope'; Tool = 'X'; Pattern = 'x' }) -NoDisplay } | Should -Throw '*give Category*'
    }

    It 'lists every task with its version and what it does, packages, containers and agents' {
        $tasks = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Task -NoDisplay)
        $have = @($tasks | ForEach-Object { "$($_.Pipeline) | $($_.Kind) | $($_.Name) | $($_.Version)" })
        foreach ($expected in @(
                'payments-ci | Task | UseDotNet | @2'
                'payments-ci | Task | AzureCLI | @1'
                'payments-ci | Package | Pester | 5.6.1'
                'payments-cd | Task | VSBuild | @1'
                'payments-cd | Task | AzureRmWebAppDeployment | @3'
                'payments-cd | Package | typescript | 5.4.5'
                'infra | Task | TerraformInstaller | @1'
                'infra | Container | hashicorp/terraform | latest'
                'infra | Container | ghcr.io/fluxcd/flux-cli | v2.3.0'
                'infra | Agent image | ubuntu-20.04 | '
            )) { $have | Should -Contain $expected }
        @($have | Where-Object { $_ -like '* | CLI | *' }).Count | Should -Be 0 -Because 'command-line tools are in the evidence now, from the one catalogue'
        $dotnet = $tasks | Where-Object { $_.Name -eq 'UseDotNet' }
        "$($dotnet.Detail) | $($dotnet.Category)" | Should -Be 'sets .NET SDK 8.0.x | Tool'
        $dotnet.Functionality | Should -BeLike 'Acquires a specific version of the .NET Core SDK*'
        ($tasks | Where-Object { $_.Name -eq 'VSTest' }).Source | Should -Be 'classic'
        $tasks[0].PSObject.TypeNames | Should -Contain 'AAC.DevOpsTask'
    }

    It 'shows the evidence for every tool - YAML, script files a script calls, package.json scripts, Makefile targets, images - with versions and masked lines' {
        $evidence = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Evidence -NoDisplay)
        $have = @($evidence | ForEach-Object { "$($_.Pipeline) | $($_.Tool) | $($_.Version) | $($_.Found) | $($_.File):$($_.Line)" })
        foreach ($expected in @(
                'payments-ci | .NET | 8.0.x | Task | azure-pipelines.yml:17'
                'payments-ci | Azure CLI (az) | agent default | YAML / inline script | azure-pipelines.yml:33'
                'payments-ci | Gitleaks | agent default | YAML / inline script | common/gitleaks.yml@shared-templates:2'
                'payments-ci | ESLint | agent default | package.json | /package.json (lint):2'
                'payments-ci | Prettier | agent default | package.json | /package.json (lint):3'
                'payments-ci | golangci-lint | agent default | Makefile | /Makefile (test):2'
                'payments-cd | Helm |  | Classic task | classic:14'
                'infra | Terraform apply | 1.9.5 | YAML / inline script | infra/pipeline.yml:23'
                'infra | Flux | v2.3.0 | Container image | infra/pipeline.yml:10'
                'infra | Flux | agent default | Script file | /scripts/deploy.sh:3'
                'infra | yamllint | agent default | Script file | /scripts/helper.sh:1'
            )) { $have | Should -Contain $expected }
        $have | Should -Not -Contain 'payments-ci | Gitleaks | agent default | YAML / inline script | steps/scan.yml@shared:2' -Because 'a template: line names a file, not a tool'
        ($evidence | Where-Object Tool -EQ 'Flux' | Where-Object Found -EQ 'Script file').Evidence | Should -Be 'flux reconcile kustomization apps --with-source'
        ($evidence | ConvertTo-Json -Depth 4) | Should -Not -Match 'abcdefghijklmnopqrstuvwxyz0123456789'
        @($script:asked | Where-Object { $_ -like '*items?path=%2Fscripts%2Fhelper.sh*' }).Count | Should -BeGreaterThan 0 -Because 'a script a script calls is read too'

        $tools = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Tool -NoDisplay)
        ($tools | Where-Object Tool -EQ 'Flux') | ForEach-Object { "$($_.Category) | $($_.Pipelines) | $($_.Versions) | $($_.Found)" } | Should -Be 'GitOps | 1 | agent default, v2.3.0 | Container image, Script file'
    }

    It 'lists what no rule knows and what couldn''t be read, and which stages each pipeline covers' {
        $unrecognised = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Unrecognised -NoDisplay)
        @($unrecognised | ForEach-Object { "$($_.Kind) | $($_.Name) | $($_.Pipelines)" }) | Should -Be @(
            'Command | acme-deployer | 1'
            'Command | keys | 1'
            'Script file not read | $(ToolsDir)/publish.sh | 1'
        )
        ($unrecognised | Where-Object Name -EQ 'acme-deployer').Example | Should -Be 'Platform / infra - /scripts/deploy.sh:4: acme-deployer push --env prod --token ***'
        $coverage = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Coverage -NoDisplay)
        @($coverage | ForEach-Object { "$($_.Pipeline) | $($_.Lint) $($_.Test) $($_.Security) $($_.GitOps)" }) | Should -Be @(
            'payments-ci | Yes Yes Yes No'
            'payments-cd | No Yes No No'
            'infra | Yes No Yes Yes'
            'web | Not read Not read Not read Not read'
        )
    }

    It 'adds tools of your own from a file, and reads no script files with -MaxScriptFiles 0' {
        $rules = Join-Path $TestDrive 'rules.psd1'
        Set-Content -LiteralPath $rules -Value "@{ Rules = @( @{ Category = 'Deploy'; Tool = 'Acme Deployer'; Pattern = '\bacme-deployer\s+push\b'; Purpose = 'Pushes a release to Acme' } ) }"
        $evidence = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -ToolRulePath $rules -View Evidence -NoDisplay | Where-Object Tool -EQ 'Acme Deployer')
        "$($evidence.Category) | $($evidence.File):$($evidence.Line) | $($evidence.Purpose)" | Should -Be 'Deploy | /scripts/deploy.sh:4 | Pushes a release to Acme'
        @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -ToolRulePath $rules -View Unrecognised -NoDisplay | Where-Object Name -EQ 'acme-deployer').Count | Should -Be 0
        { Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -ToolRulePath (Join-Path $TestDrive 'nope.psd1') -NoDisplay } | Should -Throw '*can''t find the rule file*'
        $script:asked.Clear()
        $null = Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -MaxScriptFiles 0 -NoDisplay
        @($script:asked | Where-Object { $_ -match 'path=%2F(scripts|package\.json|Makefile)' }).Count | Should -Be 0
    }

    It 'reads the security posture: service connections, variable groups, environments, branch policies and Advanced Security' {
        $connections = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View ServiceConnection -NoDisplay)
        @($connections | ForEach-Object { "$($_.Connection) | $($_.Scheme) | $($_.OpenToAllPipelines) | $($_.AuthorizedPipelines) | $($_.UsedBy)" }) | Should -Be @(
            'azure-dev | WorkloadIdentityFederation | False | 1 | '
            'azure-prod | ServicePrincipal | True | 0 | payments-ci, payments-cd'
            'github-old | Token | False | 0 | '
        )
        $groups = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View VariableGroup -NoDisplay)
        @($groups | ForEach-Object { "$($_.VariableGroup) | $($_.Type) | $($_.Secrets) | $($_.NotMarkedSecret) | $($_.OpenToAllPipelines)" }) | Should -Be @(
            'kv-linked | Key Vault | 1 |  | False'
            'payments-secrets | Azure DevOps | 1 | ApiToken | True'
        )
        ($groups | ConvertTo-Json -Depth 5) | Should -Not -Match ([regex]::Escape($script:ado.VariableValue))
        $environments = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Environment -NoDisplay)
        @($environments | ForEach-Object { "$($_.Project) | $($_.Environment) | $($_.Checks) | $($_.Approval) | $($_.UsedBy)" }) | Should -Be @(
            'Payments | dev | Approval | True | '
            'Platform | production |  | False | infra'
        )
        $repositories = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Repository -NoDisplay)
        @($repositories | ForEach-Object { "$($_.Repository) | $($_.Reviewers) | $($_.BuildValidation) | $($_.AdvancedSecurity) | $($_.CriticalAlerts) $($_.HighAlerts) $($_.MediumAlerts) | $($_.SecretAlerts)" }) | Should -Be @(
            'payments | 2 | True | On | 1 1 1 | 1'
            'payments-docs | 0 | True | Off | 0 0 0 | 0'
            'infra | 0 | False | Unknown | 0 0 0 | 0'
        )
        $findings = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Finding -NoDisplay | ForEach-Object { "$($_.Severity) | $($_.Area) | $($_.Item) | $($_.Finding)" })
        foreach ($expected in @(
                'High | Security | azure-prod (service connection) | Open to every pipeline'
                'Medium | Security | azure-prod (service connection) | Uses a client secret'
                'Low | Security | github-old (service connection) | Unused service connection'
                'High | Security | payments-secrets (variable group) | Secret-looking variable not marked secret'
                'Medium | Security | payments-secrets (variable group) | Secrets kept outside Key Vault'
                'Medium | Security | payments-secrets (variable group) | Secrets open to every pipeline'
                'High | Security | production (environment) | Production with no approval'
                'Medium | Repository | payments-docs (repository) | No required reviewers'
                'Low | Repository | infra (repository) | No build validation'
                'Low | Repository | payments-docs (repository) | Advanced Security off'
                'High | Repository | payments (repository) | Exposed secrets'
                'Medium | Repository | payments (repository) | Critical or high security alerts'
            )) { $findings | Should -Contain $expected }
        $findings | Should -Not -Contain 'Medium | Repository | payments (repository) | No required reviewers'
    }

    It 'measures delivery from the run history: success rate, duration, queue time, deployments and change failure rate' {
        $rows = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -NoDisplay)
        $ci = $rows | Where-Object Pipeline -EQ 'payments-ci'
        "$($ci.Runs) $($ci.SuccessRate) $($ci.AvgDurationMin) $($ci.AvgQueueMin) $($ci.RunsPerWeek)" | Should -Be '11 90 6 1 2.6' -Because 'the cancelled run counts as a run, not in the success rate'
        $cd = $rows | Where-Object Pipeline -EQ 'payments-cd'
        "$($cd.SuccessRate) $($cd.AvgQueueMin) $($cd.AzureTargets)" | Should -Be '33.3 15 Contoso Production'
        $production = Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Environment -NoDisplay | Where-Object Environment -EQ 'production'
        "$($production.Deployments) $($production.Succeeded) $($production.Failed) $($production.ChangeFailureRate) $($production.DeploymentsPerWeek)" | Should -Be '4 3 1 25 0.9' -Because 'the deployment 60 days ago is outside the 30 days'
        $findings = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Finding -NoDisplay | ForEach-Object { "$($_.Item) | $($_.Finding)" })
        $findings | Should -Contain 'payments-cd (#2) | Unreliable pipeline'
        $findings | Should -Contain 'payments-cd (#2) | Long queue times'
        $script:asked.Clear()
        $null = Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -MetricDays 7 -NoDisplay
        $since = [regex]::Match(@($script:asked | Where-Object { $_ -like '*/_apis/build/builds?minTime=*' })[0], 'minTime=([^&]+)').Groups[1].Value
        ([datetime]::UtcNow - [datetime]::Parse($since, [cultureinfo]::InvariantCulture, 'AdjustToUniversal')).TotalDays | Should -BeGreaterThan 6.9
    }

    It 'leaves parts out with -Skip, and still reads the rest' {
        $script:asked.Clear()
        $rows = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -Skip Security, Metrics, AdvancedSecurity -NoDisplay)
        $rows.Count | Should -Be 5
        @($script:asked | Where-Object { $_ -match 'serviceendpoint|variablegroups|environments|policy/configurations|pipelinePermissions|build/builds|advsec' }).Count | Should -Be 0
        ($rows | Where-Object Pipeline -EQ 'payments-ci').Runs | Should -BeNullOrEmpty
        @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -Skip Security -View Repository -NoDisplay | Where-Object { $null -ne $_.Reviewers }).Count | Should -Be 0 -Because 'no branch policies were read'
    }

    It 'reads several organizations, found from the sign-in, with an Organization column' {
        $rows = @(Get-AACADOInventory -DiscoverOrganization -UseAzureSignIn -View Project -NoDisplay)
        @($rows | ForEach-Object { "$($_.Organization)/$($_.Project)" }) | Should -Be @('contoso/Legacy', 'contoso/Payments', 'contoso/Platform', 'fabrikam/Mobile')
        @($script:asked | Where-Object { $_ -like 'https://app.vssps.visualstudio.com/_apis/accounts?memberId=member-1*' }).Count | Should -Be 1
        @(Get-AACADOInventory -Organization contoso, fabrikam -PersonalAccessToken $script:pat -View Project -NoDisplay).Count | Should -Be 4
        { Get-AACADOInventory -PersonalAccessToken $script:pat -NoDisplay } | Should -Throw '*needs an organization*'
    }

    It 'saves every pipeline''s YAML, its templates and the classic pipelines to -YamlPath' {
        $folder = Join-Path $TestDrive 'pipelines'
        $null = Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -YamlPath $folder -NoDisplay
        $files = @(Get-ChildItem -LiteralPath $folder -Recurse -File | ForEach-Object { $_.FullName.Substring($folder.Length + 1) -replace '\\', '/' } | Sort-Object)
        $files | Should -Be @(
            'contoso/Payments/payments-cd (#2).classic.json'
            'contoso/Payments/payments-ci (#1).yml'
            'contoso/Platform/infra (#3).yml'
            'contoso/templates/Payments/payments/templates/lint.yml'
            'contoso/templates/Payments/shared-templates/common/gitleaks.yml'
            'contoso/templates/Payments/shared-templates/steps/scan.yml'
        )
        $original = $script:ado.Answers["$($script:ado.Organization)/11111111-aaaa-0000-0000-000000000001/_apis/git/repositories/aaaaaaaa-1111-0000-0000-000000000001/items|azure-pipelines.yml"].Body.content
        [System.IO.File]::ReadAllText((Join-Path $folder 'contoso/Payments/payments-ci (#1).yml')) | Should -BeExactly $original
        $classic = Get-Content -LiteralPath (Join-Path $folder 'contoso/Payments/payments-cd (#2).classic.json') -Raw | ConvertFrom-Json
        @($classic.process.phases[0].steps).Count | Should -Be 4
        $classic.variableGroups | Should -Be 'payments-secrets'
    }

    It 'links Azure service connections to their service principals'' Azure roles with -IncludeAzure' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith {
            @{ Data = @{ sp0 = @(@{ id = 'dddddddd-0000-0000-0000-000000000001'; appId = 'aaaaaaaa-0000-0000-0000-00000000a001'; displayName = 'sp-azure-prod' }) }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            @{
                Rows   = @{
                    assignments   = @(@{ principalId = 'dddddddd-0000-0000-0000-000000000001'; scope = '/subscriptions/s-1'; roleName = 'Owner'; roleGuid = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' })
                    subscriptions = @(@{ subscriptionId = 's-1'; name = 'Contoso Production' })
                }
                Errors = @{}
            }
        }
        $connections = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -IncludeAzure -View ServiceConnection -NoDisplay)
        $prod = $connections | Where-Object Connection -EQ 'azure-prod'
        "$($prod.AzureIdentity) | $($prod.AzureRoles)" | Should -Be 'sp-azure-prod | Owner on subscription Contoso Production'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -Times 1 -Exactly -ParameterFilter { $Query['sp0'] -like "*appId in ('aaaaaaaa-0000-0000-0000-00000000a001','aaaaaaaa-0000-0000-0000-00000000a002')*" }
        $findings = @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -IncludeAzure -View Finding -NoDisplay | ForEach-Object { "$($_.Severity) | $($_.Item) | $($_.Finding)" })
        $findings | Should -Contain 'High | azure-prod (service connection) | Can grant Azure access'
    }

    It 'leaves out disabled repositories and the pipelines that build them - unless -IncludeDisabledRepository' {
        $script:asked.Clear()
        $text = (& $script:capture { Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -NoPaging }).Text
        $text | Should -BeLike '*left out 1 disabled repository(ies) and the 1 pipeline(s) that build them*'
        @($script:asked | Where-Object { $_ -like '*aaaaaaaa-5555-0000-0000-000000000005*' }).Count | Should -Be 0 -Because 'a disabled repository is never read'
        @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -NoDisplay).Pipeline | Should -Not -Contain 'old-api-ci'
        $old = Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -IncludeDisabledRepository -NoDisplay | Where-Object Pipeline -EQ 'old-api-ci'
        $old.Yaml | Should -Be 'Repository disabled'
        @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -IncludeDisabledRepository -View Repository -NoDisplay).Repository | Should -Contain 'old-api'
        @(Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -IncludeDisabledRepository -View Finding -NoDisplay | ForEach-Object { "$($_.Item) | $($_.Finding)" }) | Should -Contain 'old-api-ci (#6) | Pipeline on a disabled repository'
    }

    It 'signs in from AZURE_DEVOPS_EXT_PAT or with the Azure sign-in, and says how when neither is there' {
        $saved = $env:AZURE_DEVOPS_EXT_PAT
        try {
            $env:AZURE_DEVOPS_EXT_PAT = 'env-pat'
            $null = Get-AACADOInventory -Organization 'https://dev.azure.com/contoso/' -SkipYaml -PersonalAccessToken:$null -NoDisplay
            $script:authorizations[-1] | Should -Be ('Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':env-pat')))
            $env:AZURE_DEVOPS_EXT_PAT = $null
            $null = Get-AACADOInventory -Organization contoso -UseAzureSignIn -SkipYaml -NoDisplay
            $script:authorizations[-1] | Should -Be 'Bearer fake-entra-token'
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -ParameterFilter { $Resource -eq '499b84ac-1321-427f-aa17-267ca6975798' }
            { Get-AACADOInventory -Organization contoso -NoDisplay } | Should -Throw '*needs a way to sign in to Azure DevOps*'
            { Get-AACADOInventory -Organization 'https://example.com/x' -PersonalAccessToken $script:pat -NoDisplay } | Should -Throw "*can't read 'https://example.com/x'*"
        }
        finally { $env:AZURE_DEVOPS_EXT_PAT = $saved }
    }

    It 'shows the inventory at the prompt in characters any console can show, and writes CSV by -View and an HTML report' {
        $text = (& $script:capture { Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -NoPaging }).Text
        foreach ($expected in 'Azure DevOps inventory', 'payments-ci', 'Classic build pipeline (no YAML)', "Classic releases couldn't be read in 1 project") { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
        $csv = Join-Path $TestDrive 'ado.csv'; $html = Join-Path $TestDrive 'ado.html'
        $null = & $script:capture { Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -View Repository -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Repository | Should -Be @('payments', 'payments-docs', 'infra')
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('projects', 'pipelines', 'tasks', 'repositories', 'connections', 'groups', 'environments', 'tools', 'coverage', 'evidence', 'unrecognised', 'findings')
        (Get-Content -LiteralPath $html -Raw) | Should -Not -Match 'fake-pat-value|SuperSecret|tok-123-visible-value'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'ado.pdf'
        $null = & $script:capture { Get-AACADOInventory -Organization contoso -PersonalAccessToken $script:pat -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}

Describe 'Azure Admin Console - Azure DevOps inventory progress' {
    It 'reports each stage with the project whose request finished, the projects done and the time left' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            $finished = 0
            foreach ($u in $Uri) { $out[$u] = Get-AACContosoDevOpsAnswer -Data $script:ado -Uri $u; $finished++; if ($OnProgress) { & $OnProgress $finished @($Uri).Count $u } }
            $out
        }
        $script:progress = [System.Collections.Generic.List[object]]::new()
        $reader = @{ OrganizationUrl = 'https://dev.azure.com/contoso'; Authorization = 'Basic x'; OnProgress = { param($Step, $Text, $Done, $Total) $script:progress.Add([pscustomobject]@{ Step = $Step; Text = $Text; Done = $Done; Total = $Total }) } }
        $null = & (Get-Module -Name 'Azure.Admin.Console') { param($Splat) Read-AACDevOpsInventory @Splat } $reader
        @($script:progress | ForEach-Object Step | Select-Object -Unique) | Should -Be @(1, 2, 3, 4, 5, 6, 7, 8) -Because 'projects, pipelines, details, alerts, two levels of templates, two of script files'
        $script:progress[0].Text | Should -Be 'Projects and task catalogue - estimating'
        $pipelines = @($script:progress | Where-Object Step -EQ 2)
        $pipelines[-1].Text | Should -BeLike 'Pipelines, repositories, security, runs - 3/3 projects - * - *'
        $pipelines[-1].Done | Should -Be $pipelines[-1].Total
        @($pipelines.Text | Where-Object { $_ -match ' - (Payments|Platform|Legacy)$' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Azure Admin Console - Azure DevOps paging and sign-in in the parallel reader' {
    It 'sends the Authorization header instead of an Azure token, follows x-ms-continuationtoken - not with $top - and reports a sign-in page' {
        InModuleScope 'Azure.Admin.Console' {
            Mock Get-AACAccessToken { throw 'must not be asked' }
            $script:sent = [System.Collections.Generic.List[string]]::new()
            $respond = {
                param([string] $Target, [string] $Token)
                $script:sent.Add($Target)
                $message = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::OK)
                if ($Target -like '*signin*') { $message.StatusCode = 203; $message.Content = [System.Net.Http.StringContent]::new('<html>Sign in</html>'); return [System.Threading.Tasks.Task]::FromResult($message) }
                $page = if ($Target -match 'continuationToken=abc') { 2 } else { 1 }
                $message.Content = [System.Net.Http.StringContent]::new((@{ count = 1; value = @(@{ id = "item$page" }) } | ConvertTo-Json -Compress))
                if ($page -eq 1) { $null = $message.Headers.TryAddWithoutValidation('x-ms-continuationtoken', 'abc') }
                [System.Threading.Tasks.Task]::FromResult($message)
            }
            $answers = Invoke-AACArmParallel -Uri 'https://dev.azure.com/x/_apis/projects?api-version=7.1', 'https://dev.azure.com/x/_apis/git/repositories/r/pushes?$top=1&api-version=7.1', 'https://dev.azure.com/x/signin' -Authorization 'Basic abc' -Send $respond
            @($answers['https://dev.azure.com/x/_apis/projects?api-version=7.1'].Items | ForEach-Object { $_.id }) | Should -Be @('item1', 'item2')
            @($answers['https://dev.azure.com/x/_apis/git/repositories/r/pushes?$top=1&api-version=7.1'].Items).Count | Should -Be 1
            $answers['https://dev.azure.com/x/signin'].Error | Should -BeLike "*wasn't JSON (HTTP 203) - a sign-in page*"
            @($script:sent | Where-Object { $_ -like '*continuationToken=abc*' }).Count | Should -Be 1
        }
    }
}
