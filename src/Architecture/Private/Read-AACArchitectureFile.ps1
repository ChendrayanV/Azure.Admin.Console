function Read-AACArchitectureFile {
    <#
    .SYNOPSIS
        Reads an Architecture input file - answers, a brief, a design or
        guardrails - from .json or .psd1 into hashtables.
    .DESCRIPTION
        JSON is read with -AsHashtable, so a file written by -OutPath reads
        back as the same shape; a .psd1 is a PowerShell data file (no code).
        -What names the file in errors ("the answers file").
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [string] $What = 'the file'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Azure Admin Console can't find $What at $Path. Give the path of a .json or .psd1 file."
    }
    try {
        $data = if ($Path -match '\.psd1$') { Import-PowerShellDataFile -LiteralPath $Path } else { ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw) -AsHashtable }
    }
    catch {
        throw "Azure Admin Console can't read $What at ${Path}: $($_.Exception.Message) Check it is valid $(if ($Path -match '\.psd1$') { 'PowerShell data (.psd1)' } else { 'JSON' })."
    }
    if ($data -isnot [System.Collections.IDictionary]) { throw "Azure Admin Console can't read $What at ${Path}: it should hold one object (a hashtable), not a list." }
    $data
}
