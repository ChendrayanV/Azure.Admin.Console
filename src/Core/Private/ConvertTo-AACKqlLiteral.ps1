function ConvertTo-AACKqlLiteral {
    <#
    .SYNOPSIS
        A value as a Kusto (Resource Graph, Log Analytics) string literal:
        single-quoted, with backslashes and single quotes escaped.
    .DESCRIPTION
        Kusto reads a backslash in a single-quoted string as an escape, so
        'C:\temp' or a value ending in \ would break the query - or change
        it - unless the backslash is doubled; a single quote becomes \'. Every
        query builder quotes through here, so they all escape alike.
        -Lower lower-cases the value first, for comparisons with tolower(...).
    .EXAMPLE
        ConvertTo-AACKqlLiteral -Text "rg-o'brien"   # 'rg-o\'brien'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Text,

        [switch] $Lower
    )

    $value = if ($Lower) { $Text.ToLowerInvariant() } else { $Text }
    "'" + ($value -replace '\\', '\\' -replace "'", "\'") + "'"
}
