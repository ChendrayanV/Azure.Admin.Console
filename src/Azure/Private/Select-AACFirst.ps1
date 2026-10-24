function Select-AACFirst {
    <#
    .SYNOPSIS
        The first -Count items of the pipeline, passed on untouched.
    .DESCRIPTION
        Select-Object -First adds a 'Selected.System.Management.Automation.
        PSCustomObject' type name to the very objects it passes on (not a
        copy), so an AAC.* object that has been through it - in a view, say -
        loses its format view when the command returns it afterwards. This
        passes the objects on as they are.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int] $Count,

        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        $InputObject
    )

    begin { $taken = 0 }
    process {
        if ($taken -lt $Count) {
            $taken++
            $InputObject
        }
    }
}
