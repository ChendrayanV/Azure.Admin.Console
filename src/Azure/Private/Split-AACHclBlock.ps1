function Split-AACHclBlock {
    <#
    .SYNOPSIS
        Splits Terraform (HCL) text into its top-level blocks - terraform,
        provider, resource, import... - each with its type, its labels and
        its text, so exported configurations can be laid out in files and
        merged.
    .DESCRIPTION
        Reads character by character, so braces inside quoted strings,
        heredocs (<<EOT, <<-EOT) and comments (#, //, /* */) don't count.
        Returns, in order, @{ Type; Labels (the quoted labels: 'azurerm',
        or 'azurerm_resource_group', 'res-1'); Text (the block, from its
        type to its closing brace) }. Anything at the top level that isn't
        a block - a comment, a blank line - is left out.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()]
        [string] $Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $length = $Text.Length
    $i = 0
    # The index just past a string, heredoc or comment starting at $at - or $at when there is none.
    $skip = {
        param([int] $At)
        $c = $Text[$At]
        if ($c -eq '"') {
            $j = $At + 1
            while ($j -lt $length -and $Text[$j] -ne '"') { if ($Text[$j] -eq '\') { $j++ }; $j++ }
            return [Math]::Min($j + 1, $length)
        }
        if ($c -eq '#' -or ($c -eq '/' -and $At + 1 -lt $length -and $Text[$At + 1] -eq '/')) {
            $j = $Text.IndexOf("`n", $At)
            return $(if ($j -lt 0) { $length } else { $j + 1 })
        }
        if ($c -eq '/' -and $At + 1 -lt $length -and $Text[$At + 1] -eq '*') {
            $j = $Text.IndexOf('*/', $At + 2)
            return $(if ($j -lt 0) { $length } else { $j + 2 })
        }
        if ($c -eq '<' -and $At + 1 -lt $length -and $Text[$At + 1] -eq '<') {
            $heredoc = [regex]::Match($Text.Substring($At), '^<<-?([A-Za-z_][A-Za-z0-9_]*)[ \t]*\r?\n')
            if ($heredoc.Success) {
                $marker = [regex]::Match($Text.Substring($At + $heredoc.Length), "(?m)^[ \t]*$([regex]::Escape($heredoc.Groups[1].Value))[ \t]*$")
                return $(if ($marker.Success) { $At + $heredoc.Length + $marker.Index + $marker.Length } else { $length })
            }
        }
        $At
    }

    while ($i -lt $length) {
        $c = $Text[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        $after = & $skip $i
        if ($after -ne $i) { $i = $after; continue }

        # A block: its header runs to the first brace outside a string.
        $start = $i
        while ($i -lt $length -and $Text[$i] -ne '{' -and $Text[$i] -ne "`n") {
            $after = & $skip $i
            $i = if ($after -ne $i) { $after } else { $i + 1 }
        }
        if ($i -ge $length -or $Text[$i] -ne '{') { continue }
        $header = $Text.Substring($start, $i - $start).Trim()
        $depth = 0
        while ($i -lt $length) {
            $after = & $skip $i
            if ($after -ne $i) { $i = $after; continue }
            if ($Text[$i] -eq '{') { $depth++ }
            elseif ($Text[$i] -eq '}') { $depth--; if ($depth -eq 0) { $i++; break } }
            $i++
        }
        $type = ($header -split '\s+')[0]
        @{
            Type   = $type
            Labels = @([regex]::Matches($header, '"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
            Text   = $Text.Substring($start, $i - $start)
        }
    }
}
