BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PSLogTrawler.psd1') -Force

    # Epoch stamps come back as local time; compare in UTC so the tests do not
    # depend on the runner's time zone.
    function script:ConvertTo-Utc([datetime] $Value) { $Value.ToUniversalTime() }
}

Describe 'ConvertFrom-LogLine -Format Json' {

    Context 'common JSON loggers' {
        It 'parses a pino line with a numeric level and epoch-millisecond time' {
            $line = '{"level":50,"time":1628948722000,"pid":1,"hostname":"h","msg":"disk full","user":"alice"}'
            $entry = ConvertFrom-LogLine -Line $line -Format Json
            $entry.Level | Should -Be 'ERROR'
            $entry.Message | Should -Be 'disk full'
            (ConvertTo-Utc $entry.Timestamp) | Should -Be ([datetime]::new(2021, 8, 14, 13, 45, 22, [System.DateTimeKind]::Utc))
            $entry.Fields.user | Should -Be 'alice'
            $entry.Fields.pid | Should -Be 1
        }

        It 'parses a zap line with a string level and fractional epoch-second ts' {
            $line = '{"level":"warn","ts":1628948722.5,"caller":"main.go:42","msg":"retrying"}'
            $entry = ConvertFrom-LogLine -Line $line -Format Json
            $entry.Level | Should -Be 'WARN'
            $entry.Message | Should -Be 'retrying'
            (ConvertTo-Utc $entry.Timestamp).ToString('yyyy-MM-ddTHH:mm:ss.fff') | Should -Be '2021-08-14T13:45:22.500'
            $entry.Fields.caller | Should -Be 'main.go:42'
        }

        It 'parses a bunyan line with an ISO time string' {
            $line = '{"name":"app","hostname":"h","pid":1,"level":30,"msg":"hi","time":"2021-08-14T13:45:22.000Z","v":0}'
            $entry = ConvertFrom-LogLine -Line $line -Format Json
            $entry.Level | Should -Be 'INFO'
            (ConvertTo-Utc $entry.Timestamp) | Should -Be ([datetime]::new(2021, 8, 14, 13, 45, 22, [System.DateTimeKind]::Utc))
            $entry.Fields.name | Should -Be 'app'
        }

        It 'parses a Serilog compact (CLEF) line and treats a missing @l as INFO' {
            $line = '{"@t":"2021-08-14T13:45:22.1230000Z","@mt":"User {User} logged in","User":"bob"}'
            $entry = ConvertFrom-LogLine -Line $line -Format Json
            $entry.Level | Should -Be 'INFO'
            $entry.Message | Should -Be 'User {User} logged in'
            (ConvertTo-Utc $entry.Timestamp).Millisecond | Should -Be 123
            $entry.Fields.User | Should -Be 'bob'
        }

        It 'prefers the rendered @m over the @mt template and reads @l' {
            $line = '{"@t":"2021-08-14T13:45:22Z","@m":"User bob failed","@mt":"User {User} failed","@l":"Error","User":"bob"}'
            $entry = ConvertFrom-LogLine -Line $line -Format Json
            $entry.Level | Should -Be 'ERROR'
            $entry.Message | Should -Be 'User bob failed'
            $entry.Fields['@mt'] | Should -Be 'User {User} failed'
        }

        It 'matches field names case-insensitively (Serilog JsonFormatter)' {
            $line = '{"Timestamp":"2021-08-14T13:45:22+00:00","Level":"Warning","MessageTemplate":"low disk"}'
            $entry = ConvertFrom-LogLine -Line $line -Format Json
            $entry.Level | Should -Be 'WARN'
            (ConvertTo-Utc $entry.Timestamp).Hour | Should -Be 13
        }
    }

    Context 'level mapping' {
        It 'maps pino/bunyan numeric level <Value> to <Expected>' -ForEach @(
            @{ Value = '10'; Expected = 'DEBUG' }
            @{ Value = '20'; Expected = 'DEBUG' }
            @{ Value = '30'; Expected = 'INFO' }
            @{ Value = '40'; Expected = 'WARN' }
            @{ Value = '50'; Expected = 'ERROR' }
            @{ Value = '60'; Expected = 'ERROR' }
            @{ Value = '"60"'; Expected = 'ERROR' }
        ) {
            (ConvertFrom-LogLine -Line ('{{"level":{0},"msg":"x"}}' -f $Value) -Format Json).Level | Should -Be $Expected
        }

        It 'maps zap panic levels and cloud severities onto ERROR' {
            (ConvertFrom-LogLine -Line '{"level":"dpanic","msg":"x"}' -Format Json).Level | Should -Be 'ERROR'
            (ConvertFrom-LogLine -Line '{"level":"panic","msg":"x"}' -Format Json).Level | Should -Be 'ERROR'
            (ConvertFrom-LogLine -Line '{"severity":"ALERT","message":"x"}' -Format Json).Level | Should -Be 'ERROR'
        }

        It 'keeps an unrecognized level in Fields and leaves Level empty' {
            $entry = ConvertFrom-LogLine -Line '{"level":"audit","msg":"x"}' -Format Json
            $entry.Level | Should -BeNullOrEmpty
            $entry.Fields.level | Should -Be 'audit'
        }

        It 'does not guess a level from the message text' {
            (ConvertFrom-LogLine -Line '{"msg":"ERROR in upstream"}' -Format Json).Level | Should -BeNullOrEmpty
        }
    }

    Context 'field selection' {
        It 'uses the first matching field name and keeps the others in Fields' {
            $entry = ConvertFrom-LogLine -Line '{"time":"2021-01-02T03:04:05Z","ts":1628948722,"msg":"x"}' -Format Json
            (ConvertTo-Utc $entry.Timestamp).Month | Should -Be 1
            $entry.Fields.ts | Should -Be 1628948722
            $entry.Fields.Contains('time') | Should -BeFalse
            $entry.Fields.Contains('msg') | Should -BeFalse
        }

        It 'skips a candidate field whose value is null' {
            $entry = ConvertFrom-LogLine -Line '{"level":null,"lvl":"error","msg":"x"}' -Format Json
            $entry.Level | Should -Be 'ERROR'
        }

        It 'honors custom field names' {
            $line = '{"sev":"error","when":"2021-08-14T13:45:22Z","text":"boom","level":"info"}'
            $entry = ConvertFrom-LogLine -Line $line -Format Json -LevelField 'sev' -TimestampField 'when' -MessageField 'text'
            $entry.Level | Should -Be 'ERROR'
            $entry.Message | Should -Be 'boom'
            (ConvertTo-Utc $entry.Timestamp).Day | Should -Be 14
            $entry.Fields.level | Should -Be 'info'
        }

        It 'uses the whole line as the message when no message field is present' {
            $line = '{"level":"error","code":42}'
            (ConvertFrom-LogLine -Line $line -Format Json).Message | Should -Be $line
        }

        It 'keeps nested objects reachable through Fields' {
            $entry = ConvertFrom-LogLine -Line '{"msg":"x","http":{"status":500,"path":"/a"}}' -Format Json
            $entry.Fields.http.status | Should -Be 500
        }

        It 'supports filtering on Fields in the pipeline' {
            $lines = @(
                '{"level":30,"msg":"a","user":"alice"}',
                '{"level":30,"msg":"b","user":"bob"}'
            )
            $hits = @($lines | ConvertFrom-LogLine -Format Json | Where-Object { $_.Fields.user -eq 'bob' })
            $hits.Count | Should -Be 1
            $hits[0].Message | Should -Be 'b'
        }
    }

    Context 'non-JSON input' {
        It 'falls back to the text parser for a plain-text line' {
            $entry = ConvertFrom-LogLine -Line '[2021-08-14T13:45:22] [ERROR] disk full' -Format Json
            $entry.Level | Should -Be 'ERROR'
            $entry.Message | Should -Be 'disk full'
            $entry.Fields | Should -BeNullOrEmpty
        }

        It 'falls back without throwing on malformed JSON' {
            $line = '{"level":"error","msg":'
            $entry = ConvertFrom-LogLine -Line $line -Format Json
            $entry.Raw | Should -Be $line
            $entry.Fields | Should -BeNullOrEmpty
        }

        It 'treats a JSON array as non-record input' {
            (ConvertFrom-LogLine -Line '[1,2,3]' -Format Json).Fields | Should -BeNullOrEmpty
        }

        It 'leaves JSON lines alone in the default Text format' {
            $line = '{"level":50,"msg":"x"}'
            $entry = ConvertFrom-LogLine -Line $line
            $entry.Message | Should -Be $line
            $entry.Fields | Should -BeNullOrEmpty
        }

        It 'rejects an unknown -Format value' {
            { ConvertFrom-LogLine -Line 'x' -Format Xml } | Should -Throw
        }
    }

    Context 'output shape' {
        It 'stamps JSON entries with the PSLogTrawler.LogEntry type name and keeps Raw' {
            $line = '{"level":30,"msg":"x"}'
            $entry = ConvertFrom-LogLine -Line $line -Format Json
            $entry.PSObject.TypeNames | Should -Contain 'PSLogTrawler.LogEntry'
            $entry.Raw | Should -Be $line
        }

        It 'gives text and JSON entries the same property names' {
            $text = ConvertFrom-LogLine -Line '[2021-08-14T13:45:22] [INFO] hi'
            $json = ConvertFrom-LogLine -Line '{"level":30,"msg":"hi"}' -Format Json
            $text.PSObject.Properties.Name | Should -Be $json.PSObject.Properties.Name
        }
    }
}

Describe 'JSON lines through the aggregating cmdlets' {
    BeforeAll {
        $script:fixture = Join-Path $PSScriptRoot 'fixtures/sample.jsonl'
    }

    It 'summarizes a JSON-lines file by level' {
        $summary = Get-LogSummary -Path $fixture -Format Json
        $summary.Error        | Should -Be 3
        $summary.Warn         | Should -Be 1
        $summary.Info         | Should -Be 3
        $summary.Debug        | Should -Be 1
        $summary.Unknown      | Should -Be 1
        $summary.BlankSkipped | Should -Be 1
        $summary.Total        | Should -Be 9
        (ConvertTo-Utc $summary.First) | Should -Be ([datetime]::new(2021, 8, 14, 9, 0, 1, [System.DateTimeKind]::Utc))
        (ConvertTo-Utc $summary.Last)  | Should -Be ([datetime]::new(2021, 8, 14, 10, 10, 0, [System.DateTimeKind]::Utc))
    }

    It 'counts nothing by level when the JSON file is read as text' {
        $summary = Get-LogSummary -Path $fixture
        $summary.Error | Should -Be 0
        $summary.Unknown | Should -Be 9
    }

    It 'selects JSON errors by pattern from the pipeline' {
        $hits = @(Get-Content $fixture | Select-LogError -Format Json -IncludeWarnings -Pattern 'disk')
        $hits.Count | Should -Be 2
        $hits.Message | Should -Contain 'disk full on /var'
    }

    It 'honors custom field names in Select-LogError' {
        $lines = @('{"sev":"error","text":"boom"}', '{"sev":"info","text":"fine"}')
        $hits = @($lines | Select-LogError -Format Json -LevelField 'sev' -MessageField 'text')
        $hits.Count | Should -Be 1
        $hits[0].Message | Should -Be 'boom'
    }

    It 'measures the JSON error rate' {
        $buckets = @(Measure-LogRate -Path $fixture -Format Json -Level ERROR -Interval Minute)
        ($buckets | Measure-Object -Property Count -Sum).Sum | Should -Be 3
    }

    It 'counts the non-JSON banner as a line without a timestamp' {
        $buckets = @(Get-Content $fixture | Measure-LogRate -Format Json -Interval Hour)
        ($buckets | Measure-Object -Property Count -Sum).Sum | Should -Be 8
        $buckets[0].SkippedNoTimestamp | Should -Be 1
    }
}
