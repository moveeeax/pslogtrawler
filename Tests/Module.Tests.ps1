BeforeAll {
    $script:moduleRoot = Split-Path -Parent $PSScriptRoot
    $script:manifestPath = Join-Path $moduleRoot 'PSLogTrawler.psd1'
    Import-Module $manifestPath -Force
}

Describe 'Module manifest and surface' {

    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $manifestPath } | Should -Not -Throw
    }

    It 'declares ModuleVersion 0.1.0' {
        (Import-PowerShellDataFile -Path $manifestPath).ModuleVersion | Should -Be '0.1.0'
    }

    It 'requires PowerShell 7.1' {
        (Import-PowerShellDataFile -Path $manifestPath).PowerShellVersion | Should -Be '7.1'
    }

    It 'exports exactly the four public functions' {
        $exported = (Get-Module PSLogTrawler).ExportedFunctions.Keys | Sort-Object
        $expected = @('ConvertFrom-LogLine', 'Get-LogSummary', 'Measure-LogRate', 'Select-LogError')
        $exported | Should -Be $expected
    }

    It 'does not leak private helpers' {
        (Get-Module PSLogTrawler).ExportedFunctions.Keys | Should -Not -Contain 'ConvertTo-NormalizedLevel'
        (Get-Module PSLogTrawler).ExportedFunctions.Keys | Should -Not -Contain 'ConvertTo-LogDateTime'
    }

    It 'ships comment-based help for every public function' {
        foreach ($fn in @('ConvertFrom-LogLine', 'Get-LogSummary', 'Select-LogError', 'Measure-LogRate')) {
            (Get-Help $fn).Synopsis | Should -Not -BeNullOrEmpty
        }
    }

    It 'advertises exactly the functions that Public/ actually defines' {
        # Guards against the manifest promising a command no file implements
        # (documented but unreachable) and against a new Public/*.ps1 silently
        # never reaching callers because the manifest was not updated.
        $declared = (Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport | Sort-Object
        $onDisk = Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Public') -Filter '*.ps1' -File |
            Select-Object -ExpandProperty BaseName | Sort-Object
        $declared | Should -Be $onDisk
    }
}

Describe 'Module import integrity' {

    BeforeAll {
        # A throwaway copy we can deliberately damage.
        $script:broken = Join-Path ([System.IO.Path]::GetTempPath()) ('pslt-broken-' + [guid]::NewGuid())
        Copy-Item -LiteralPath (Split-Path -Parent $PSScriptRoot) -Destination $broken -Recurse
    }
    AfterAll {
        Remove-Module PSLogTrawler -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $broken -Recurse -Force -ErrorAction SilentlyContinue
    }
    AfterEach {
        Remove-Module PSLogTrawler -Force -ErrorAction SilentlyContinue
    }

    It 'fails the import when a public source file cannot be parsed' {
        # Previously this only wrote a non-terminating error: the module
        # imported "successfully" while Get-LogSummary silently did not exist.
        $target = Join-Path $broken 'Public/Get-LogSummary.ps1'
        $original = Get-Content -LiteralPath $target -Raw
        try {
            Add-Content -LiteralPath $target -Value 'function {{{ syntactically broken'
            { Import-Module (Join-Path $broken 'PSLogTrawler.psd1') -Force -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*failed to load*'
        }
        finally {
            Set-Content -LiteralPath $target -Value $original -NoNewline
        }
    }

    It 'fails the import when a manifest-declared function is not defined anywhere' {
        $target = Join-Path $broken 'Public/Measure-LogRate.ps1'
        $original = Get-Content -LiteralPath $target -Raw
        try {
            # Valid PowerShell, but no longer defines Measure-LogRate.
            Set-Content -LiteralPath $target -Value '# intentionally defines nothing'
            { Import-Module (Join-Path $broken 'PSLogTrawler.psd1') -Force -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Measure-LogRate*'
        }
        finally {
            Set-Content -LiteralPath $target -Value $original -NoNewline
        }
    }

    It 'still imports cleanly when nothing is damaged' {
        { Import-Module (Join-Path $broken 'PSLogTrawler.psd1') -Force -ErrorAction Stop } | Should -Not -Throw
        (Get-Module PSLogTrawler).ExportedFunctions.Keys | Should -Contain 'Measure-LogRate'
    }
}

Describe 'File input is streamed, not buffered' {

    # Reading a whole log into an array costs roughly 35x the file size in
    # managed heap and made Get-LogSummary OOM on a 25 MB log under a 96 MB
    # heap cap. Every -Path branch must enumerate lazily instead.
    It '<Name> reads its -Path input with File::ReadLines and never calls Get-Content' -ForEach @(
        @{ Name = 'Get-LogSummary' }
        @{ Name = 'Select-LogError' }
        @{ Name = 'Measure-LogRate' }
    ) {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        $file = Join-Path $moduleRoot "Public/$Name.ps1"

        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref] $null, [ref] $null)

        # Inspect real command invocations only -- Get-Content legitimately
        # appears in the .EXAMPLE help text of these functions.
        $invoked = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true) | ForEach-Object { $_.GetCommandName() }

        $invoked | Should -Not -Contain 'Get-Content'

        $readLines = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $node.Member.Value -eq 'ReadLines'
            }, $true)
        $readLines.Count | Should -BeGreaterThan 0
    }
}
