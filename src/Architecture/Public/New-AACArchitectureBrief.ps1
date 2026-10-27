function New-AACArchitectureBrief {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Step 1: captures a workload's requirements by asking about 20 probe
        questions, and returns the brief.
    .DESCRIPTION
        At the prompt each question is asked in turn: Enter keeps the
        default, ? means "don't know". Or give answers with -Answer or
        -AnswerPath. Unanswered questions take their default (assumptions);
        "don't know" answers stay open decisions. Offline.
    .PARAMETER Name
        The workload's name.
    .PARAMETER Answer
        Answers by question ID: @{ 'BUS-01' = 'Web or API'; 'REL-01' = 30 }.
    .PARAMETER AnswerPath
        A .json or .psd1 file of answers, or a saved brief.
    .PARAMETER Level
        Guided (default) explains each question; Expert doesn't.
    .PARAMETER NonInteractive
        Ask nothing; unanswered questions take their default.
    .PARAMETER OutPath
        Save the brief as JSON.
    .PARAMETER NoDisplay
        Return the brief without the summary.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        $brief = New-AACArchitectureBrief -Name 'orders-api' -OutPath .\orders-api.brief.json
        Asks the questions and saves the answers.
    .EXAMPLE
        $brief = New-AACArchitectureBrief -Name 'orders-api' -Answer @{ 'BUS-01' = 'Web or API'; 'SEC-01' = 'Confidential' } -NonInteractive
        Two answers given, the rest defaulted - no questions asked.
    .OUTPUTS
        AAC.ArchitectureBrief
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('AAC.ArchitectureBrief')]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $Name = 'workload',

        [System.Collections.IDictionary] $Answer,

        [string] $AnswerPath,

        [ValidateSet('Guided', 'Expert')]
        [string] $Level = 'Guided',

        [switch] $NonInteractive,

        [string] $OutPath,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $catalog = Get-AACArchitectureCatalog
    $given = [ordered]@{}
    if ($AnswerPath) {
        $file = Resolve-AACArchitectureInput -InputObject (& $resolve $AnswerPath) -Kind Brief
        foreach ($key in $file.Answers.Keys) { $given[$key] = $file.Answers[$key] }
        if ($Name -eq 'workload' -and $file.Name -and $file.Name -ne 'workload') { $Name = $file.Name }
    }
    if ($Answer) { foreach ($key in $Answer.Keys) { $given[$key] = $Answer[$key] } }

    # Ask at the prompt only when someone is there to answer.
    $canAsk = -not $NonInteractive -and $interactive -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    $ask = if ($canAsk) {
        Write-AACRule -Title 'Azure Admin Console :: Architecture brief' -Color 'mediumpurple2'
        Write-AACMarkup "[grey58]Enter keeps the default in brackets; ? means you don't know (the default is used and the question stays open).[/]"
        { param($Question, $Default) Read-AACArchitectureAnswer -Question $Question -Default $Default -Guided:($Level -eq 'Guided') }
    }
    $brief = ConvertTo-AACArchitectureBrief -Catalog $catalog -Answer $given -Ask $ask -Name $Name
    if ($interactive -and -not $canAsk) { Write-AACRule -Title 'Azure Admin Console :: Architecture brief' -Color 'mediumpurple2' }
    $object = [pscustomobject][ordered]@{
        PSTypeName = 'AAC.ArchitectureBrief'; Name = $brief.Name; CatalogVersion = $brief.CatalogVersion; Created = $brief.Created
        Answers = $brief.Answers; Open = $brief.Open; Assumed = $brief.Assumed; Rows = $brief.Rows
    }
    if ($OutPath -and $PSCmdlet.ShouldProcess((& $resolve $OutPath), 'Save the architecture brief')) {
        $path = & $resolve $OutPath
        $folder = Split-Path -Path $path -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        [pscustomobject][ordered]@{ Name = $brief.Name; CatalogVersion = $brief.CatalogVersion; Created = $brief.Created; Answers = $brief.Answers; Open = $brief.Open; Assumed = $brief.Assumed } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
    }

    $sourceTones = @{ Answered = 'good'; 'Default (assumed)' = 'neutral'; 'Unknown - default used' = 'warn' }
    $report = @{
        Facts    = [ordered]@{ Workload = $brief.Name; Catalog = $brief.CatalogVersion; Saved = $(if ($OutPath) { & $resolve $OutPath } else { 'not saved (-OutPath)' }) }
        Status   = $(if ($brief.Open.Count) { 'Warning' } else { 'Success' })
        Headline = "$(@($brief.Rows | Where-Object Source -EQ 'Answered').Count) answered, $($brief.Assumed.Count) assumed, $($brief.Open.Count) open decision(s)"
        Tiles    = @(
            @{ Value = '{0:N0}' -f @($brief.Rows).Count; Label = 'questions'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $brief.Assumed.Count; Label = 'assumed (defaults)'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $brief.Open.Count; Label = 'open decisions'; Tone = $(if ($brief.Open.Count) { 'warn' } else { 'good' }) }
        )
        Tables   = @(@{ Id = 'answers'; Title = 'Answers'; Rows = @($brief.Rows); Noun = 'answers'; NoConsole = $true
                Columns = @(
                    @{ Key = 'Id'; Label = 'ID'; Type = 'mono'; Console = $true }
                    @{ Key = 'Question'; Label = 'Question'; Type = 'wide'; Console = $true }
                    @{ Key = 'Answer'; Label = 'Answer'; Console = $true }
                    @{ Key = 'Source'; Label = 'Source'; Type = 'badge'; Tones = $sourceTones; Console = $true }
                    @{ Key = 'Pillar'; Label = 'Pillar' }
                ) })
        Hint     = 'Next: Get-AACArchitecturePattern -Brief <this> ranks the cloud design patterns; New-AACArchitectureDesign builds the design.'
    }
    Invoke-AACReportOutput -Report $report -Title 'Architecture brief' -ShowView:$interactive -NoPaging:$NoPaging -Object @($object) -ReturnObject
}
