BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PSLogTrawler.psd1') -Force
}

Describe 'ConvertFrom-LogLine' {

    Context 'ISO-8601 bracketed format' {
        It 'parses timestamp, level and message from a bracketed line' {
            $entry = ConvertFrom-LogLine -Line '[2021-08-14T13:45:22] [ERROR] disk full'
            $entry.Level | Should -Be 'ERROR'
            $entry.Message | Should -Be 'disk full'
            $entry.Timestamp.Year | Should -Be 2021
            $entry.Timestamp.Month | Should -Be 8
            $entry.Timestamp.Day | Should -Be 14
        }

        It 'accepts a space between date and time and an unbracketed level' {
            $entry = ConvertFrom-LogLine -Line '[2021-08-14 09:00:05] WARN retrying now'
            $entry.Level | Should -Be 'WARN'
            $entry.Message | Should -Be 'retrying now'
        }

        It 'normalizes level synonyms such as WARNING to WARN' {
            (ConvertFrom-LogLine -Line '[2021-08-14T00:00:00] [WARNING] hmm').Level | Should -Be 'WARN'
            (ConvertFrom-LogLine -Line '[2021-08-14T00:00:00] [FATAL] boom').Level | Should -Be 'ERROR'
            (ConvertFrom-LogLine -Line '[2021-08-14T00:00:00] [TRACE] noise').Level | Should -Be 'DEBUG'
        }
    }

    Context 'syslog-ish format' {
        It 'parses a syslog stamp using the supplied default year' {
            $entry = ConvertFrom-LogLine -Line 'Aug 14 13:45:22 host app: ERROR boom' -DefaultYear 2021
            $entry.Timestamp.Year | Should -Be 2021
            $entry.Timestamp.Month | Should -Be 8
            $entry.Level | Should -Be 'ERROR'
        }
    }

    Context 'edge cases' {
        It 'returns a null level for a line with no level keyword' {
            $entry = ConvertFrom-LogLine -Line 'plain line without any level word'
            $entry.Level | Should -BeNullOrEmpty
            $entry.Message | Should -Be 'plain line without any level word'
        }

        It 'handles a blank line without throwing' {
            $entry = ConvertFrom-LogLine -Line ''
            $entry.Level | Should -BeNullOrEmpty
            $entry.Message | Should -Be ''
            $entry.Timestamp | Should -BeNullOrEmpty
        }

        It 'preserves the original text in Raw' {
            $raw = '[2021-08-14T13:45:22] [INFO] hello world'
            (ConvertFrom-LogLine -Line $raw).Raw | Should -Be $raw
        }

        It 'stamps the object with the PSLogTrawler.LogEntry type name' {
            $entry = ConvertFrom-LogLine -Line '[2021-08-14T13:45:22] [INFO] hi'
            $entry.PSObject.TypeNames | Should -Contain 'PSLogTrawler.LogEntry'
        }
    }

    Context 'pipeline input' {
        It 'parses many lines from the pipeline' {
            $lines = @(
                '[2021-08-14T13:45:22] [ERROR] one',
                '[2021-08-14T13:45:23] [INFO] two'
            )
            $result = $lines | ConvertFrom-LogLine
            $result.Count | Should -Be 2
            $result[0].Level | Should -Be 'ERROR'
            $result[1].Level | Should -Be 'INFO'
        }
    }
}
