<#
    Unit tests for the console plumbing every command shares: the live
    progress display (Invoke-AACProgress) as it runs in an interactive
    terminal - where the command's work runs inside Spectre.Console's live
    display - and the paging of the view (Invoke-AACPagedOutput).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - the live progress display' {
    BeforeAll {
        # An interactive console writing to a buffer: the live display runs as at a terminal.
        $script:live = {
            param([scriptblock] $Body)
            $real = [Spectre.Console.AnsiConsole]::Console
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new([System.IO.StringWriter]::new())
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            $settings.Interactive = [Spectre.Console.InteractionSupport]::Yes
            # Spectre's enrichers turn interactivity off on CI servers (GitHub Actions...): not here.
            $settings.Enrichment.UseDefaultEnrichers = $false
            $console = [Spectre.Console.AnsiConsole]::Create($settings)
            $console.Profile.Capabilities.Interactive = $true
            try { [Spectre.Console.AnsiConsole]::Console = $console; & $Body }
            finally { [Spectre.Console.AnsiConsole]::Console = $real }
        }
    }

    It 'hands the work''s warnings back after the display, so -WarningVariable and -WarningAction see them' {
        $result = & $script:live {
            InModuleScope 'Azure.Admin.Console' {
                [Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive | Should -BeTrue -Because 'this test is about the live display'
                $value = Invoke-AACProgress -ScriptBlock { Write-Warning 'No group named ''grp-typo'' was found'; @{ Answer = 42 } } -WarningVariable seen -WarningAction SilentlyContinue
                @{ Value = $value; Seen = @($seen) }
            }
        }
        "$($result.Seen)" | Should -Be "No group named 'grp-typo' was found"
        $result.Value | Should -BeOfType [hashtable] -Because 'one object returned stays one object'
        $result.Value.Answer | Should -Be 42
    }

    It 'still throws the work''s error, after the warnings' {
        {
            & $script:live { InModuleScope 'Azure.Admin.Console' { Invoke-AACProgress -ScriptBlock { throw 'it broke' } -WarningAction SilentlyContinue } }
        } | Should -Throw '*it broke*'
    }
}

Describe 'Azure Admin Console - paging the view' {
    It 'writes straight through - no key press - when Spectre draws to something other than the terminal' {
        $buffer = [System.IO.StringWriter]::new()
        $real = [Spectre.Console.AnsiConsole]::Console
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        try {
            [Spectre.Console.AnsiConsole]::Console = [Spectre.Console.AnsiConsole]::Create($settings)
            InModuleScope 'Azure.Admin.Console' {
                Invoke-AACPagedOutput -ScriptBlock { 1..80 | ForEach-Object { Write-AACMarkup "line $_" } } -ReadKey { throw 'no key press expected' }
            }
        }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        $buffer.ToString() | Should -Match 'line 80'
    }
}
