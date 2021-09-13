function Get-KnownLevelToken {
    <#
    .SYNOPSIS
        Return every raw level token the module recognizes.
    .DESCRIPTION
        Single source of truth for the level synonyms understood by the module.
        ConvertTo-NormalizedLevel folds these onto canonical buckets and
        ConvertFrom-LogLine builds its level-detection regex from the same list,
        so the two never drift apart.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    ,@(
        'ERROR', 'ERR', 'FATAL', 'CRITICAL', 'CRIT', 'SEVERE',
        'WARN', 'WARNING',
        'INFO', 'INFORMATION', 'NOTICE',
        'DEBUG', 'TRACE', 'VERBOSE', 'FINE'
    )
}
