function New-AACArchitectureDiagram {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Step 5: draws the design as Mermaid, Markdown and draw.io files,
        coloured by its findings, with compliance layers.
    .DESCRIPTION
        Writes <name>.mmd, <name>.md (renders in Azure DevOps wikis, GitHub
        and VS Code) and <name>.drawio into -Path. Green, amber and red show
        each component's worst open finding; the layers add WAF badges,
        policy, guardrail zones, the PSRule gate and Advisor. Offline.

        The .drawio has five pages: Cover, Architecture (Azure icons in
        landing zone, region, virtual network and data boxes, each layer
        on a draw.io layer), Policy and compliance (inherited assignments
        and the Azure Policy and PSRule rule for each component), Findings,
        and Legend.
    .PARAMETER Design
        The design, or the path of a saved one.
    .PARAMETER Path
        The folder to write to.
    .PARAMETER Format
        Mermaid, Markdown, DrawIo (all by default).
    .PARAMETER Layer
        Waf, Policy, Guardrail, PSRule, Recommendations (all by default).
    .PARAMETER GuardrailPath
        Your guardrails, so their findings are drawn too.
    .PARAMETER Accept
        Accepted risks, drawn as resolved.
    .PARAMETER PSRuleBaseline
        The PSRule baseline shown on the gate (Azure.Default).
    .EXAMPLE
        New-AACArchitectureDiagram -Design $design -Path .\diagrams
        All three files, every layer.
    .OUTPUTS
        System.IO.FileInfo
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object] $Design,

        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('Mermaid', 'Markdown', 'DrawIo')]
        [string[]] $Format = @('Mermaid', 'Markdown', 'DrawIo'),

        [ValidateSet('Waf', 'Policy', 'Guardrail', 'PSRule', 'Recommendations')]
        [string[]] $Layer = @('Waf', 'Policy', 'Guardrail', 'PSRule', 'Recommendations'),

        [string] $GuardrailPath,

        [string[]] $Accept = @(),

        [string] $PSRuleBaseline = 'Azure.Default'
    )

    process {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }
        $resolve = { param([string] $Value) if ($Value) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Value) } }
        $catalog = Get-AACArchitectureCatalog
        $model = Resolve-AACArchitectureInput -InputObject $(if ($Design -is [string]) { & $resolve $Design } else { $Design }) -Kind Design
        $guard = if ($GuardrailPath) { Read-AACArchitectureFile -Path (& $resolve $GuardrailPath) -What 'the guardrails' } else { @{} }
        $result = Invoke-AACArchitectureRule -Design $model -Catalog $catalog -Guardrail $guard -Accept $Accept
        $folder = & $resolve $Path
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        $base = ($model.Name -replace '[^A-Za-z0-9._-]', '-').Trim('-')
        if (-not $base) { $base = 'architecture' }
        $mermaid = ConvertTo-AACArchitectureMermaid -Design $model -Finding $result.Findings -Catalog $catalog -Layer $Layer -PSRuleBaseline $PSRuleBaseline
        $write = {
            param([string] $Name, [string] $Content)
            $file = Join-Path -Path $folder -ChildPath $Name
            if (-not $PSCmdlet.ShouldProcess($file, 'Write the diagram')) { return }
            [System.IO.File]::WriteAllText($file, $Content, [System.Text.UTF8Encoding]::new($false))
            Get-Item -LiteralPath $file
        }

        if ($Format -contains 'Mermaid') { & $write "$base.mmd" $mermaid }
        if ($Format -contains 'Markdown') {
            $open = @($result.Findings | Where-Object Status -EQ 'Open')
            $md = [System.Text.StringBuilder]::new()
            $null = $md.AppendLine("# $($model.Name) - architecture").AppendLine()
            $null = $md.AppendLine("Regions: $(@($model.Regions) -join ', ') · Landing zone: $(if ($model.LandingZone) { $model.LandingZone } else { 'none' }) · Catalog $($model.CatalogVersion) · Generated $([datetime]::UtcNow.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture))").AppendLine()
            $null = $md.AppendLine('```mermaid').AppendLine($mermaid).AppendLine('```').AppendLine()
            $null = $md.AppendLine('Colours: green - no open finding; amber - medium or low; red - blocking or high. WAF badges: R reliability, S security, C cost, O operations, P performance (!! blocking or high, ! other).').AppendLine()
            $null = $md.AppendLine('## Patterns').AppendLine()
            foreach ($id in @($model.Patterns)) { $p = @($catalog.Patterns | Where-Object Id -EQ $id)[0]; if ($p) { $null = $md.AppendLine("- [$($p.Name)]($($p.Link)) - $($p.Problem)") } }
            $null = $md.AppendLine().AppendLine("## Open findings ($($open.Count))").AppendLine()
            if ($open.Count) {
                $null = $md.AppendLine('| Severity | Finding | Component | Pillar | Azure Policy | PSRule | What to do |').AppendLine('| --- | --- | --- | --- | --- | --- | --- |')
                foreach ($f in $open) { $null = $md.AppendLine("| $($f.Severity) | $($f.Finding) | $($f.Component) | $($f.Pillar) | $($f.Policy) | $($f.PSRule) | $($f.Remediation -replace '\|', '/') |") }
            }
            else { $null = $md.AppendLine('None: the design passes every rule.') }
            if (@($model.Open).Count) {
                $null = $md.AppendLine().AppendLine('## Open decisions').AppendLine()
                foreach ($id in @($model.Open)) { $q = @($catalog.Questions | Where-Object Id -EQ $id)[0]; $null = $md.AppendLine("- **$id** $(if ($q) { $q.Text }) - default used: $($model.Answers[$id])") }
            }
            & $write "$base.md" $md.ToString()
        }
        if ($Format -contains 'DrawIo') { & $write "$base.drawio" (ConvertTo-AACArchitectureDrawIo -Design $model -Finding $result.Findings -Pillar $result.Pillars -Catalog $catalog -Layer $Layer -PSRuleBaseline $PSRuleBaseline) }
    }
}
