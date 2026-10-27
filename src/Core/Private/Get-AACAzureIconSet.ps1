function Get-AACAzureIconSet {
    <#
    .SYNOPSIS
        Returns the Azure icon set (lib\azure-icons\azure-icons.json), checked
        first: types (ARM type to icon key) and icons (key to category, label
        and SVG).
    .DESCRIPTION
        In Core because more than one area draws Azure icons: the resource
        map and diagrams (Azure) and the architecture diagrams (Architecture).
        The file is refused if its SHA-256 doesn't match the one it was
        released with (see the folder's SOURCES.md). Read once per session.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($script:AACAzureIconSet) {
        return $script:AACAzureIconSet
    }

    $relative = 'lib/azure-icons/azure-icons.json'
    $path = Join-Path -Path $script:AACModuleRoot -ChildPath $relative
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Azure Admin Console needs $relative, which is missing. Reinstall the module."
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne '85B824FD42006B89F35F6D832F763702F51393A94AC7A6B545EDA7798AEF91C1') {
        throw "Azure Admin Console refused ${relative}: its SHA-256 doesn't match the file this module was released with. Reinstall the module."
    }
    $script:AACAzureIconSet = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)) -AsHashtable
    $script:AACAzureIconSet
}
