BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PSLogTrawler.psd1') -Force

    $script:sampleLines = @(
        '[2021-08-14T13:45:22] [ERROR] disk full',
        '[2021-08-14T13:46:00] [WARN] retrying',
        '[2021-08-14T13:47:00] [INFO] recovered',
        '[2021-08-14T13:48:00] [INFO] steady',
        '[2021-08-14T13:49:00] [DEBUG] trace details',
        '',
        'a line with no level at all'
    )
}

Describe 'Get-LogSummary' {

    Context 'counting by level from the pipeline' {
        BeforeAll {
            $script:summary = $sampleLines | Get-LogSummary
        }

        It 'counts errors, warnings, info and debug lines' {
            $summary.Error | Should -Be 1
            $summary.Warn  | Should -Be 1
            $summary.Info  | Should -Be 2
            $summary.Debug | Should -Be 1
        }

        It 'buckets unrecognized lines under Unknown' {
            $summary.Unknown | Should -Be 1
        }

        It 'skips blank lines by default and records the count' {
            $summary.BlankSkipped | Should -Be 1
            $summary.Total | Should -Be 6
        }

        It 'reports the covered time range' {
            $summary.First.ToString('HH:mm:ss') | Should -Be '13:45:22'
            $summary.Last.ToString('HH:mm:ss')  | Should -Be '13:49:00'
        }

        It 'stamps the object with the PSLogTrawler.LogSummary type name' {
            $summary.PSObject.TypeNames | Should -Contain 'PSLogTrawler.LogSummary'
        }
    }

    Context 'IncludeBlank switch' {
        It 'counts blank lines toward the total when requested' {
            $summary = $sampleLines | Get-LogSummary -IncludeBlank
            $summary.Total | Should -Be 7
            $summary.Unknown | Should -Be 2
            $summary.BlankSkipped | Should -Be 0
        }
    }

    Context 'reading from a file' {
        BeforeAll {
            $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pslt-{0}.log" -f [guid]::NewGuid())
            Set-Content -LiteralPath $tmp -Value $sampleLines
        }
        AfterAll {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }

        It 'produces the same counts as the pipeline path' {
            $summary = Get-LogSummary -Path $tmp
            $summary.Error | Should -Be 1
            $summary.Info  | Should -Be 2
            $summary.Total | Should -Be 6
        }

        It 'throws when the file does not exist' {
            { Get-LogSummary -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'does-not-exist-9182.log') } |
                Should -Throw
        }
    }

    Context 'empty input' {
        It 'returns zero counts for no lines' {
            $summary = @() | Get-LogSummary
            $summary.Total | Should -Be 0
            $summary.Error | Should -Be 0
        }
    }
}
