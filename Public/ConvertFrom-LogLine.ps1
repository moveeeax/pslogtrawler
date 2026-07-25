function ConvertFrom-LogLine {
    <#
    .SYNOPSIS
        Parse a single log line into a structured object.
    .DESCRIPTION
        Recognizes two common line shapes:

          * ISO-8601 bracketed:  [2021-08-14T13:45:22] [ERROR] disk full
                                 [2021-08-14 13:45:22] WARN retrying
          * syslog-ish:          Aug 14 13:45:22 host app: ERROR disk full

        Returns an object with Timestamp ([datetime] or $null), Level (one of
        ERROR/WARN/INFO/DEBUG or $null when no level keyword is present),
        Message (string) and the original Raw line. Lines that match no known
        shape still return an object with Raw set and the message carrying the
        whole line, so a pipeline never silently drops data.
    .PARAMETER Line
        The log line(s) to parse. Accepts pipeline input.
    .PARAMETER DefaultYear
        Year to assume for syslog stamps that omit it. Defaults to the current
        year.
    .EXAMPLE
        '[2021-08-14T13:45:22] [ERROR] disk full' | ConvertFrom-LogLine

        Returns an object with Level 'ERROR' and the parsed Timestamp.
    .EXAMPLE
        Get-Content app.log | ConvertFrom-LogLine | Where-Object Level -eq 'ERROR'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [AllowEmptyString()]
        [string[]] $Line,

        [int] $DefaultYear = (Get-Date).Year
    )

    begin {
        # These three patterns are fixed for the lifetime of the module, but
        # this begin block runs on every single invocation -- and the
        # aggregating cmdlets call this function once per log line. Rebuilding
        # (and re-JITting) the regexes each time cost ~2.8x the parse time on a
        # 20k-line file, so build them once and cache them at module scope.
        if ($null -eq $script:LogLinePatterns) {
            $opts = [System.Text.RegularExpressions.RegexOptions]::Compiled
            # A log line is untrusted input; cap any single match so a
            # pathological line cannot wedge the pipeline indefinitely.
            $matchTimeout = [timespan]::FromSeconds(2)

            $script:LogLinePatterns = @{
                Iso = [regex]::new(
                    '^\s*\[?(?<ts>\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?)\]?\s*' +
                    '(?:\[\s*(?<lvl>[A-Za-z]+)\s*\]|(?<lvl2>[A-Za-z]+))?\s*(?<msg>.*)$',
                    $opts, $matchTimeout)

                Syslog = [regex]::new(
                    '^\s*(?<ts>[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(?<msg>.*)$',
                    $opts, $matchTimeout)

                LevelWord = [regex]::new(
                    ('\b({0})\b' -f ((Get-KnownLevelToken) -join '|')),
                    ($opts -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase),
                    $matchTimeout)
            }
        }

        $isoPattern    = $script:LogLinePatterns.Iso
        $syslogPattern = $script:LogLinePatterns.Syslog
        $levelWord     = $script:LogLinePatterns.LevelWord
    }

    process {
        foreach ($raw in $Line) {
            $text = if ($null -eq $raw) { '' } else { $raw }

            $timestamp = $null
            $level     = $null
            $message   = $text

            $m = $isoPattern.Match($text)
            if ($m.Success) {
                # Some frameworks (log4j/log4net) use a comma before the
                # fractional seconds; normalize it so .NET can parse it.
                $tsText = $m.Groups['ts'].Value -replace ',(\d)', '.$1'
                $timestamp = ConvertTo-LogDateTime -Text $tsText -DefaultYear $DefaultYear

                $rawLevel = if ($m.Groups['lvl'].Success) { $m.Groups['lvl'].Value }
                            elseif ($m.Groups['lvl2'].Success) { $m.Groups['lvl2'].Value }
                            else { $null }

                $normalized = ConvertTo-NormalizedLevel -Token $rawLevel
                if ($normalized) {
                    $level   = $normalized
                    $message = $m.Groups['msg'].Value.Trim()
                }
                else {
                    # The token we grabbed was actually part of the message.
                    $rebuilt = ('{0} {1}' -f $rawLevel, $m.Groups['msg'].Value).Trim()
                    $message = if ([string]::IsNullOrEmpty($rebuilt)) { $m.Groups['msg'].Value.Trim() } else { $rebuilt }
                }
            }
            else {
                $s = $syslogPattern.Match($text)
                if ($s.Success) {
                    $timestamp = ConvertTo-LogDateTime -Text $s.Groups['ts'].Value -DefaultYear $DefaultYear
                    $message   = $s.Groups['msg'].Value.Trim()
                }
            }

            if (-not $level) {
                $lw = $levelWord.Match($message)
                if ($lw.Success) {
                    $level = ConvertTo-NormalizedLevel -Token $lw.Value
                }
            }

            [pscustomobject]@{
                PSTypeName = 'PSLogTrawler.LogEntry'
                Timestamp  = $timestamp
                Level      = $level
                Message    = $message
                Raw        = $text
            }
        }
    }
}
