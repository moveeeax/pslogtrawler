function ConvertTo-NormalizedLevel {
    <#
    .SYNOPSIS
        Map a raw log-level token to one of the canonical levels.
    .DESCRIPTION
        Folds common synonyms (WARNING, FATAL, TRACE, ...) onto the four
        canonical buckets used across the module: ERROR, WARN, INFO, DEBUG.
        Unknown tokens fall through as $null so callers can decide what to do.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [string] $Token
    )

    if ([string]::IsNullOrWhiteSpace($Token)) {
        return $null
    }

    switch -Regex ($Token.Trim().ToUpperInvariant()) {
        '^(ERROR|ERR|FATAL|CRITICAL|CRIT|SEVERE)$' { return 'ERROR' }
        '^(WARN|WARNING)$'                          { return 'WARN' }
        '^(INFO|INFORMATION|NOTICE)$'               { return 'INFO' }
        '^(DEBUG|TRACE|VERBOSE|FINE)$'              { return 'DEBUG' }
        default                                     { return $null }
    }
}
