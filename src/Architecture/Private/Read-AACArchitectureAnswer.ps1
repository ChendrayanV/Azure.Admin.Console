function Read-AACArchitectureAnswer {
    <#
    .SYNOPSIS
        Asks one probe question at the console and returns the answer.
    .DESCRIPTION
        Shows the question (with its help when -Guided), the choices
        numbered, and the default; reads the reply with Read-Host. Enter
        keeps the default, ? (or 'unknown') records "don't know" - the
        default is used and the question becomes an open decision. A
        MultiChoice question takes numbers separated by commas.
        Returns @{ Value; Unknown }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Question,

        $Default,

        [switch] $Guided
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    Write-AACMarkup "[deepskyblue1]$(& $escape $Question.Id)[/] [white]$(& $escape $Question.Text)[/] [grey50]($(& $escape $Question.Pillar))[/]"
    if ($Guided -and $Question.Help) { Write-AACMarkup "  [grey62]$(& $escape $Question.Help)[/]" }
    $choices = @(if ($Question.Contains('Choices')) { $Question.Choices })
    for ($i = 0; $i -lt $choices.Count; $i++) { Write-AACMarkup "  [grey70]$($i + 1).[/] $(& $escape $choices[$i])" }
    $shown = if ($Default -is [array]) { $Default -join ', ' } else { [string]$Default }

    while ($true) {
        $reply = ([string](Read-Host -Prompt "  Answer$(if ($shown) { " [$shown]" }) (? if you don't know)")).Trim()
        if (-not $reply) { return @{ Value = $Default; Unknown = $false } }
        if ($reply -in '?', 'unknown', "don't know") { return @{ Value = $Default; Unknown = $true } }
        switch ($Question.Type) {
            'Number' {
                $n = 0.0
                if ([double]::TryParse($reply, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$n)) { return @{ Value = $n; Unknown = $false } }
                Write-AACMarkup '  [orange1]A number, please.[/]'
            }
            'Text' { return @{ Value = $reply; Unknown = $false } }
            default {
                $picked = @(foreach ($part in ($reply -split '\s*,\s*')) {
                        if ($part -match '^\d+$' -and [int]$part -ge 1 -and [int]$part -le $choices.Count) { $choices[[int]$part - 1] }
                        else { @($choices | Where-Object { $_ -eq $part }) | Select-Object -First 1 }
                    })
                if ($picked.Count -and ($Question.Type -eq 'MultiChoice' -or $picked.Count -eq 1) -and -not @($picked | Where-Object { -not $_ }).Count) {
                    return @{ Value = $(if ($Question.Type -eq 'MultiChoice') { , @($picked) } else { $picked[0] }); Unknown = $false }
                }
                Write-AACMarkup "  [orange1]Pick $(if ($Question.Type -eq 'MultiChoice') { 'one or more numbers, separated by commas' } else { 'one number' }) from 1 to $($choices.Count).[/]"
            }
        }
    }
}
