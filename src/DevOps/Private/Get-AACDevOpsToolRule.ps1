function Get-AACDevOpsToolRule {
    <#
    .SYNOPSIS
        The tool catalogue of Invoke-AACADOAssessment: every tool it recognises
        in a pipeline - its category, what it does, and the regular
        expression that finds it.
    .DESCRIPTION
        One list for everything (the category columns, the Tools tab, the
        evidence and the findings all come from it, so they can't disagree).
        Categories:
          Lint, Build, Test, Security, Deploy, Publish   stages of a pipeline
                                                         (the findings - no
                                                         linting, no tests, no
                                                         security scanning -
                                                         read these)
          SBOM                                           software bill of
                                                         materials generators
                                                         and validators (the
                                                         SBOM tab reads these)
          GitOps                                         Flux, Argo CD,
                                                         Kustomize...
          Tooling                                        command-line tools
                                                         that are no stage of
                                                         their own (az, git,
                                                         jq, Node.js...)
        A pattern is matched, ignoring case, line by line against each file
        the pipeline runs - its YAML and templates (comments and
        displayName taken out), the script files it calls, the package.json
        scripts and Makefile targets it runs, a classic pipeline's tasks - so
        it finds a task (SonarCloudPrepare@1), a CLI in a script (trivy
        image ...), a command's input (command: test) or a container image
        (fluxcd/flux-cli). VersionOf names the installer's tool (Get-AACDevOpsCliRule)
        whose version applies (UseNode@1 -> Node.js). -ToolRule and
        -ToolRulePath on the command add rules of your own.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $rule = {
        param([string] $Category, [string] $Tool, [string] $Pattern, [string] $Purpose = '', [string] $VersionOf = '')
        [pscustomobject]@{ Category = $Category; Tool = $Tool; Pattern = $Pattern; Purpose = $Purpose; VersionOf = $(if ($VersionOf) { $VersionOf } else { $Tool }) }
    }
    @(
        # --- Lint and static checks -----------------------------------------------------------------------------------
        & $rule 'Lint' 'ESLint' '\beslint\b' 'Lints JavaScript and TypeScript'
        & $rule 'Lint' 'Prettier' '\bprettier\b' 'Checks code formatting'
        & $rule 'Lint' 'Stylelint' '\bstylelint\b' 'Lints CSS'
        & $rule 'Lint' 'Pylint' '\bpylint\b' 'Lints Python'
        & $rule 'Lint' 'Flake8' '\bflake8\b' 'Lints Python'
        & $rule 'Lint' 'Ruff' '\bruff\b' 'Lints and formats Python'
        & $rule 'Lint' 'Black' '\bblack\s+(--check|\.)' 'Checks Python formatting'
        & $rule 'Lint' 'mypy' '\bmypy\b' 'Type-checks Python'
        & $rule 'Lint' 'PSScriptAnalyzer' 'PSScriptAnalyzer|Invoke-ScriptAnalyzer' 'Lints PowerShell'
        & $rule 'Lint' 'ShellCheck' '\bshellcheck\b' 'Lints shell scripts'
        & $rule 'Lint' 'Hadolint' '\bhadolint\b' 'Lints Dockerfiles'
        & $rule 'Lint' 'yamllint' '\byamllint\b' 'Lints YAML'
        & $rule 'Lint' 'markdownlint' 'markdownlint' 'Lints Markdown'
        & $rule 'Lint' 'TFLint' '\btflint\b' 'Lints Terraform'
        & $rule 'Lint' 'terraform fmt / validate' 'terraform\s+(fmt|validate)' 'Checks Terraform formatting and syntax' 'Terraform'
        & $rule 'Lint' 'golangci-lint' 'golangci-lint' 'Lints Go'
        & $rule 'Lint' 'RuboCop' '\brubocop\b' 'Lints Ruby'
        & $rule 'Lint' 'dotnet format' 'dotnet\s+format' 'Checks .NET formatting' '.NET SDK'
        & $rule 'Lint' 'Bicep linter' '\bbicep\s+(build|lint)\b|az\s+bicep\s+(build|lint)\b' 'Lints Bicep' 'Bicep'
        & $rule 'Lint' 'MegaLinter' 'megalinter|mega-linter' 'Runs many linters at once'
        & $rule 'Lint' 'Super-Linter' 'super-linter' 'Runs many linters at once'
        & $rule 'Lint' 'ansible-lint' 'ansible-lint' 'Lints Ansible playbooks'
        & $rule 'Lint' 'SQLFluff' '\bsqlfluff\b' 'Lints SQL'
        & $rule 'Lint' 'commitlint' '\bcommitlint\b' 'Checks commit messages'
        & $rule 'Lint' 'cspell' '\bcspell\b' 'Checks spelling'
        & $rule 'Lint' 'kube-linter' 'kube-linter' 'Lints Kubernetes manifests'
        & $rule 'Lint' 'kubeconform / kubeval' '\bkubeconform\b|\bkubeval\b' 'Validates Kubernetes manifests'
        & $rule 'Lint' 'helm lint' 'helm\s+lint\b' 'Lints Helm charts' 'Helm'
        & $rule 'Lint' 'editorconfig-checker' 'editorconfig-checker|\bec\s+-' 'Checks .editorconfig rules'
        & $rule 'Lint' 'pre-commit' '\bpre-commit\s+run\b' 'Runs the repository''s pre-commit hooks'
        & $rule 'Lint' 'Checkstyle / SpotBugs' '\bcheckstyle\b|\bspotbugs\b' 'Lints Java'
        # --- Build ----------------------------------------------------------------------------------------------------
        & $rule 'Build' '.NET' 'DotNetCoreCLI@|dotnet\s+(build|publish|pack|restore)\b' 'Restores, builds and publishes .NET' '.NET SDK'
        & $rule 'Build' 'MSBuild' 'VSBuild@|MSBuild@|\bmsbuild\b' 'Builds Visual Studio solutions'
        & $rule 'Build' 'NuGet restore' 'NuGetCommand@|NuGetToolInstaller@|\bnuget(\.exe)?\s+restore\b' 'Restores NuGet packages' 'NuGet'
        & $rule 'Build' 'Maven' 'Maven@|\bmvnw?\s' 'Builds Java projects' 'Java'
        & $rule 'Build' 'Gradle' 'Gradle@|\bgradlew?\s' 'Builds Java and Android projects' 'Java'
        & $rule 'Build' 'npm' 'Npm@|\bnpm\s+(ci|install|run|run-script)\b' 'Installs packages and runs scripts' 'Node.js'
        & $rule 'Build' 'Yarn' '\byarn\s+(install|build|--frozen-lockfile)\b' 'Installs packages and runs scripts' 'Node.js'
        & $rule 'Build' 'pnpm' '\bpnpm\s+(install|build|run)\b' 'Installs packages and runs scripts' 'Node.js'
        & $rule 'Build' 'Python' 'UsePythonVersion@|\bpip3?\s+install|python3?\s+-m\s+build|\bpoetry\s+(install|build)' 'Installs Python packages and builds' 'Python'
        & $rule 'Build' 'Go' 'GoTool@|\bgo\s+build\b' 'Builds Go'
        & $rule 'Build' 'Rust' '\bcargo\s+build\b' 'Builds Rust'
        & $rule 'Build' 'Docker' 'Docker@|DockerCompose@|docker\s+(build|buildx|compose)\b|\bbuildah\s+bud\b|\bkaniko\b' 'Builds container images'
        & $rule 'Build' 'Terraform' 'TerraformTask|TerraformInstaller@|terraform\s+(init|plan)\b' 'Plans infrastructure'
        & $rule 'Build' 'Packer' '\bpacker\s+build\b' 'Builds machine images'
        & $rule 'Build' 'Make' '(^|[\s;&|(])make(\s+-?[\w-]+)*\s*$' 'Runs a Makefile'
        # --- Test -----------------------------------------------------------------------------------------------------
        & $rule 'Test' 'VSTest' 'VSTest@' 'Runs .NET and Visual Studio tests'
        & $rule 'Test' 'dotnet test' 'dotnet\s+test\b|\bcommand:\s*[''"]?test\b' 'Runs .NET tests' '.NET SDK'
        & $rule 'Test' 'Pester' 'Invoke-Pester|\bPester\b' 'Runs PowerShell tests'
        & $rule 'Test' 'pytest' '\bpytest\b' 'Runs Python tests' 'Python'
        & $rule 'Test' 'Jest' '\bjest\b' 'Runs JavaScript tests' 'Node.js'
        & $rule 'Test' 'Mocha' '\bmocha\b' 'Runs JavaScript tests' 'Node.js'
        & $rule 'Test' 'go test' '\bgo\s+test\b' 'Runs Go tests' 'Go'
        & $rule 'Test' 'Playwright / Cypress' '\bplaywright\b|\bcypress\b' 'Runs browser tests'
        & $rule 'Test' 'Test results published' 'PublishTestResults@' 'Publishes test results to the run'
        & $rule 'Test' 'Code coverage' 'PublishCodeCoverageResults@|\bcoverlet\b|--coverage\b|XPlat Code Coverage' 'Measures code coverage'
        # --- Security scanning ----------------------------------------------------------------------------------------
        & $rule 'Security' 'Microsoft Security DevOps' 'MicrosoftSecurityDevOps@' 'Runs Microsoft''s security analyzers'
        & $rule 'Security' 'Advanced Security (CodeQL)' 'AdvancedSecurity-Codeql|\bcodeql\b' 'Scans code (CodeQL)'
        & $rule 'Security' 'Advanced Security (dependencies)' 'AdvancedSecurity-Dependency-Scanning@' 'Scans dependencies'
        & $rule 'Security' 'Credential Scanner' 'CredScan@|CredentialScanner' 'Scans for credentials'
        & $rule 'Security' 'SonarQube' 'SonarQube(Prepare|Analyze|Publish)@|\bsonar-scanner\b|dotnet\s+sonarscanner\b' 'Analyses code quality and security'
        & $rule 'Security' 'SonarCloud' 'SonarCloud(Prepare|Analyze|Publish)@' 'Analyses code quality and security'
        & $rule 'Security' 'Snyk' 'SnykSecurityScan@|\bsnyk\s+(test|code|container|iac|monitor)\b' 'Scans dependencies, code and containers'
        & $rule 'Security' 'Trivy' '\btrivy\b|aquasec/trivy' 'Scans images, files and IaC'
        & $rule 'Security' 'Checkov' '\bcheckov\b' 'Scans infrastructure as code'
        & $rule 'Security' 'tfsec' '\btfsec\b' 'Scans Terraform'
        & $rule 'Security' 'Terrascan' '\bterrascan\b' 'Scans infrastructure as code'
        & $rule 'Security' 'KICS' '\bkics\b' 'Scans infrastructure as code'
        & $rule 'Security' 'Mend (WhiteSource)' 'WhiteSource|\bmend\s+(scan|dep|code)' 'Scans dependencies'
        & $rule 'Security' 'Black Duck' 'BlackDuck|synopsys-detect|\bdetect\.sh\b' 'Scans dependencies'
        & $rule 'Security' 'Veracode' '\bveracode' 'Scans code'
        & $rule 'Security' 'Checkmarx' 'checkmarx|\bcxflow\b|\bCxScan' 'Scans code'
        & $rule 'Security' 'Fortify' '\bfortify\b' 'Scans code'
        & $rule 'Security' 'Gitleaks' '\bgitleaks\b' 'Scans for secrets'
        & $rule 'Security' 'TruffleHog' 'trufflehog' 'Scans for secrets'
        & $rule 'Security' 'detect-secrets' 'detect-secrets' 'Scans for secrets'
        & $rule 'Security' 'OWASP Dependency-Check' 'dependency-check' 'Scans dependencies'
        & $rule 'Security' 'OWASP ZAP' '\bowasp\s*zap\b|\bzap-(baseline|full-scan|api-scan)' 'Scans running web apps'
        & $rule 'Security' 'npm audit' 'npm\s+audit\b' 'Scans npm dependencies' 'Node.js'
        & $rule 'Security' 'dotnet vulnerable packages' 'package\s+--vulnerable' 'Lists vulnerable NuGet packages' '.NET SDK'
        & $rule 'Security' 'pip-audit / Safety' 'pip-audit|\bsafety\s+check\b' 'Scans Python dependencies'
        & $rule 'Security' 'Grype / Syft' '\bgrype\b|\banchore\b|\bsyft\b' 'Scans images and builds an SBOM'
        & $rule 'Security' 'PSRule for Azure' 'ps-rule-assert|Assert-PSRule' 'Checks Azure IaC against the Well-Architected Framework'
        & $rule 'Security' 'Template Analyzer' 'TemplateAnalyzer' 'Scans ARM and Bicep templates'
        & $rule 'Security' 'Kubescape' '\bkubescape\b' 'Scans Kubernetes configuration'
        & $rule 'Security' 'Cosign' '\bcosign\s+(sign|verify)\b' 'Signs or verifies container images'
        # --- SBOM: a software bill of materials for what the pipeline builds -----------------------------------------
        # The Microsoft SBOM Tool (github.com/microsoft/sbom-tool) as a CLI, a .NET tool, the MSBuild targets
        # or the Manifest Generator task; 1ES Pipeline Templates run it for every pipeline that extends them.
        & $rule 'SBOM' 'Microsoft SBOM Tool' '\bsbom-tool(\.exe)?\b[^\n]*\bgenerate\b|Microsoft\.Sbom\.DotNetTool|ManifestGeneratorTask@|manifest-generator-task' 'Generates an SPDX SBOM of the build drop (Microsoft SBOM Tool)'
        & $rule 'SBOM' 'Microsoft SBOM Tool (MSBuild)' 'Microsoft\.Sbom\.Targets|GenerateSBOM\s*[=>:]\s*["'']?true' 'Generates an SPDX SBOM as part of dotnet build or pack' 'Microsoft SBOM Tool'
        & $rule 'SBOM' 'Microsoft SBOM Tool (validate)' '\bsbom-tool(\.exe)?\b[^\n]*\bvalidate\b' 'Checks a build drop against its SBOM - nothing added, changed or missing' 'Microsoft SBOM Tool'
        & $rule 'SBOM' '1ES Pipeline Templates' '1ES\.(Official|Unofficial)\.PipelineTemplate|1ESPipelineTemplates' 'Microsoft 1ES templates: an SBOM for every build, unless sbom: enabled: false'
        & $rule 'SBOM' 'Syft' '\bsyft\b' 'Generates an SBOM (SPDX or CycloneDX) of an image or a folder'
        & $rule 'SBOM' 'CycloneDX' '\bcyclonedx\b|\bcdxgen\b' 'Generates a CycloneDX SBOM'
        & $rule 'SBOM' 'Trivy (SBOM)' '\btrivy\b[^\n]*--format\s+(spdx|spdx-json|cyclonedx)\b' 'Generates an SBOM with Trivy' 'Trivy'
        & $rule 'SBOM' 'Docker SBOM' 'docker\s+sbom\b|--sbom[=\s]+true|--attest\s+type=sbom' 'Generates or attests a container image''s SBOM' 'Docker'
        # --- Deploy ---------------------------------------------------------------------------------------------------
        & $rule 'Deploy' 'Azure App Service' 'AzureWebApp@|AzureRmWebAppDeployment@|AzureWebAppContainer@|az\s+webapp\s+(deploy|deployment)' 'Deploys to Azure App Service'
        & $rule 'Deploy' 'Azure Functions' 'AzureFunctionApp@|AzureFunctionAppContainer@|\bfunc\s+azure\s+functionapp\s+publish' 'Deploys Azure Functions'
        & $rule 'Deploy' 'Azure Static Web Apps' 'AzureStaticWebApp@|\bswa\s+deploy\b' 'Deploys an Azure Static Web App'
        & $rule 'Deploy' 'Azure Container Apps' 'AzureContainerApps@|az\s+containerapp\s+(up|update|create)' 'Deploys to Azure Container Apps'
        & $rule 'Deploy' 'ARM / Bicep' 'AzureResourceManagerTemplateDeployment@|az\s+deployment\s+(group|sub|mg|tenant)\s+create|New-AzResourceGroupDeployment' 'Deploys ARM or Bicep templates'
        & $rule 'Deploy' 'Azure Developer CLI' '\bazd\s+(up|provision|deploy)\b' 'Provisions and deploys an azd application' 'Azure Developer CLI (azd)'
        & $rule 'Deploy' 'Kubernetes' 'KubernetesManifest@|Kubernetes@|\bkubectl\s+(apply|rollout|set\s+image)\b' 'Deploys to Kubernetes' 'kubectl'
        & $rule 'Deploy' 'Helm' 'HelmDeploy@|\bhelm\s+(upgrade|install)\b' 'Installs and upgrades Helm charts'
        & $rule 'Deploy' 'Terraform apply' 'terraform\s+apply\b|\bcommand:\s*[''"]?apply\b' 'Applies infrastructure changes' 'Terraform'
        & $rule 'Deploy' 'Pulumi' '\bpulumi\s+(up|preview)\b' 'Deploys infrastructure as code'
        & $rule 'Deploy' 'Ansible' '\bansible-playbook\b' 'Configures machines with playbooks'
        & $rule 'Deploy' 'SQL database (DACPAC)' 'SqlAzureDacpacDeployment@|SqlDacpacDeploymentOnMachineGroup@|\bsqlpackage(\.exe)?\b' 'Deploys SQL database projects'
        & $rule 'Deploy' 'Azure CLI' 'AzureCLI@' 'Runs Azure CLI on a service connection'
        & $rule 'Deploy' 'Azure PowerShell' 'AzurePowerShell@' 'Runs Az PowerShell on a service connection' 'Az PowerShell'
        & $rule 'Deploy' 'Environments (approvals)' '^\s*environment:' 'Deploys through an environment (its checks apply)'
        # --- GitOps ---------------------------------------------------------------------------------------------------
        & $rule 'GitOps' 'Flux' '\bflux\s+(bootstrap|reconcile|install|check|create|get|diff|build|push|tag|suspend|resume|export|logs)\b|fluxcd|FluxCLI@' 'Reconciles Kubernetes from Git (Flux)'
        & $rule 'GitOps' 'Argo CD' '\bargocd\s+(app|login|sync|proj|repo|cluster)\b|argoproj' 'Syncs Kubernetes from Git (Argo CD)'
        & $rule 'GitOps' 'Kustomize' '\bkustomize\s+(build|edit)\b|\bkubectl\s+kustomize\b|^\s*kustomization:' 'Builds Kubernetes manifests'
        & $rule 'GitOps' 'GitOps repository update' 'git\s+commit[^\n]*(image|tag|bump|release|deploy)|yq\s+[^\n]*\.image' 'Commits a new version to a GitOps repository'
        # --- Publish --------------------------------------------------------------------------------------------------
        & $rule 'Publish' 'Pipeline artifacts' 'PublishPipelineArtifact@|PublishBuildArtifacts@' 'Publishes build output to the run'
        & $rule 'Publish' 'NuGet push' 'dotnet\s+nuget\s+push|\bnuget(\.exe)?\s+push\b|\bcommand:\s*[''"]?push\b[^\n]*nuget' 'Publishes NuGet packages' 'NuGet'
        & $rule 'Publish' 'npm publish' 'npm\s+publish\b' 'Publishes npm packages' 'Node.js'
        & $rule 'Publish' 'Container image push' 'docker\s+push\b|\bcommand:\s*[''"]?(push|buildAndPush)\b|az\s+acr\s+(build|import)\b' 'Pushes container images' 'Docker'
        & $rule 'Publish' 'Helm chart push' 'helm\s+push\b' 'Publishes Helm charts' 'Helm'
        & $rule 'Publish' 'Universal Packages' 'UniversalPackages@' 'Publishes Universal Packages'
        & $rule 'Publish' 'PowerShell Gallery' 'Publish-Module|Publish-PSResource' 'Publishes PowerShell modules'
        # --- Tooling: command-line tools that are no stage of their own ----------------------------------------------
        & $rule 'Tooling' 'Azure CLI (az)' '(^|[\s;&|(])az\s+[a-z]' 'Manages Azure from the command line'
        & $rule 'Tooling' 'Az PowerShell' '\b(Connect-AzAccount|(Get|New|Set|Remove|Update|Invoke|Start|Stop)-Az[A-Z]\w+)\b' 'Manages Azure from PowerShell'
        & $rule 'Tooling' 'kubectl' '\bkubectl\s+(get|describe|logs|exec|create|delete|config|wait|patch)\b|KubectlInstaller@' 'Inspects and changes Kubernetes objects'
        & $rule 'Tooling' 'kubelogin' '\bkubelogin\b' 'Signs in to AKS with Entra ID'
        & $rule 'Tooling' 'Node.js' '(^|[\s;&|(])(node|npx)\s+\S|UseNode@|NodeTool@' 'Runs JavaScript'
        & $rule 'Tooling' 'Python' '(^|[\s;&|(])python3?\s' 'Runs Python'
        & $rule 'Tooling' 'PowerShell' '^\s*-\s+(pwsh|powershell)\s*:|PowerShell@|\bpwsh\s+-' 'Runs PowerShell scripts'
        & $rule 'Tooling' 'Git' '(^|[\s;&|(])git\s+(clone|push|tag|checkout|config|fetch|pull|submodule)\b' 'Clones, tags or pushes Git repositories'
        & $rule 'Tooling' 'GitHub CLI' '(^|[\s;&|(])gh\s+(pr|release|api|repo|issue|auth)\b' 'Calls GitHub'
        & $rule 'Tooling' 'curl / wget' '\b(curl|wget|Invoke-WebRequest|Invoke-RestMethod)\b' 'Downloads files or calls web APIs'
        & $rule 'Tooling' 'jq / yq' '(^|[\s;&|(])(jq|yq)\s' 'Reads and edits JSON or YAML'
        & $rule 'Tooling' 'sqlcmd' '\bsqlcmd\b|\bInvoke-Sqlcmd\b' 'Runs SQL scripts'
        & $rule 'Tooling' 'Chocolatey' '\bchoco\s+install\b' 'Installs Windows packages'
        & $rule 'Tooling' 'apt / yum / apk' '\b(apt-get|apt|yum|dnf|apk)\s+(install|add)\b' 'Installs Linux packages on the agent'
        & $rule 'Tooling' 'Azure Functions Core Tools' '\bfunc\s+(start|pack|new)\b' 'Runs and packs Azure Functions'
        & $rule 'Tooling' 'Docker (run)' 'docker\s+(run|pull|login|tag|image|exec)\b' 'Runs or pulls container images' 'Docker'
    )
}
