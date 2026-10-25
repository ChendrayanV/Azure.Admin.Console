<#
    A made-up Contoso Azure DevOps organization for DevOpsInventory.Tests.ps1
    (and demo mode), as the Azure DevOps REST API returns it.

      Payments   payments-ci   YAML (azure-pipelines.yml, Azure Repos): .NET
                               build and test, test results, Microsoft
                               Security DevOps, AzureCLI@1 (older major) with
                               an inline script (az, Install-Module Pester
                               5.6.1) on azure-prod; a local template with
                               dotnet format; steps/scan.yml@shared from the
                               shared-templates repository (Trivy), which
                               includes ../common/gitleaks.yml; a
                               commented-out SonarCloud task; npm run lint
                               (package.json: ESLint, Prettier), make test
                               (Makefile: go test, golangci-lint), and a
                               script whose path is a variable. Succeeded 2
                               days ago; 9 of 10 runs in 30 days succeeded.
                 payments-cd   classic build: VSBuild@1, VSTest@2,
                               AzureRmWebAppDeployment@3 (deprecated) on
                               azure-prod, CmdLine@2 (npm -g typescript@5.4.5,
                               helm upgrade); no scanning; its last run failed
                               10 days ago; 2 of 6 runs succeeded, 15-minute
                               queues
                 payments-release   classic release; last release 200 days ago
                 old-api-ci    YAML on old-api, a disabled repository
                 repositories  payments (push yesterday; 2 reviewers, build
                               validation; Advanced Security on: a secret, a
                               critical dependency and a medium code alert),
                               payments-docs (push 400 days ago, no pipeline,
                               no reviewers, Advanced Security off)
                 connections   azure-prod (azurerm, client secret, open to
                               every pipeline), azure-dev (workload identity
                               federation, one pipeline), github-old (unused)
                 groups        payments-secrets (a secret, ApiToken not marked
                               secret, open to every pipeline), kv-linked
                               (Key Vault)
                 environments  dev (approval)
      Platform   infra         YAML: Terraform (TerraformInstaller 1.9.5) and
                               Checkov, ubuntu-20.04 (retired), a password
                               written in the YAML, an unpinned container,
                               deploys to production; runs scripts/deploy.sh
                               (Flux, an unknown acme-deployer), which runs
                               scripts/helper.sh (yamllint); a Flux image;
                               never run
                 web           YAML in a GitHub repository (not readable); last
                               run partially succeeded
                 repository    infra (push 5 days ago; no branch policies)
                 environments  production (no checks; 3 of 4 deployments in
                               30 days succeeded)
      Legacy     no pipelines; its classic releases can't be read (403)

    -DiscoverOrganization finds contoso and fabrikam (one project, Mobile,
    nothing in it).
#>
function Get-AACContosoDevOps {
    $org = 'https://dev.azure.com/contoso'
    $advsec = 'https://advsec.dev.azure.com/contoso'
    $ago = { param([double] $Days) [datetime]::UtcNow.AddDays(-$Days).ToString('o') }
    $p1 = '11111111-aaaa-0000-0000-000000000001'; $p2 = '22222222-aaaa-0000-0000-000000000002'; $p3 = '33333333-aaaa-0000-0000-000000000003'
    $r1 = 'aaaaaaaa-1111-0000-0000-000000000001'; $r2 = 'aaaaaaaa-2222-0000-0000-000000000002'; $r3 = 'aaaaaaaa-3333-0000-0000-000000000003'
    $e1 = 'eeeeeeee-0000-0000-0000-000000000001'; $e2 = 'eeeeeeee-0000-0000-0000-000000000002'; $e3 = 'eeeeeeee-0000-0000-0000-000000000003'
    $repo = { param($Id, $Name, $Type = 'TfsGit') @{ id = $Id; name = $Name; type = $Type; defaultBranch = 'refs/heads/main' } }
    $definition = { param($Id, $Name, $Type, $Yaml, $Repository, $Latest) $d = @{ id = $Id; name = $Name; path = '\'; queueStatus = 'enabled'; process = @{ type = $Type }; repository = $Repository }; if ($Yaml) { $d.process.yamlFilename = $Yaml }; if ($Latest) { $d.latestBuild = $Latest }; $d }
    $build = { param($Result, $Days, $Number) @{ id = 1000 + $Number; buildNumber = "2026.$Number"; status = 'completed'; result = $Result; finishTime = (& $ago $Days); queueTime = (& $ago ($Days + 0.01)); requestedFor = @{ displayName = 'Alex Contoso' }; sourceBranch = 'refs/heads/main' } }
    # A run of the last 30 days: queued, started after QueueMinutes, ran 6 minutes.
    $run = { param($DefinitionId, $Result, $Days, $QueueMinutes = 1) $q = [datetime]::UtcNow.AddDays(-$Days); @{ id = [int]($Days * 100) + $DefinitionId; definition = @{ id = $DefinitionId }; status = 'completed'; result = $Result; queueTime = $q.ToString('o'); startTime = $q.AddMinutes($QueueMinutes).ToString('o'); finishTime = $q.AddMinutes($QueueMinutes + 6).ToString('o') } }
    $list = { param([object[]] $Items) @{ Status = 200; Body = @{ count = @($Items).Count }; Items = [System.Collections.Generic.List[object]]@($Items); Error = '' } }
    $one = { param($Body) @{ Status = 200; Body = $Body; Items = $null; Error = '' } }
    $file = { param([string] $Path, [string] $Content) @{ Status = 200; Body = @{ path = $Path; content = $Content }; Items = $null; Error = '' } }
    $task = { param($Id, $Name, $Major, $Description, $Category, $Deprecated = $false) @{ id = $Id; name = $Name; friendlyName = $Name; description = $Description; category = $Category; deprecated = $Deprecated; version = @{ major = $Major; minor = 0; patch = 0 } } }
    $permission = { param([bool] $All, [int[]] $Pipelines = @()) & $one @{ allPipelines = $(if ($All) { @{ authorized = $true } } else { $null }); pipelines = @($Pipelines | ForEach-Object { @{ id = $_; authorized = $true } }) } }

    $ci = @'
trigger:
  - main
resources:
  repositories:
    - repository: shared
      type: git
      name: shared-templates
      ref: refs/heads/main
pool:
  vmImage: ubuntu-latest
variables:
  - group: payments-secrets
steps:
  - task: UseDotNet@2
    inputs:
      version: 8.0.x
  - task: DotNetCoreCLI@2
    inputs:
      command: build
  - task: DotNetCoreCLI@2
    inputs:
      command: test
  - task: PublishTestResults@2
  # - task: SonarCloudPrepare@1   (switched off)
  - task: MicrosoftSecurityDevOps@1
  - task: AzureCLI@1
    displayName: Smoke test
    inputs:
      azureSubscription: azure-prod
      scriptType: pscore
      scriptLocation: inlineScript
      inlineScript: |
        az account show
        Install-Module -Name Pester -RequiredVersion 5.6.1 -Force
  - template: templates/lint.yml
  - template: steps/scan.yml@shared
  - script: npm run lint
  - script: make test
  - script: $(ToolsDir)/publish.sh
'@
    $lint = @'
steps:
  - script: dotnet format --verify-no-changes
'@
    $scan = @'
steps:
  - template: ../common/gitleaks.yml
  - script: trivy fs --exit-code 1 .
'@
    $gitleaks = @'
steps:
  - script: gitleaks detect --no-git
'@
    $infra = @'
pool:
  vmImage: 'ubuntu-20.04'
variables:
  adminPassword: SuperSecret123!
resources:
  containers:
    - container: tf
      image: hashicorp/terraform:latest
    - container: flux
      image: ghcr.io/fluxcd/flux-cli:v2.3.0
jobs:
  - deployment: apply
    environment: production
    strategy:
      runOnce:
        deploy:
          steps:
            - task: TerraformInstaller@1
              inputs:
                terraformVersion: 1.9.5
            - script: terraform init && terraform plan -out tfplan
            - script: checkov -d .
            - script: terraform apply tfplan
            - task: Bash@3
              inputs:
                filePath: scripts/deploy.sh
'@
    $classicCd = & $definition 2 'payments-cd' 1 $null (& $repo $r1 'payments') (& $build 'failed' 10 2)
    $classicCd.process.phases = @(@{ name = 'Agent job 1'; steps = @(
                @{ displayName = 'Build solution'; enabled = $true; task = @{ id = 'b0000000-0000-0000-0000-00000000000b'; versionSpec = '1.*' }; inputs = @{ solution = '**\*.sln' } }
                @{ displayName = 'Test assemblies'; enabled = $true; task = @{ id = 'b0000000-0000-0000-0000-00000000000c'; versionSpec = '2.*' }; inputs = @{ testSelector = 'testAssemblies' } }
                @{ displayName = 'Deploy web app'; enabled = $true; task = @{ id = 'b0000000-0000-0000-0000-00000000000d'; versionSpec = '3.*' }; inputs = @{ ConnectedServiceName = $e1; WebAppName = 'payments' } }
                @{ displayName = 'Tools'; enabled = $true; task = @{ id = 'b0000000-0000-0000-0000-00000000000e'; versionSpec = '2.*' }; inputs = @{ script = "npm install -g typescript@5.4.5`nhelm upgrade web ./chart" } }
            ) })
    $classicCd.variableGroups = @(@{ id = 1; name = 'payments-secrets' })
    # A marketplace task (from an installed extension), a self-hosted pool, and variables in the pipeline's settings.
    $classicCd.process.phases[0].steps += @{ displayName = 'Replace tokens'; enabled = $true; task = @{ id = 'c0000000-0000-0000-0000-000000000001'; versionSpec = '6.*' }; inputs = @{ targetFiles = '**/*.config' } }
    $classicCd.queue = @{ name = 'onprem-linux'; pool = @{ name = 'onprem-linux' } }
    $classicCd.variables = @{ BuildConfiguration = @{ value = 'Release'; allowOverride = $true }; NpmToken = @{ isSecret = $true; value = $null } }
    $marketTask = & $task 'c0000000-0000-0000-0000-000000000001' 'replacetokens' 6 'Replace tokens in files' 'Utility'
    $marketTask.contributionIdentifier = 'fabrikam.replacetokens.replacetokens-task'
    $marketTask.author = 'Fabrikam Tools'
    $feeds = 'https://feeds.dev.azure.com/contoso'
    $vsrm = 'https://vsrm.dev.azure.com/contoso'
    $branch = { param([string] $Name, [double] $Days, [int] $Ahead = 0, [int] $Behind = 0) @{ name = $Name; aheadCount = $Ahead; behindCount = $Behind; commit = @{ author = @{ name = 'Alex Contoso'; date = (& $ago $Days) }; committer = @{ date = (& $ago $Days) } } } }

    $answers = @{
        "$org/_apis/projects"                                              = & $list @(@{ id = $p1; name = 'Payments'; state = 'wellFormed'; visibility = 'private'; lastUpdateTime = (& $ago 1) }, @{ id = $p2; name = 'Platform'; state = 'wellFormed'; visibility = 'private'; lastUpdateTime = (& $ago 5) }, @{ id = $p3; name = 'Legacy'; state = 'wellFormed'; visibility = 'private'; lastUpdateTime = (& $ago 900) })
        "$org/_apis/distributedtask/tasks"                                 = & $list @(
            (& $task 'b0000000-0000-0000-0000-000000000001' 'UseDotNet' 2 'Acquires a specific version of the .NET Core SDK from the internet or the local cache and adds it to the PATH' 'Tool')
            (& $task 'b0000000-0000-0000-0000-000000000002' 'DotNetCoreCLI' 2 'Build, test, package, or publish a dotnet application, or run a custom dotnet command' 'Build')
            (& $task 'b0000000-0000-0000-0000-000000000003' 'PublishTestResults' 2 'Publish test results to Azure Pipelines' 'Test')
            (& $task 'b0000000-0000-0000-0000-000000000004' 'MicrosoftSecurityDevOps' 1 'Run security analyzers' 'Utility')
            (& $task 'b0000000-0000-0000-0000-000000000005' 'AzureCLI' 1 'Run Azure CLI commands against an Azure subscription in a Shell script' 'Deploy')
            (& $task 'b0000000-0000-0000-0000-000000000005' 'AzureCLI' 2 'Run Azure CLI commands against an Azure subscription in a PowerShell Core/Shell script' 'Deploy')
            (& $task 'b0000000-0000-0000-0000-000000000006' 'TerraformInstaller' 1 'Install a specific version of terraform' 'Tool')
            (& $task 'b0000000-0000-0000-0000-00000000000b' 'VSBuild' 1 'Build with MSBuild and set the Visual Studio version property' 'Build')
            (& $task 'b0000000-0000-0000-0000-00000000000c' 'VSTest' 2 'Run unit and functional tests (Selenium, Appium, Coded UI test, etc.)' 'Test')
            (& $task 'b0000000-0000-0000-0000-00000000000d' 'AzureRmWebAppDeployment' 3 'Deploy to Azure App Service (use AzureRmWebAppDeployment@4)' 'Deploy' $true)
            (& $task 'b0000000-0000-0000-0000-00000000000e' 'CmdLine' 2 'Run a command line script using Bash on Linux and macOS and cmd.exe on Windows' 'Utility')
            $marketTask
        )
        # --- Payments ------------------------------------------------------------------------------------------
        "$org/$p1/_apis/build/definitions"                                 = & $list @(
            (& $definition 1 'payments-ci' 2 'azure-pipelines.yml' (& $repo $r1 'payments') (& $build 'succeeded' 2 1))
            $classicCd
            (& $definition 6 'old-api-ci' 2 'azure-pipelines.yml' (& $repo 'aaaaaaaa-5555-0000-0000-000000000005' 'old-api') (& $build 'succeeded' 300 6))
        )
        "https://vsrm.dev.azure.com/contoso/$p1/_apis/release/definitions" = & $list @(@{ id = 5; name = 'payments-release'; path = '\'; lastRelease = @{ name = 'Release-41'; createdOn = (& $ago 200); createdBy = @{ displayName = 'Sam Contoso' } } })
        "$org/$p1/_apis/git/repositories"                                  = & $list @(@{ id = $r1; name = 'payments'; defaultBranch = 'refs/heads/main'; size = 52428800; webUrl = "$org/Payments/_git/payments" }, @{ id = $r2; name = 'payments-docs'; defaultBranch = 'refs/heads/main'; size = 1048576; webUrl = "$org/Payments/_git/payments-docs" }, @{ id = 'aaaaaaaa-5555-0000-0000-000000000005'; name = 'old-api'; defaultBranch = 'refs/heads/main'; isDisabled = $true; webUrl = "$org/Payments/_git/old-api" })
        "$org/$p1/_apis/git/repositories/$r1/pushes"                       = & $list @(@{ date = (& $ago 1); pushedBy = @{ displayName = 'Alex Contoso' }; refUpdates = @(@{ name = 'refs/heads/main' }) })
        "$org/$p1/_apis/git/repositories/$r2/pushes"                       = & $list @(@{ date = (& $ago 400); pushedBy = @{ displayName = 'Kim Contoso' }; refUpdates = @(@{ name = 'refs/heads/main' }) })
        "$org/$p1/_apis/git/repositories/$r1/items|azure-pipelines.yml"    = & $file '/azure-pipelines.yml' $ci
        "$org/$p1/_apis/git/repositories/$r1/items|/templates/lint.yml"    = & $file '/templates/lint.yml' $lint
        "$org/$p1/_apis/git/repositories/shared-templates/items|/steps/scan.yml" = & $file '/steps/scan.yml' $scan
        "$org/$p1/_apis/git/repositories/shared-templates/items|/common/gitleaks.yml" = & $file '/common/gitleaks.yml' $gitleaks
        "$org/$p1/_apis/git/repositories/$r1/items|/package.json"          = & $file '/package.json' '{ "name": "payments", "scripts": { "prelint": "node tools/check.js", "lint": "eslint . && npm run format", "format": "prettier --check .", "build": "tsc" } }'
        "$org/$p1/_apis/git/repositories/$r1/items|/Makefile"              = & $file '/Makefile' "build:`n`tgo build ./...`n`ntest:`n`tgo test ./...`n`t@golangci-lint run"
        "$org/$p1/_apis/serviceendpoint/endpoints"                         = & $list @(
            @{ id = $e1; name = 'azure-prod'; type = 'azurerm'; isReady = $true; authorization = @{ scheme = 'ServicePrincipal'; parameters = @{ serviceprincipalid = 'AAAAAAAA-0000-0000-0000-00000000A001'; tenantid = 't' } }; data = @{ subscriptionId = 's-1'; subscriptionName = 'Contoso Production'; scopeLevel = 'Subscription' }; createdBy = @{ displayName = 'Sam Contoso' } }
            @{ id = $e2; name = 'azure-dev'; type = 'azurerm'; isReady = $true; authorization = @{ scheme = 'WorkloadIdentityFederation'; parameters = @{ serviceprincipalid = 'aaaaaaaa-0000-0000-0000-00000000a002' } }; data = @{ subscriptionId = 's-2'; subscriptionName = 'Contoso Dev' }; createdBy = @{ displayName = 'Sam Contoso' } }
            @{ id = $e3; name = 'github-old'; type = 'github'; isReady = $true; authorization = @{ scheme = 'Token'; parameters = @{} }; data = @{}; createdBy = @{ displayName = 'Kim Contoso' } }
        )
        "$org/$p1/_apis/pipelines/pipelinePermissions/endpoint/$e1"        = & $permission $true
        "$org/$p1/_apis/pipelines/pipelinePermissions/endpoint/$e2"        = & $permission $false @(1)
        "$org/$p1/_apis/pipelines/pipelinePermissions/endpoint/$e3"        = & $permission $false
        "$org/$p1/_apis/distributedtask/variablegroups"                    = & $list @(
            @{ id = 1; name = 'payments-secrets'; type = 'Vsts'; variables = @{ DbPassword = @{ isSecret = $true; value = $null }; ApiToken = @{ value = 'tok-123-visible-value' }; Region = @{ value = 'westeurope' } } }
            @{ id = 2; name = 'kv-linked'; type = 'AzureKeyVault'; providerData = @{ vault = 'kv-payments' }; variables = @{ SqlPassword = @{ isSecret = $true; value = $null } } }
        )
        "$org/$p1/_apis/pipelines/pipelinePermissions/variablegroup/1"     = & $permission $true
        "$org/$p1/_apis/pipelines/pipelinePermissions/variablegroup/2"     = & $permission $false @(1)
        "$org/$p1/_apis/distributedtask/environments"                      = & $list @(@{ id = 11; name = 'dev' })
        "$org/$p1/_apis/pipelines/pipelinePermissions/environment/11"      = & $permission $false @(1)
        "$org/$p1/_apis/pipelines/checks/configurations|11"                = & $list @(@{ id = 1; type = @{ name = 'Approval' }; settings = @{} })
        "$org/$p1/_apis/distributedtask/environments/11/environmentdeploymentrecords" = & $list @()
        "$org/$p1/_apis/policy/configurations"                             = & $list @(
            @{ id = 1; isEnabled = $true; isBlocking = $true; isDeleted = $false; type = @{ displayName = 'Minimum number of reviewers' }; settings = @{ minimumApproverCount = 2; scope = @(@{ repositoryId = $r1; refName = 'refs/heads/main'; matchKind = 'Exact' }) } }
            @{ id = 2; isEnabled = $true; isBlocking = $true; isDeleted = $false; type = @{ displayName = 'Build' }; settings = @{ buildDefinitionId = 1; scope = @(@{ repositoryId = $null; refName = 'refs/heads/main'; matchKind = 'Exact' }) } }
            @{ id = 3; isEnabled = $false; isBlocking = $true; isDeleted = $false; type = @{ displayName = 'Minimum number of reviewers' }; settings = @{ minimumApproverCount = 1; scope = @(@{ repositoryId = $r2; refName = 'refs/heads/main'; matchKind = 'Exact' }) } }
        )
        "$org/$p1/_apis/build/builds"                                      = & $list @(
            foreach ($day in 1..9) { & $run 1 'succeeded' $day }
            (& $run 1 'failed' 12)
            (& $run 1 'canceled' 13)
            (& $run 2 'succeeded' 3 15); (& $run 2 'succeeded' 5 15); (& $run 2 'failed' 6 15); (& $run 2 'failed' 7 15); (& $run 2 'failed' 8 15); (& $run 2 'failed' 10 15)
        )
        "$advsec/$p1/_apis/management/repositories/$r1/enablement"         = & $one @{ advSecEnabled = $true }
        "$advsec/$p1/_apis/management/repositories/$r2/enablement"         = & $one @{ advSecEnabled = $false }
        "$advsec/$p1/_apis/alert/repositories/$r1/alerts"                  = & $list @(
            @{ alertId = 1; alertType = 'secret'; severity = 'high'; state = 'active'; title = 'Azure storage key' }
            @{ alertId = 2; alertType = 'dependency'; severity = 'critical'; state = 'active'; title = 'Newtonsoft.Json' }
            @{ alertId = 3; alertType = 'code'; severity = 'medium'; state = 'active'; title = 'SQL injection' }
        )
        # Branches (GitFlow on payments; one branch on payments-docs), tags, pull requests, Git LFS.
        "$org/$p1/_apis/git/repositories/$r1/stats/branches"               = & $list @((& $branch 'main' 1), (& $branch 'develop' 2 3 0), (& $branch 'release/1.0' 10 0 4), (& $branch 'feature/old-idea' 200 1 90), (& $branch 'users/kim/spike' 150 2 70))
        "$org/$p1/_apis/git/repositories/$r2/stats/branches"               = & $list @((& $branch 'main' 400))
        "$org/$p1/_apis/git/repositories/$r1/refs"                         = & $list @(@{ name = 'refs/tags/v1.0' }, @{ name = 'refs/tags/v1.1' })
        "$org/$p1/_apis/git/repositories/$r1/pullrequests"                 = & $list @(@{ pullRequestId = 7; title = 'Add refunds' })
        "$org/$p1/_apis/git/repositories/$r1/items|/.gitattributes"        = & $file '/.gitattributes' '*.psd filter=lfs diff=lfs merge=lfs -text'
        # Classic release deployments to Production, a wiki, a test plan, a feed with npm and PyPI packages.
        "$vsrm/$p1/_apis/release/deployments"                              = & $list @(
            @{ id = 1; deploymentStatus = 'succeeded'; releaseEnvironment = @{ name = 'Production' }; queuedOn = (& $ago 4.5); completedOn = (& $ago 4) }
            @{ id = 2; deploymentStatus = 'failed'; releaseEnvironment = @{ name = 'Production' }; queuedOn = (& $ago 8.5); completedOn = (& $ago 8) }
            @{ id = 3; deploymentStatus = 'succeeded'; releaseEnvironment = @{ name = 'Production' }; queuedOn = (& $ago 7.6); completedOn = (& $ago 7.5) }
        )
        "$org/$p1/_apis/wiki/wikis"                                        = & $list @(@{ id = 'w1'; name = 'Payments.wiki'; type = 'projectWiki' })
        "$org/$p1/_apis/testplan/plans"                                    = & $list @(@{ id = 31; name = 'Payments regression'; state = 'Active'; areaPath = 'Payments'; iteration = 'Payments\Sprint 9'; owner = @{ displayName = 'Kim Contoso' }; updatedDate = (& $ago 3) })
        "$feeds/$p1/_apis/packaging/feeds"                                 = & $list @(@{ id = 'f1'; name = 'payments-feed'; upstreamSources = @(@{ name = 'npmjs' }) })
        "$feeds/$p1/_apis/packaging/Feeds/f1/packages"                     = & $list @(@{ name = 'payments-ui'; protocolType = 'Npm' }, @{ name = 'payments-sdk'; protocolType = 'Npm' }, @{ name = 'payments-tools'; protocolType = 'PyPi' })
        "$advsec/$p1/_apis/management/enablement"                          = & $one @{ enableOnCreate = $true; projectId = $p1 }
        # --- Platform ------------------------------------------------------------------------------------------
        "$org/$p2/_apis/build/definitions"                                 = & $list @(
            (& $definition 3 'infra' 2 'infra/pipeline.yml' (& $repo $r3 'infra') $null)
            (& $definition 4 'web' 2 'azure-pipelines.yml' (& $repo 'contoso/web' 'contoso/web' 'GitHub') (& $build 'partiallySucceeded' 3 4))
        )
        "https://vsrm.dev.azure.com/contoso/$p2/_apis/release/definitions" = & $list @()
        "$org/$p2/_apis/git/repositories"                                  = & $list @(@{ id = $r3; name = 'infra'; defaultBranch = 'refs/heads/main'; size = 2097152; webUrl = "$org/Platform/_git/infra" })
        "$org/$p2/_apis/git/repositories/$r3/pushes"                       = & $list @(@{ date = (& $ago 5); pushedBy = @{ displayName = 'Ola Contoso' }; refUpdates = @(@{ name = 'refs/heads/main' }) })
        "$org/$p2/_apis/git/repositories/$r3/items|infra/pipeline.yml"     = & $file '/infra/pipeline.yml' $infra
        "$org/$p2/_apis/git/repositories/$r3/items|/scripts/deploy.sh"     = & $file '/scripts/deploy.sh' "#!/bin/bash`nset -e`nflux reconcile kustomization apps --with-source`nacme-deployer push --env prod --token abcdefghijklmnopqrstuvwxyz0123456789`n./scripts/helper.sh"
        "$org/$p2/_apis/git/repositories/$r3/items|/scripts/helper.sh"     = & $file '/scripts/helper.sh' "yamllint .`nkeys rotate --all"
        "$org/$p2/_apis/serviceendpoint/endpoints"                         = & $list @()
        "$org/$p2/_apis/distributedtask/variablegroups"                    = & $list @()
        "$org/$p2/_apis/distributedtask/environments"                      = & $list @(@{ id = 21; name = 'production' })
        "$org/$p2/_apis/pipelines/pipelinePermissions/environment/21"      = & $permission $false @(3)
        "$org/$p2/_apis/pipelines/checks/configurations|21"                = & $list @()
        "$org/$p2/_apis/distributedtask/environments/21/environmentdeploymentrecords" = & $list @(
            @{ id = 1; result = 'succeeded'; queueTime = (& $ago 2); finishTime = (& $ago 2); owner = @{ id = 304 } }
            @{ id = 2; result = 'failed'; queueTime = (& $ago 9); finishTime = (& $ago 9) }
            @{ id = 3; result = 'succeeded'; queueTime = (& $ago 16); finishTime = (& $ago 16) }
            @{ id = 4; result = 'succeeded'; queueTime = (& $ago 23); finishTime = (& $ago 23) }
            @{ id = 5; result = 'failed'; queueTime = (& $ago 60); finishTime = (& $ago 60) }
        )
        "$org/$p2/_apis/policy/configurations"                             = & $list @()
        "$org/$p2/_apis/git/repositories/$r3/stats/branches"               = & $list @((& $branch 'main' 5), (& $branch 'feature/flux-upgrade' 3 2 0))
        "$org/$p2/_apis/build/builds"                                      = & $list @((& $run 4 'partiallySucceeded' 3))
        # --- Legacy --------------------------------------------------------------------------------------------
        "$org/$p3/_apis/build/definitions"                                 = & $list @()
        "https://vsrm.dev.azure.com/contoso/$p3/_apis/release/definitions" = @{ Status = 403; Body = $null; Items = $null; Error = 'TF400813: The user is not authorized to access this resource.' }
        "$org/$p3/_apis/git/repositories"                                  = & $list @()
        "$org/$p3/_apis/serviceendpoint/endpoints"                         = & $list @()
        "$org/$p3/_apis/distributedtask/variablegroups"                    = & $list @()
        "$org/$p3/_apis/distributedtask/environments"                      = & $list @()
        "$org/$p3/_apis/policy/configurations"                             = & $list @()
        "$org/$p3/_apis/build/builds"                                      = & $list @()
        # --- People: Payments' teams and Project Administrators (Platform has none; Legacy can't be read) -----------
        "$org/_apis/projects/$p1/teams"                                    = & $list @(@{ id = 'team-1'; name = 'Payments Team' }, @{ id = 'team-2'; name = 'Web Team' })
        "$org/_apis/projects/$p1/teams/team-1/members"                     = & $list @(
            @{ isTeamAdmin = $true; identity = @{ id = 'u-alex'; displayName = 'Alex Contoso'; uniqueName = 'alex@contoso.com' } }
            @{ identity = @{ id = 'u-kim'; displayName = 'Kim Contoso'; uniqueName = 'kim@contoso.com' } }
        )
        "$org/_apis/projects/$p1/teams/team-2/members"                     = & $list @(
            @{ isTeamAdmin = $true; identity = @{ id = 'u-sam'; displayName = 'Sam Contoso'; uniqueName = 'sam@contoso.com' } }
            @{ identity = @{ id = 'u-alex'; displayName = 'Alex Contoso'; uniqueName = 'alex@contoso.com' } }
        )
        'https://vssps.dev.azure.com/contoso/_apis/identities|filter=[Payments]\Project Administrators' = & $list @(@{ id = 'g-admins'; providerDisplayName = '[Payments]\Project Administrators'; isContainer = $true; members = @('d-alex', 'd-ops') })
        'https://vssps.dev.azure.com/contoso/_apis/identities|descriptors=d-alex,d-ops' = & $list @(
            @{ id = 'i-alex'; providerDisplayName = 'Alex Contoso'; isContainer = $false; properties = @{ Mail = @{ '$value' = 'alex@contoso.com' }; Account = @{ '$value' = 'alex@contoso.com' } } }
            @{ id = 'i-ops'; providerDisplayName = 'Contoso Ops'; isContainer = $true; properties = @{ Account = @{ '$value' = '[contoso]\Contoso Ops' } } }
        )
        "$org/_apis/projects/$p2/teams"                                    = & $list @()
        'https://vssps.dev.azure.com/contoso/_apis/identities|filter=[Platform]\Project Administrators' = & $list @()
        # --- The organization's own: a feed, agent pools, service hooks, extensions ---------------------------------
        "$feeds/_apis/packaging/feeds"                                     = & $list @(@{ id = 'f0'; name = 'shared' })
        "$feeds/_apis/packaging/Feeds/f0/packages"                         = & $list @(@{ name = 'Contoso.Common'; protocolType = 'NuGet' })
        "$org/_apis/distributedtask/pools"                                 = & $list @(@{ id = 1; name = 'Azure Pipelines'; isHosted = $true; poolType = 'automation' }, @{ id = 7; name = 'onprem-linux'; isHosted = $false; poolType = 'automation' })
        "$org/_apis/distributedtask/pools/7/agents"                        = & $list @(@{ id = 1; name = 'agent-1'; status = 'online'; enabled = $true }, @{ id = 2; name = 'agent-2'; status = 'offline'; enabled = $true })
        "$org/_apis/hooks/subscriptions"                                   = & $list @(@{ id = 'h1'; publisherId = 'tfs'; eventType = 'git.push'; consumerId = 'teams'; publisherInputs = @{ projectId = $p1 } })
        'https://extmgmt.dev.azure.com/contoso/_apis/extensionmanagement/installedextensions' = & $list @(
            @{ publisherId = 'fabrikam'; publisherName = 'Fabrikam Tools'; extensionId = 'replacetokens'; extensionName = 'Replace Tokens'; version = '6.0.0'; flags = 'none'; installState = @{ flags = 'none' } }
            @{ publisherId = 'ms'; publisherName = 'Microsoft'; extensionId = 'vss-code-search'; extensionName = 'Code Search'; version = '1.0'; flags = 'builtIn'; installState = @{ flags = 'none' } }
            @{ publisherId = 'acme'; publisherName = 'Acme'; extensionId = 'unused-widget'; extensionName = 'Unused widget'; version = '0.1'; flags = 'none'; installState = @{ flags = 'disabled' } }
        )
        # --- Discovery, and a second organization ------------------------------------------------------------------
        'https://app.vssps.visualstudio.com/_apis/profile/profiles/me'     = & $one @{ id = 'member-1'; displayName = 'Alex Contoso' }
        'https://app.vssps.visualstudio.com/_apis/accounts'                = & $list @(@{ accountName = 'contoso' }, @{ accountName = 'fabrikam' })
        'https://dev.azure.com/fabrikam/_apis/projects'                    = & $list @(@{ id = '44444444-aaaa-0000-0000-000000000004'; name = 'Mobile'; state = 'wellFormed'; visibility = 'private' })
        'https://dev.azure.com/fabrikam/44444444-aaaa-0000-0000-000000000004/_apis/build/definitions' = & $list @()
        'https://dev.azure.com/fabrikam/44444444-aaaa-0000-0000-000000000004/_apis/git/repositories' = & $list @()
        'https://vsrm.dev.azure.com/fabrikam/44444444-aaaa-0000-0000-000000000004/_apis/release/definitions' = & $list @()
    }
    @{ Organization = $org; Answers = $answers; Secret = 'SuperSecret123!'; VariableValue = 'tok-123-visible-value' }
}

# The answer to one request: by its path; a file (items?path=) by repository and path; checks by resource.
function Get-AACContosoDevOpsAnswer {
    param([hashtable] $Data, [string] $Uri)
    $path = ($Uri -split '\?', 2)[0]
    if ($path -like '*/items') {
        $file = [System.Uri]::UnescapeDataString(([regex]::Match($Uri, '[?&]path=([^&]+)')).Groups[1].Value)
        $path = "$path|$file"
    }
    elseif ($path -like '*/checks/configurations') { $path = "$path|$(([regex]::Match($Uri, '[?&]resourceId=([^&]+)')).Groups[1].Value)" }
    elseif ($path -like '*/_apis/identities') {
        # Identities by search (filterValue) or by descriptors.
        $by = [regex]::Match($Uri, '[?&](filterValue|descriptors)=([^&]+)')
        $path = "$path|$(@{ filterValue = 'filter'; descriptors = 'descriptors' }[$by.Groups[1].Value])=$([System.Uri]::UnescapeDataString($by.Groups[2].Value))"
    }
    if ($Data.Answers.Contains($path)) { return $Data.Answers[$path] }
    @{ Status = 404; Body = $null; Items = $null; Error = 'TF401174: The item could not be found.' }
}
