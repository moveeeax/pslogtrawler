BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PSLogTrawler.psd1') -Force

    $script:lines = @(
        '[2021-08-14T13:45:10] [INFO] a',
        '[2021-08-14T13:45:40] [ERROR] b',
        '[2021-08-14T13:46:05] [INFO] c',
        '[2021-08-14T14:10:00] [INFO] d',
        'no timestamp on this one'
    )
}

Describe 'Measure-LogRate' {

    Context 'per-minute bucketing' {
        BeforeAll {
            $script:buckets = $lines | Measure-LogRate -Interval Minute
        }

        It 'creates one bucket per distinct minute with events' {
            $buckets.Count | Should -Be 3
        }

        It 'counts two events in the 13:45 bucket' {
            $b = $buckets | Where-Object { $_.Start.ToString('HH:mm') -eq '13:45' }
            $b.Count | Should -Be 2
            $b.Rate | Should -Be 2
        }

        It 'reports skipped lines that had no timestamp' {
            $buckets[0].SkippedNoTimestamp | Should -Be 1
        }

        It 'returns buckets in chronological order' {
            $ordered = $buckets.Start
            $sorted = $buckets.Start | Sort-Object
            $ordered | Should -Be $sorted
        }
    }

    Context 'per-hour bucketing' {
        BeforeAll {
            $script:hourly = $lines | Measure-LogRate -Interval Hour
        }

        It 'collapses events into hourly buckets' {
            $hourly.Count | Should -Be 2
            ($hourly | Where-Object { $_.Start.Hour -eq 13 }).Count | Should -Be 3
        }

        It 'expresses Rate as events per minute' {
            # three events in an hour => 3 / 60 = 0.05 per minute
            ($hourly | Where-Object { $_.Start.Hour -eq 13 }).Rate | Should -Be 0.05
        }
    }

    Context 'level filtering' {
        It 'counts only the requested level' {
            $errBuckets = $lines | Measure-LogRate -Interval Hour -Level ERROR
            $errBuckets.Count | Should -Be 1
            $errBuckets[0].Count | Should -Be 1
        }
    }

    Context 'edge cases' {
        It 'returns nothing when no line has a timestamp' {
            $result = @('plain one', 'plain two') | Measure-LogRate
            $result | Should -BeNullOrEmpty
        }

        It 'stamps buckets with the PSLogTrawler.RateBucket type name' {
            ($lines | Measure-LogRate)[0].PSObject.TypeNames | Should -Contain 'PSLogTrawler.RateBucket'
        }
    }
}
