function Write-AACWafHistory {
    <#
    .SYNOPSIS
        Adds this run of a Well-Architected assessment to its history CSV and
        returns how the overall score moved since the last run.
    .DESCRIPTION
        One line per run: Date (UTC, ISO 8601), Scope, Overall, a column per
        pillar, Failed and High. A pillar not assessed is left empty. Returns
        @{ Previous (the last run's date, or $null); Change (overall now less
        then); Path }. -Path must be a full path; its folder is created.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [hashtable] $State
    )

    $result = $State.Result
    $previous = $null
    $change = $null
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $last = @(Import-Csv -LiteralPath $Path) | Select-Object -Last 1
        if ($last -and $last.PSObject.Properties['Overall'] -and $last.Overall -and $null -ne $result.Overall) {
            $previous = $last.Date
            $change = [Math]::Round([double]$result.Overall - [double]::Parse($last.Overall, [cultureinfo]::InvariantCulture), 1)
        }
    }
    $row = [ordered]@{ Date = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture); Scope = [string]$State.Scope.Label; Overall = $(if ($null -ne $result.Overall) { ([double]$result.Overall).ToString([cultureinfo]::InvariantCulture) } else { '' }) }
    foreach ($pillar in 'Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency') {
        $score = @($result.Pillars | Where-Object Pillar -EQ $pillar | ForEach-Object { $_.Score })
        $row[$pillar] = if ($score.Count -and $null -ne $score[0]) { ([double]$score[0]).ToString([cultureinfo]::InvariantCulture) } else { '' }
    }
    $row['Failed'] = $result.Stats.Failed
    $row['High'] = $result.Stats.High
    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    [pscustomobject]$row | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8 -Append
    @{ Previous = $previous; Change = $change; Path = $Path }
}
