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

## License

MIT © 2021 Michael Tarassov
