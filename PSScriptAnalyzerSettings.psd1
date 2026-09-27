# PSScriptAnalyzer settings for Azure.Admin.Console. build.ps1 fails on any
# error or warning left after these; each exclusion says why it doesn't fit.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The module requires PowerShell 7.2+, which reads UTF-8 without a
        # BOM; the BOM only matters to Windows PowerShell 5.1.
        'PSUseBOMForUnicodeEncodedFile'
        # Parameters used inside nested script blocks (the progress and
        # export callbacks every command passes) are reported as unused.
        'PSReviewUnusedParameter'
        # Flags Spectre.Console's AnsiConsole.Write/WriteLine - the module's
        # UI layer by design - as Console.Write.
        'PSAvoidUsingWriteHost'
        # Public commands return arrays of typed AAC.* objects, which the
        # pipeline unrolls; the rule sees only the array and wants
        # [object[]] declared instead of the AAC.* type names.
        'PSUseOutputTypeCorrectly'
    )
}
