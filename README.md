# PSLogTrawler

A small, cross-platform PowerShell toolkit for trawling plain-text log files:
parse lines into structured objects, tally them by level, pull out the errors,
and measure event rates over time. No dependencies beyond PowerShell 7.1+.

## Install

Clone the repo and import the module:

```powershell
git clone https://github.com/moveeeax/pslogtrawler.git
Import-Module ./pslogtrawler/PSLogTrawler.psd1
```

## Cmdlets

| Cmdlet                | Purpose                                                        |
| --------------------- | ------------------------------------------------------------- |
| `ConvertFrom-LogLine` | Parse one line into `Timestamp` / `Level` / `Message`.        |
| `Get-LogSummary`      | Count lines by level and report the covered time range.       |
| `Select-LogError`     | Filter down to errors/warnings, by time and regex.            |
| `Measure-LogRate`     | Bucket timestamped events per minute or hour.                 |

## Supported line formats

`ConvertFrom-LogLine` recognizes two common shapes and falls back gracefully:

* **ISO-8601 bracketed** — `[2021-08-14T13:45:22] [ERROR] disk full`
  (a space instead of `T` and an unbracketed level both work)
* **syslog-ish** — `Aug 14 13:45:22 host app: ERROR disk full`
  (the year is assumed via `-DefaultYear`, current year by default)

Levels are normalized onto four buckets — `ERROR`, `WARN`, `INFO`, `DEBUG` —
so synonyms like `WARNING`, `FATAL`, `TRACE` and `NOTICE` are folded in.

## Usage

### Parse a single line

```powershell
'[2021-08-14T13:45:22] [ERROR] disk full' | ConvertFrom-LogLine

# Timestamp           Level Message
# ---------           ----- -------
# 2021-08-14 13:45:22 ERROR disk full
```

### Summarize a file

```powershell
Get-LogSummary -Path ./app.log

# Total Error Warn Info Debug First               Last
# ----- ----- ---- ---- ----- -----               ----
#   842    17   40  760    25 2021-08-14 09:00:01 2021-08-14 17:59:58
```

### Pull recent errors matching a pattern

```powershell
Get-Content app.log |
    Select-LogError -Since (Get-Date).AddHours(-1) -Pattern 'timeout|refused' -IncludeWarnings
```

### Measure event rate

```powershell
# Errors per hour across the file
Get-Content app.log | Measure-LogRate -Interval Hour -Level ERROR

# Start               Interval Count Rate
# -----               -------- ----- ----
# 2021-08-14 09:00:00 Hour        12  0.2
# 2021-08-14 10:00:00 Hour         5 0.0833
```

`Rate` is always expressed per minute, so hourly buckets divide the count by 60.

## Large files

`Get-LogSummary`, `Select-LogError` and `Measure-LogRate` stream their input a
line at a time, whether it arrives via `-Path` or the pipeline. Nothing but the
running totals is retained, so memory stays flat and a multi-gigabyte log is
fine:

```powershell
Get-LogSummary -Path ./huge.log
```

`-Pattern` on `Select-LogError` is capped at a two-second match timeout per
line, so a pattern that backtracks catastrophically fails with a clear error
rather than hanging the pipeline.

## Running the tests

Tests use [Pester 5.x](https://pester.dev):

```powershell
Invoke-Pester -Path ./Tests -Output Detailed
```

## License

MIT © 2021 Michael Tarassov
