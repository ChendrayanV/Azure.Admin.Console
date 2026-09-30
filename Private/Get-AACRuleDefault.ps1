function Get-AACRuleDefault {
    <#
    .SYNOPSIS
        Reads a defaults table from one of the module's PSRule rule files
        without running it: the plain hashtable a function there returns
        (Get-AACNamingDefault, Get-AACTagDefault). Used by Invoke-AACPSRule's
        plan and Get-AACInventory -Insight's tag coverage.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $File,

        [Parameter(Mandatory)]
        [string] $Function
    )

    $path = Join-Path -Path (Join-Path -Path $script:AACModuleRoot -ChildPath 'PSRule/Rules') -ChildPath $File
    if (-not (Test-Path -LiteralPath $path)) { return @{} }
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -like "*$Function" }, $true)
    $table = if ($definition) { $definition.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true) }
    if ($table) { $table.SafeGetValue() } else { @{} }
}
