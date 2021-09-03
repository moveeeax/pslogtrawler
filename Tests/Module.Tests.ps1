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
}
