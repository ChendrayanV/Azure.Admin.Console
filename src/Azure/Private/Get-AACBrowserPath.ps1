function Get-AACBrowserPath {
    <#
    .SYNOPSIS
        The path of Microsoft Edge or Google Chrome (or Chromium), for
        printing a page to PDF headless - or nothing when neither is there.
        A function of its own so tests can replace it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $candidates = @(
        if ($IsWindows) {
            foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA) | Where-Object { $_ }) {
                Join-Path -Path $root -ChildPath 'Microsoft\Edge\Application\msedge.exe'
                Join-Path -Path $root -ChildPath 'Google\Chrome\Application\chrome.exe'
            }
        }
        elseif ($IsMacOS) {
            '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'
            '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
            '/Applications/Chromium.app/Contents/MacOS/Chromium'
        }
        else {
            foreach ($name in 'microsoft-edge', 'microsoft-edge-stable', 'google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser') {
                $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($command) { $command.Source }
            }
        }
    )
    $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}
