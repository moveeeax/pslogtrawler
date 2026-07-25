#Requires -Version 7.1

# Dot-source all public and private function definitions, then export the
# public surface. Keeping the loader dumb means new functions only need a
# file drop under Public/ or Private/ -- but "dumb" must not mean "quiet":
# a module that imports successfully while missing a command its manifest
# advertises is far worse than one that refuses to import at all.

$privatePath = Join-Path $PSScriptRoot 'Private'
$publicPath  = Join-Path $PSScriptRoot 'Public'

foreach ($dir in @($privatePath, $publicPath)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        throw "PSLogTrawler is incomplete: required directory '$dir' is missing."
    }
}

# Private first: public functions build on the helpers defined there.
$private = @(Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File | Sort-Object -Property Name)
$public  = @(Get-ChildItem -LiteralPath $publicPath  -Filter '*.ps1' -File | Sort-Object -Property Name)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        # Previously this only wrote a non-terminating error, so a syntax error
        # in any one file left the module importable but silently missing that
        # command. Fail the import instead.
        throw "PSLogTrawler failed to load '$($file.FullName)': $($_.Exception.Message)"
    }
}

# The manifest is the contract with callers. Verify every function it promises
# actually got defined, so drift between FunctionsToExport and the files on
# disk surfaces at import time rather than as "command not found" later.
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'PSLogTrawler.psd1')
$declared = @($manifest.FunctionsToExport) | Where-Object { $_ -and $_ -ne '*' }

$missing = @($declared | Where-Object { -not (Test-Path -LiteralPath "Function:\$_") })
if ($missing.Count -gt 0) {
    throw ("PSLogTrawler manifest advertises functions that no file under '{0}' defines: {1}." -f
        $publicPath, ($missing -join ', '))
}

Export-ModuleMember -Function $public.BaseName
