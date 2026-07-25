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

        It 'throws a clear error when the path does not exist' {
            { Select-LogError -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'nope-4471.log') } |
                Should -Throw -ExpectedMessage '*Log file not found*'
        }

        It 'throws rather than trying to read a directory as a log' {
            { Select-LogError -Path ([System.IO.Path]::GetTempPath()) } |
                Should -Throw -ExpectedMessage '*directory*'
        }
    }

    Context 'hostile -Pattern input' {
        It 'gives up on a catastrophically backtracking pattern instead of hanging' {
            # '(a+)+$' against a non-matching run of a's is the classic
            # exponential-backtracking case. With no match timeout this ran
            # unbounded (still going after 25s) and could not be interrupted.
            $line = '[2021-08-14T09:00:00] [ERROR] ' + ('a' * 32) + '!'
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            { $line | Select-LogError -Pattern '(a+)+$' } |
                Should -Throw -ExpectedMessage '*match timeout*'
            $sw.Stop()
            $sw.Elapsed.TotalSeconds | Should -BeLessThan 15
        }

        It 'reports an invalid regular expression as an argument error' {
            $err = $null
            try { 'x' | Select-LogError -Pattern '([unclosed' } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $err.CategoryInfo.Category | Should -Be 'InvalidArgument'
            $err.Exception | Should -BeOfType [System.ArgumentException]
        }
    }
}
