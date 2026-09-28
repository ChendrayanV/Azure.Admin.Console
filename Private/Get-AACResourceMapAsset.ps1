function Get-AACResourceMapAsset {
    <#
    .SYNOPSIS
        Returns what the resource map's HTML page embeds: the ELK layout
        library, the Azure icons and the page template - each checked first.
    .DESCRIPTION
        lib\elk\elk.bundled.js (elkjs 0.12.0) and lib\azure-icons\azure-icons.json
        are refused if their SHA-256 doesn't match the one they were released
        with (see each folder's SOURCES.md): the page runs the one and shows
        the other. Read once per session.

        Returns a hashtable: Elk (the script's text), Icons (the parsed icon
        set: types and icons) and Template (Private\ResourceMap.html).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:AACResourceMapAsset) {
        return $script:AACResourceMapAsset
    }

    $expected = @{
        'lib/elk/elk.bundled.js'            = '1222E44F953CE7746AF23801E723708F8E6F436B8B377A6A5FC7552F34A307B3'
        'lib/azure-icons/azure-icons.json'  = '85B824FD42006B89F35F6D832F763702F51393A94AC7A6B545EDA7798AEF91C1'
    }
    $text = @{}
    foreach ($relative in $expected.Keys) {
        $path = Join-Path -Path $script:AACModuleRoot -ChildPath $relative
        if (-not (Test-Path -LiteralPath $path)) {
            throw "The resource map needs $relative, which is missing. Reinstall the module."
        }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ne $expected[$relative]) {
            throw "The resource map refused ${relative}: its SHA-256 doesn't match the file this module was released with. Reinstall the module."
        }
        $text[$relative] = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    }

    $script:AACResourceMapAsset = @{
        Elk      = $text['lib/elk/elk.bundled.js']
        Icons    = ConvertFrom-Json -InputObject $text['lib/azure-icons/azure-icons.json'] -AsHashtable
        Template = [System.IO.File]::ReadAllText((Join-Path -Path $script:AACModuleRoot -ChildPath 'Private/ResourceMap.html'), [System.Text.Encoding]::UTF8)
    }
    $script:AACResourceMapAsset
}
