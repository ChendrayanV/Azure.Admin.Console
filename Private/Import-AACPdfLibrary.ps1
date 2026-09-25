function Import-AACPdfLibrary {
    <#
    .SYNOPSIS
        Loads the vendored PDFsharp + MigraDoc assemblies from .\lib\pdf, after
        checking every file against a pinned SHA-256 hash.
    .DESCRIPTION
        Called only when a PDF is exported, so importing the module stays fast
        and never touches these DLLs.

        Every DLL is hashed before any of them is loaded. If one is missing or
        its hash differs from the pin below, nothing is loaded and the export
        stops with an error naming the file - a swapped or tampered assembly
        is never executed. Where the files came from and how they were
        verified is recorded in lib\pdf\SOURCES.md.

        The assemblies are the net8.0 builds, so PowerShell 7.4 or later
        (.NET 8+) is required. Fonts come from the Windows Fonts folder (Segoe
        UI, Consolas; Arial if those are missing), so export is Windows-only.
    #>
    [CmdletBinding()]
    param()

    if ($script:AACPdfLibraryLoaded) {
        return
    }

    if (-not $IsWindows) {
        throw 'PDF export uses the fonts installed with Windows and is only supported on Windows.'
    }
    if ($PSVersionTable.PSVersion -lt [version]'7.4') {
        throw "PDF export needs PowerShell 7.4 or later (this is $($PSVersionTable.PSVersion)): the bundled PDFsharp assemblies are built for .NET 8."
    }

    # Load order: dependencies first. Hashes are SHA-256 of the files exactly
    # as published in the nuget.org packages listed in lib\pdf\SOURCES.md.
    $pinned = [ordered]@{
        'Microsoft.Extensions.DependencyInjection.Abstractions.dll' = '67FA4325000DB017DC0C35829B416F024F042D24EFB868BCF17A895EE6500A93'
        'Microsoft.Extensions.Logging.Abstractions.dll'             = 'BB853130F5AFAF335BE7858D661F8212EC653835100F5A4E3AA2C66A4D4F685D'
        'PdfSharp.Shared.dll'                                       = 'B3ED534CAE06D4B2129D1242FA52D57EFFA4F06883C3B959C18966DE7CE8A264'
        'PdfSharp.System.dll'                                       = '6D9ACCDBF73F4C8F79E60B91764B34E25F0ED207820C62DA1112980AD32B6F82'
        'PdfSharp.dll'                                              = 'A30A1C39E942A6C7F33F451257F26E9A8856D389EF98031971711A7C77123D82'
        'PdfSharp.Charting.dll'                                     = '714A27E299BBCB6EAC7AE7F9A83BD8A9972A157A8C53581B73C260EAD16AE24F'
        'MigraDoc.DocumentObjectModel.dll'                          = '32BC0F2644E19F22A5BDFD95EC350E4CE0A6837042F80A565CBB81FA77A39100'
        'MigraDoc.Rendering.dll'                                    = '7D726EBE46F796F6D976F26FE2750FA106187D3F6A94E66C04DE0A98735AE227'
    }

    $folder = Join-Path -Path $script:AACModuleRoot -ChildPath 'lib\pdf'

    # Check everything first, so a bad file can't leave half the set loaded.
    $problems = foreach ($name in $pinned.Keys) {
        $path = Join-Path -Path $folder -ChildPath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            "$name is missing"
            continue
        }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne $pinned[$name]) {
            "$name has SHA-256 $actual, expected $($pinned[$name])"
        }
    }
    if ($problems) {
        throw "PDF export refused to load its libraries from $folder, because they don't match the versions this module was released with:`n  $($problems -join "`n  ")`nRestore the files from the module package (see lib\pdf\SOURCES.md)."
    }

    foreach ($name in $pinned.Keys) {
        $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($name)
        # An assembly of the same name may already be in the session (e.g.
        # Microsoft.Extensions.* from another module); .NET can only load one.
        if (-not ([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq $assemblyName })) {
            Add-Type -Path (Join-Path -Path $folder -ChildPath $name) -ErrorAction Stop
        }
    }

    # PDFsharp's own Windows font support covers only the core fonts (Arial,
    # Times New Roman, ...), so the report's fonts are served by this small
    # resolver, compiled from source here rather than shipped as another
    # binary. It reads the font files from the Windows Fonts folder and falls
    # back to Arial when a Segoe/Consolas file isn't installed. A type (and
    # the global resolver) survive a module reimport, so both happen once.
    if (-not ('Azure.Admin.Console.Pdf.WindowsFontResolver' -as [type])) {
        # -IgnoreWarnings: PdfSharp is built against .NET 8 and PowerShell may
        # run a newer .NET, which the compiler reports as warning CS1701 (a
        # harmless version mapping) and Add-Type would otherwise fail on.
        Add-Type -IgnoreWarnings -WarningAction SilentlyContinue -ReferencedAssemblies (Join-Path -Path $folder -ChildPath 'PdfSharp.dll') -TypeDefinition @'
namespace Azure.Admin.Console.Pdf
{
    using System;
    using System.IO;
    using PdfSharp.Fonts;

    public sealed class WindowsFontResolver : IFontResolver
    {
        private static readonly string FontFolder = Environment.GetFolderPath(Environment.SpecialFolder.Fonts);

        // Candidate files per family and style (regular, bold, italic,
        // bold italic), in order of preference.
        private static string[] Candidates(string family, bool bold, bool italic)
        {
            int style = (bold ? 1 : 0) + (italic ? 2 : 0);
            switch (family.ToLowerInvariant())
            {
                case "segoe ui semibold":
                    return new[] { italic ? "seguisbi.ttf" : "seguisb.ttf", new[] { "arialbd.ttf", "arialbd.ttf", "arialbi.ttf", "arialbi.ttf" }[style] };
                case "consolas":
                    return new[] { new[] { "consola.ttf", "consolab.ttf", "consolai.ttf", "consolaz.ttf" }[style], new[] { "cour.ttf", "courbd.ttf", "couri.ttf", "courbi.ttf" }[style] };
                case "segoe ui symbol":
                    return new[] { "seguisym.ttf", "arial.ttf" };
                default:
                    return new[] { new[] { "segoeui.ttf", "segoeuib.ttf", "segoeuii.ttf", "segoeuiz.ttf" }[style], new[] { "arial.ttf", "arialbd.ttf", "ariali.ttf", "arialbi.ttf" }[style] };
            }
        }

        public FontResolverInfo ResolveTypeface(string familyName, bool bold, bool italic)
        {
            foreach (string file in Candidates(familyName, bold, italic))
            {
                if (File.Exists(Path.Combine(FontFolder, file)))
                {
                    return new FontResolverInfo(file);
                }
            }
            return null;
        }

        public byte[] GetFont(string faceName)
        {
            // Face names are only ever the bare file names returned above.
            string path = Path.Combine(FontFolder, Path.GetFileName(faceName));
            return File.Exists(path) ? File.ReadAllBytes(path) : null;
        }
    }
}
'@
    }
    # PDFsharp allows one font resolver per process: once a PDF has been
    # rendered, it refuses to replace it. The one already there may come from
    # an earlier copy of this module in the same session (before an upgrade
    # or a reimport from another path, under another type name) or from
    # another module - keep it then, rather than fail the export.
    $current = [PdfSharp.Fonts.GlobalFontSettings]::FontResolver
    if ($current -isnot [Azure.Admin.Console.Pdf.WindowsFontResolver]) {
        try {
            [PdfSharp.Fonts.GlobalFontSettings]::FontResolver = [Azure.Admin.Console.Pdf.WindowsFontResolver]::new()
        }
        catch {
            if ($null -eq $current) {
                throw
            }
            Write-Verbose "PDF export keeps the font resolver already in use in this session ($($current.GetType().FullName)); PDFsharp can't replace it once used."
        }
    }
    $script:AACPdfLibraryLoaded = $true
}
