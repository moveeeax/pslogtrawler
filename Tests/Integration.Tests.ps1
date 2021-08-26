BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PSLogTrawler.psd1') -Force
    $script:fixture = Join-Path $PSScriptRoot 'fixtures/sample.log'
}

Describe 'End-to-end on a sample log file' {

    It 'has the fixture available' {
        Test-Path $fixture | Should -BeTrue
    }

    It 'summarizes the sample file with expected counts' {
        $summary = Get-LogSummary -Path $fixture
        $summary.Error   | Should -Be 3
        $summary.Warn    | Should -Be 2
        $summary.Info    | Should -Be 4
        $summary.Debug   | Should -Be 2
        $summary.Unknown | Should -Be 1
        $summary.Total   | Should -Be 12
    }

    It 'selects the three error lines from the file' {
        $errors = Get-Content $fixture | Select-LogError
        $errors.Count | Should -Be 3
        $errors.Message | Should -Contain 'upstream request timeout'
    }

    It 'finds disk-related errors and warnings via pattern' {
        $hits = Get-Content $fixture | Select-LogError -IncludeWarnings -Pattern 'disk'
        $hits.Count | Should -Be 2
    }

    It 'buckets the file into two hourly rate buckets' {
        $rate = Get-Content $fixture | Measure-LogRate -Interval Hour
        $rate.Count | Should -Be 2
        ($rate | Where-Object { $_.Start.Hour -eq 9 }).Count | Should -Be 7
        ($rate | Where-Object { $_.Start.Hour -eq 10 }).Count | Should -Be 4
    }
}
