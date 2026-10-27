function Test-AACArchitectureDesign {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Step 4: checks a design against the Well-Architected Framework,
        inherited Azure Policy, your guardrails and PSRule for Azure, and
        says what to fix.
    .DESCRIPTION
        Each finding has a severity, pillar, the matching policy and PSRule
        rule, and the fix. Blocking means Azure policy or your guardrails
        would refuse the deployment. A guardrails file looks like
        @{ AllowedRegions = @('westeurope'); DenyPublicEndpoint = $true;
        DeniedSkus = @('Basic*'); RequiredTags = @('Owner') }. Offline.
    .PARAMETER Design
        The design, or the path of a saved one.
    .PARAMETER GuardrailPath
        Your guardrails, a .psd1 or .json file.
    .PARAMETER Guardrail
        The guardrails as a hashtable (joins -GuardrailPath).
    .PARAMETER Accept
        Accepted risks: a rule ID (SEC-TLS-01) or rule:component (SEC-TLS-01:data).
    .PARAMETER FailOnGap
        Fail (throw) while a Blocking or High finding is open - for pipelines.
    .PARAMETER CsvPath
        Write the findings to this CSV file.
    .PARAMETER HtmlPath
        Write a tabbed HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the findings.
    .PARAMETER NoDisplay
        Return the findings without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Test-AACArchitectureDesign -Design $design
        The findings and the score per pillar.
    .EXAMPLE
        Test-AACArchitectureDesign -Design $design -GuardrailPath .\guardrails.psd1 -HtmlPath .\validation.html
        With your guardrails, as a tabbed HTML report.
    .EXAMPLE
        Test-AACArchitectureDesign -Design .\orders-api.design.json -Accept 'COST-RI-01' -NoDisplay -FailOnGap
        In a pipeline: fails the stage while a Blocking or High finding is open.
    .OUTPUTS
        AAC.ArchitectureFinding (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ArchitectureFinding')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNull()]
        [object] $Design,

        [string] $GuardrailPath,

        [System.Collections.IDictionary] $Guardrail = @{},

        [string[]] $Accept = @(),

        [switch] $FailOnGap,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Architecture validation',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    process {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }
        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Architecture validation' -Color 'mediumpurple2' }
        $catalog = Get-AACArchitectureCatalog
        $model = Resolve-AACArchitectureInput -InputObject $(if ($Design -is [string]) { & $resolve $Design } else { $Design }) -Kind Design
        $guard = @{}
        if ($GuardrailPath) { $file = Read-AACArchitectureFile -Path (& $resolve $GuardrailPath) -What 'the guardrails'; foreach ($k in $file.Keys) { $guard[$k] = $file[$k] } }
        foreach ($k in $Guardrail.Keys) { $guard[$k] = $Guardrail[$k] }
        $result = Invoke-AACArchitectureRule -Design $model -Catalog $catalog -Guardrail $guard -Accept $Accept
        $findings = @($result.Findings)
        $open = @($findings | Where-Object Status -EQ 'Open')
        $blocking = @($open | Where-Object Severity -EQ 'Blocking')
        $high = @($open | Where-Object Severity -EQ 'High')
        $scored = @($result.Pillars | Where-Object { $null -ne $_.Score })
        $overall = if ($scored.Count) { [Math]::Round((@($scored | ForEach-Object Score) | Measure-Object -Average).Average) } else { $null }

        $severityTones = @{ Blocking = 'bad'; High = 'bad'; Medium = 'warn'; Low = 'info' }
        $components = @($model.Nodes | ForEach-Object { $n = $_; [pscustomobject][ordered]@{ Zone = $n.Zone; Component = $n.Name; Kind = $n.Kind; Sku = $n.Sku; Region = $n.Region; ZoneRedundant = $n.ZoneRedundant; PrivateEndpoint = $n.PrivateEndpoint; Identity = $n.Identity; Open = @($open | Where-Object NodeId -EQ $n.Id).Count } })
        $openRows = @($model.Open | ForEach-Object { $id = $_; $q = @($catalog.Questions | Where-Object Id -EQ $id)[0]; [pscustomobject][ordered]@{ Id = $id; Question = $(if ($q) { $q.Text } else { '' }); Answer = [string]$model.Answers[$id]; Status = 'Open - default used' } })
        $policyRows = @($model.Policies | ForEach-Object { [pscustomobject][ordered]@{ Assignment = [string]$_['Name']; Scope = [string]$_['Scope']; Enforcement = [string]$_['Enforcement'] } })
        $report = @{
            Subtitle = "$($model.Name) - $(@($model.Regions) -join ', ')$(if ($model.LandingZone) { " - landing zone $($model.LandingZone)" })"
            Facts    = [ordered]@{ Design = $model.Name; Catalog = $catalog.Version; 'Designed with catalog' = $model.CatalogVersion; Guardrails = $(if ($guard.Count) { (@($guard.Keys) -join ', ') } else { 'none' }); Checks = $result.Checks }
            Status   = $(if ($blocking.Count -or $high.Count) { 'Failed' } elseif ($open.Count) { 'Warning' } else { 'Success' })
            Headline = "$($blocking.Count) blocking, $($high.Count) high and $(($open.Count - $blocking.Count - $high.Count)) other open finding(s) in $($result.Checks) checks; $(@($findings | Where-Object Status -EQ 'Accepted').Count) accepted; overall $(if ($null -ne $overall) { "$overall/100" } else { 'not scored' })"
            Notices  = @(@($model.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } }) + @($result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } }) + @(if ($model.CatalogVersion -and $model.CatalogVersion -ne $catalog.Version) { @{ Status = 'Info'; Text = "The design was made with catalog $($model.CatalogVersion); it is checked with $($catalog.Version) - build it again with New-AACArchitectureDesign to pick up the changes." } }))
            Tiles    = @(
                @{ Value = $(if ($null -ne $overall) { "$overall/100" } else { '-' }); Label = 'Well-Architected (design)'; Tone = $(if ($overall -ge 80) { 'good' } elseif ($overall -ge 60) { 'warn' } else { 'bad' }); Table = 'pillars' }
                @{ Value = '{0:N0}' -f $blocking.Count; Label = 'blocking (policy, guardrails)'; Tone = $(if ($blocking.Count) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'Blocking' } }
                @{ Value = '{0:N0}' -f $high.Count; Label = 'high'; Tone = $(if ($high.Count) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
                @{ Value = '{0:N0}' -f @($model.Open).Count; Label = 'open decisions'; Tone = $(if (@($model.Open).Count) { 'warn' } else { 'good' }); Table = 'open' }
            )
            Charts   = @(@{ Title = 'Score by pillar'; Items = @($scored | ForEach-Object { @{ Label = $_.Pillar; Value = $_.Score; Display = "$($_.Score)/100"; Tone = $(if ($_.Score -ge 80) { 'good' } elseif ($_.Score -ge 60) { 'warn' } else { 'bad' }) } }); Table = 'findings'; Column = 'Pillar'; Console = $true })
            Tabs     = @(
                @{ Name = 'Findings'; Badge = $open.Count; Tone = $(if ($blocking.Count -or $high.Count) { 'bad' } else { 'warn' }); Note = 'What to fix before deploying, worst first - each with its pillar, the Azure Policy and PSRule for Azure rule it corresponds to, and what to do.' }
                @{ Name = 'Pillars'; Badge = $null; Tone = 'info'; Note = 'The design''s score per Well-Architected pillar: the share of checks that pass, weighted by severity.' }
                @{ Name = 'Components'; Badge = $components.Count; Tone = 'neutral'; Note = 'Every component of the design and its open findings.' }
                @{ Name = 'Inherited policy'; Badge = $policyRows.Count; Tone = 'info'; Note = 'The policy assignments in force on the landing zone and above, read when the design was made.' }
                @{ Name = 'Open decisions'; Badge = $openRows.Count; Tone = 'warn'; Note = 'Questions answered "don''t know": the default was used - decide them before the design is final.' }
            )
            Tables   = @(
                @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = $findings; Noun = 'findings'; ConsoleLimit = 25; GroupBy = @('Severity', 'Pillar', 'Status')
                    Hover = @('Remediation', 'Policy', 'PSRule', 'Advisor'); HoverTitle = 'Finding'
                    Empty = 'Nothing to fix: the design passes every rule.'; EmptyStatus = 'Success'
                    Columns = @(
                        @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Open = 'warn'; Accepted = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Finding'; Label = 'Finding'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Component'; Label = 'Component'; Console = $true; Pdf = $true }
                        @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Policy'; Label = 'Azure Policy'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'PSRule'; Label = 'PSRule for Azure'; Type = 'mono' }
                        @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'Rule'; Label = 'Rule'; Type = 'mono' }
                        @{ Key = 'Link'; Label = 'Learn more'; Type = 'link'; Text = 'Docs' }
                    ) }
                @{ Id = 'pillars'; Title = 'Pillars'; Section = 'Pillars'; Rows = @($result.Pillars); Noun = 'pillars'
                    Columns = @(@{ Key = 'Pillar'; Label = 'Pillar'; Console = $true; Pdf = $true }, @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Console = $true; Pdf = $true }, @{ Key = 'Checks'; Label = 'Checks'; Type = 'number'; Pdf = $true }, @{ Key = 'Open'; Label = 'Open'; Type = 'number'; Console = $true; Pdf = $true }, @{ Key = 'Blocking'; Label = 'Blocking'; Type = 'number'; Pdf = $true }, @{ Key = 'High'; Label = 'High'; Type = 'number'; Pdf = $true }) }
                @{ Id = 'components'; Title = 'Components'; Section = 'Components'; Rows = $components; Noun = 'components'; NoConsole = $true
                    Columns = @(@{ Key = 'Zone'; Label = 'Zone'; Facet = $true; Pdf = $true }, @{ Key = 'Component'; Label = 'Component'; Pdf = $true }, @{ Key = 'Sku'; Label = 'SKU'; Pdf = $true }, @{ Key = 'Region'; Label = 'Region'; Facet = $true; Pdf = $true }, @{ Key = 'ZoneRedundant'; Label = 'Zone-redundant'; Pdf = $true }, @{ Key = 'PrivateEndpoint'; Label = 'Private endpoint'; Pdf = $true }, @{ Key = 'Identity'; Label = 'Identity' }, @{ Key = 'Open'; Label = 'Open findings'; Type = 'number'; Pdf = $true }) }
                @{ Id = 'policy'; Title = 'Inherited policy'; Section = 'Inherited policy'; Rows = $policyRows; Noun = 'assignments'; NoConsole = $true
                    Columns = @(@{ Key = 'Assignment'; Label = 'Assignment'; Pdf = $true }, @{ Key = 'Scope'; Label = 'Scope'; Pdf = $true }, @{ Key = 'Enforcement'; Label = 'Enforcement'; Type = 'badge'; Tones = @{ Enforced = 'good'; 'Not enforced' = 'warn' }; Pdf = $true }) }
                @{ Id = 'open'; Title = 'Open decisions'; Section = 'Open decisions'; Rows = $openRows; Noun = 'decisions'; ConsoleLimit = 20
                    Columns = @(@{ Key = 'Id'; Label = 'ID'; Type = 'mono'; Console = $true; Pdf = $true }, @{ Key = 'Question'; Label = 'Question'; Type = 'wide'; Console = $true; Pdf = $true }, @{ Key = 'Answer'; Label = 'Default used'; Console = $true; Pdf = $true }) }
            )
            Hint     = '-GuardrailPath adds your guardrails; -Accept records an accepted risk; -FailOnGap fails a pipeline; New-AACArchitectureDiagram draws the findings on the design.'
        }
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $findings -Noun 'finding' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $findings -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
        if ($FailOnGap -and ($blocking.Count -or $high.Count)) {
            $problem = [System.InvalidOperationException]::new("Azure Admin Console: the design has $($blocking.Count) blocking and $($high.Count) high finding(s) open: $((@($blocking) + @($high) | Select-Object -First 5 | ForEach-Object { "$($_.Rule) $($_.Finding) ($($_.Component))" }) -join ' | ')")
            $problem.Data['AACHint'] = 'Fix the design (New-AACArchitectureDesign -Override, or different answers), or accept the risk with -Accept and record it with Export-AACArchitectureDecision.'
            throw $problem
        }
    }
}
