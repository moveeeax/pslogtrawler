BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PSLogTrawler.psd1') -Force

    $script:lines = @(
        '[2021-08-14T13:45:22] [ERROR] disk full',
        '[2021-08-14T13:46:00] [WARN] retrying timeout',
        '[2021-08-14T13:47:00] [INFO] recovered',
        '[2021-08-14T14:00:00] [ERROR] connection refused',
        '[2021-08-14T14:05:00] [DEBUG] noisy trace'
    )
}

Describe 'Select-LogError' {

    Context 'default behaviour' {
        It 'returns only ERROR entries by default' {
            $result = $lines | Select-LogError
            $result.Count | Should -Be 2
            $result.Level | Should -Not -Contain 'WARN'
            $result.Message | Should -Contain 'disk full'
            $result.Message | Should -Contain 'connection refused'
        }
    }

    Context 'IncludeWarnings' {
        It 'also returns WARN entries when asked' {
            $result = $lines | Select-LogError -IncludeWarnings
            $result.Count | Should -Be 3
            ($result | Where-Object Level -eq 'WARN').Message | Should -Be 'retrying timeout'
        }
    }

    Context '-Pattern filtering' {
        It 'keeps only messages matching the regex' {
            $result = $lines | Select-LogError -Pattern 'refused'
            $result.Count | Should -Be 1
            $result[0].Message | Should -Be 'connection refused'
        }

        It 'matches case-insensitively' {
            $result = $lines | Select-LogError -Pattern 'DISK'
            $result.Count | Should -Be 1
            $result[0].Message | Should -Be 'disk full'
        }
    }

    Context '-Since filtering' {
        It 'drops entries before the cutoff' {
            $result = $lines | Select-LogError -Since ([datetime]'2021-08-14T13:50:00')
            $result.Count | Should -Be 1
            $result[0].Message | Should -Be 'connection refused'
        }

        It 'keeps undated error lines unless RequireTimestamp is set' {
            $mixed = @(
                '[2021-08-14T13:45:22] [ERROR] dated old',
                'ERROR undated but urgent'
            )
            ($mixed | Select-LogError -Since ([datetime]'2021-08-14T14:00:00')).Message |
                Should -Be 'ERROR undated but urgent'

            ($mixed | Select-LogError -Since ([datetime]'2021-08-14T14:00:00') -RequireTimestamp) |
                Should -BeNullOrEmpty
        }
    }

    Context 'combined Since and Pattern' {
        It 'applies both filters together' {
            $result = $lines | Select-LogError -IncludeWarnings -Since ([datetime]'2021-08-14T13:46:00') -Pattern 'timeout|refused'
            $result.Count | Should -Be 2
        }
    }

    Context 'file input' {
        BeforeAll {
            $script:tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pslt-err-{0}.log" -f [guid]::NewGuid())
            Set-Content -LiteralPath $tmp -Value $lines
        }
        AfterAll {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }

        It 'reads errors from a file path' {
            (Select-LogError -Path $tmp).Count | Should -Be 2
        }
    }
}
