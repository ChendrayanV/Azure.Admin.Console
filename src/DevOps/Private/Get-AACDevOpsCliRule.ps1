function Get-AACDevOpsCliRule {
    <#
    .SYNOPSIS
        How Invoke-AACADOAssessment finds a tool's version: the installer tasks
        that set it, and the commands that install a package at a version.
    .DESCRIPTION
        The tools themselves are in the tool catalogue (Get-AACDevOpsToolRule);
        each catalogue entry's VersionOf names the Installer tool below.
        Returns @{
          Installer  - task name -> @{ Tool; Inputs (the inputs holding the
                       version, first found wins); Default } - UseNode@1's
                       version sets Node.js, HelmInstaller@1's
                       helmVersionToInstall sets Helm...
          Package    - @{ Tool (a label); Pattern } with two groups (name,
                       version): npm install -g x@1.2, pip install x==1.2,
                       Install-Module -RequiredVersion, choco --version,
                       dotnet tool install --version
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $installer = { param([string] $Tool, [string[]] $Inputs, [string] $Default = '') @{ Tool = $Tool; Inputs = $Inputs; Default = $Default } }
    @{
        Installer = @{
            UseNode                 = & $installer 'Node.js' @('version', 'versionSpec')
            NodeTool                = & $installer 'Node.js' @('versionSpec', 'version')
            UseDotNet               = & $installer '.NET SDK' @('version', 'versionSpec')
            UsePythonVersion        = & $installer 'Python' @('versionSpec', 'version')
            UseRubyVersion          = & $installer 'Ruby' @('versionSpec')
            JavaToolInstaller       = & $installer 'Java' @('versionSpec')
            GoTool                  = & $installer 'Go' @('version')
            HelmInstaller           = & $installer 'Helm' @('helmVersionToInstall', 'helmVersion')
            KubectlInstaller        = & $installer 'kubectl' @('kubectlVersion')
            TerraformInstaller      = & $installer 'Terraform' @('terraformVersion', 'version')
            NuGetToolInstaller      = & $installer 'NuGet' @('versionSpec')
            DockerInstaller         = & $installer 'Docker' @('dockerVersion')
            AzurePowerShell         = & $installer 'Az PowerShell' @('azurePowerShellVersion', 'preferredAzurePowerShellVersion', 'customVersion') 'agent default'
            Maven                   = & $installer 'Java' @('jdkVersionOption', 'jdkVersion')
            Gradle                  = & $installer 'Java' @('jdkVersionOption', 'jdkVersion')
            VSBuild                 = & $installer 'MSBuild' @('vsVersion') 'latest'
            MSBuild                 = & $installer 'MSBuild' @('msbuildVersion') 'latest'
            BicepInstall            = & $installer 'Bicep' @('version')
            PowerShell              = & $installer 'PowerShell' @()
        }
        Package   = @(
            @{ Tool = 'npm (global)'; Pattern = 'npm\s+(?:install|i)\s+(?:-g|--global)\s+[^\n]*?(@?[\w./-]+?)@(\d[\w.-]*)' }
            @{ Tool = 'pip'; Pattern = 'pip3?\s+install\s+[^\n]*?([\w.-]+)==([\w.]+)' }
            @{ Tool = 'PowerShell module'; Pattern = 'Install-Module\s+[^\n]*?-Name\s+[''"]?([\w.]+)[''"]?[^\n]*?-RequiredVersion\s+[''"]?([\w.-]+)' }
            @{ Tool = 'Chocolatey'; Pattern = 'choco\s+install\s+([\w.-]+)[^\n]*?--version[= ]([\w.-]+)' }
            @{ Tool = 'dotnet tool'; Pattern = 'dotnet\s+tool\s+install\s+[^\n]*?([\w.-]+)\s+--version\s+([\w.-]+)' }
        )
    }
}
