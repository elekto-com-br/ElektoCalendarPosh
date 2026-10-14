# ElektoCalendarPosh

[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/ElektoCalendarPosh)](https://www.powershellgallery.com/packages/ElektoCalendarPosh)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/ElektoCalendarPosh)](https://www.powershellgallery.com/packages/ElektoCalendarPosh)
[![License](https://img.shields.io/github/license/elekto-com-br/ElektoCalendarPosh)](LICENSE)

A lightweight PowerShell module for business day (workday) arithmetic, driven by plain-text holiday calendars. **Zero dependencies**, one ISO date per line, and the answers scripts need: is today a workday, what is the next one, what is D+2, how many workdays until a date.

## Why ElektoCalendarPosh?

- **Simple**: commands named after the questions (`Test-Workday`, `Get-NextWorkday`, `Add-Workday`, `Get-WorkdayDelta`), today and the default calendar when nothing is said
- **Plain-text calendars**: one `yyyy-MM-dd` date per line, with comments and descriptions; compatible with the `.cal` files of [bizdays](https://github.com/wilsonfreitas/python-bizdays)
- **Safe**: a calendar refuses dates outside the years its holidays cover, instead of treating a missing holiday as a workday
- **Fast**: adding and counting workdays is arithmetic, whatever the distance between the dates
- **Lightweight**: no dependencies, PowerShell 7.2+, Windows, Linux and macOS

## Installation

### From PowerShell Gallery (Recommended)

```powershell
Install-Module -Name ElektoCalendarPosh
```

### From Source

```powershell
git clone https://github.com/elekto-com-br/ElektoCalendarPosh.git
Import-Module ./ElektoCalendarPosh/ElektoCalendarPosh.psd1
```

## Quick Start

Without any setup, Saturday and Sunday are the only non-working days:

```powershell
Test-Workday                      # is today a workday?
Get-NextWorkday                   # the first workday after today
Add-Workday 2                     # D+2
Get-WorkdayDelta -End 2026-12-31  # workdays from today until the end of the year
```

With a holiday file, for a single call or for the whole script:

```powershell
Get-NextWorkday -Date 2026-11-19 -Calendar ./holidays/br.txt   # 2026-11-23: the 20th is a holiday

Set-WorkdayCalendar ./holidays/br.txt   # from now on, the default calendar
Get-LastWorkdayInMonth                  # the last workday of this month, in Brazil
```

The repository has an example file with the Brazilian national holidays from 2001 to 2099, [Examples/br-national.txt](Examples/br-national.txt); check it against the official list before relying on it.

## Calendars

### Holiday Files

A holiday file is plain UTF-8 text:

```text
# Comments start with '#'. Blank lines are ignored.

# Optional: the non-working weekdays, by English name. Saturday and Sunday when omitted.
Saturday Sunday

# One holiday per line, as yyyy-MM-dd; the rest of the line is a free description.
2026-01-01  New Year's Day
2026-02-16  Carnival Monday
2026-11-20  Black Consciousness Day
```

- The weekday names can share a line or take one each, and are case-insensitive.
- Any other line is an error that names the file and the line: a typo never silently drops a holiday.
- A bizdays `.cal` file is a valid holiday file. Note that a file declaring no weekday gets Saturday and Sunday here, while bizdays would take every weekday as a business day.
- The calendar is named after the file (`br` for `br.txt`).
- A file is read once and read again only when it changes, so long-running scripts and schedulers can pass the path on every call and still pick up a new version of the file.

### Coverage

A calendar with holidays covers the whole years they span: a file listing holidays from 2001 to 2099 covers 2001-01-01 to 2099-12-31. Asking about a date outside that period is an error (`ArgumentOutOfRangeException`, error id `DateOutsideCalendar`), because the calendar cannot know the holidays of a year it does not list:

```text
Get-NextWorkday: Calendar 'br' covers 2001-01-01 to 2099-12-31 and cannot tell whether 2100-01-01 is a workday.
Add the holidays of 2100 to '/srv/holidays/br.txt'.
```

A calendar without holidays (the default one, or one with only weekdays declared) covers every date.

### The Default Calendar

Every command takes a `-Calendar` parameter. When it is omitted, the default calendar is, in order of precedence:

1. The calendar set by `Set-WorkdayCalendar` in the current session.
2. The holiday file named by the `WORKDAY_CALENDAR` environment variable.
3. Saturday and Sunday as the only non-working days.

The environment variable configures every script on a machine, or in a CI/CD pipeline, without touching them:

```powershell
$env:WORKDAY_CALENDAR = '/srv/holidays/br.txt'
```

### The `-Calendar` Parameter

It accepts a calendar object, the path of a holiday file, or several of them. With several, a day is a workday only if it is a workday in all of them, which is what a settlement in two markets needs:

```powershell
Add-Workday 2 -Calendar ./holidays/br.txt, ./holidays/us.txt
```

`New-WorkdayCalendar` builds a calendar object when the file needs adjustments, or when there is no file:

```powershell
$office = New-WorkdayCalendar ./holidays/br.txt -Holiday 2026-12-24, 2026-12-31 -Name office
$gulf = New-WorkdayCalendar -Weekend Friday, Saturday
$always = New-WorkdayCalendar -Weekend @()   # every day is a workday
```

`Get-WorkdayCalendar` shows the calendar in effect, or the one given:

```powershell
PS> Get-WorkdayCalendar ./holidays/br.txt

Name Weekend          MinDate    MaxDate    Holidays Path
---- -------          -------    -------    -------- ----
br   Saturday, Sunday 2001-01-01 2099-12-31     1263 /srv/holidays/br.txt
```

## Commands

| Command | Returns |
|---------|---------|
| `Test-Workday` | Whether the date is a workday |
| `Test-NextDayIsWorkday` | Whether the day after the date is a workday (the eve of a workday) |
| `Test-PreviousDayIsWorkday` | Whether the day before the date was a workday |
| `Get-NextWorkday` | The first workday after the date |
| `Get-NextOrSameWorkday` | The date itself if it is a workday, otherwise the next one |
| `Get-PreviousWorkday` | The last workday before the date |
| `Get-PreviousOrSameWorkday` | The date itself if it is a workday, otherwise the previous one |
| `Add-Workday` | The Nth workday after the date (before it, when negative) |
| `Add-CalendarDay` | The date plus N calendar days, optionally moved to a workday |
| `Get-WorkdayDelta` | The number of workdays between two dates |
| `Get-FirstWorkdayInMonth` | The first workday of the month |
| `Get-LastWorkdayInMonth` | The last workday of the month |
| `Get-NthWorkdayInMonth` | The Nth workday of the month, from its start or, when negative, from its end |
| `Get-Workday` | The workdays between two dates |
| `New-WorkdayCalendar` | A calendar from a file, a list of dates, or both |
| `Get-WorkdayCalendar` | The default calendar, or the one given |
| `Set-WorkdayCalendar` | Sets the default calendar |

The date parameters ignore the time of day and default to today; most commands take dates from the pipeline too:

```powershell
Import-Csv trades.csv | Add-Workday 2     # the D+2 of each trade, from its Date column
```

Every command has full help: `Get-Help Add-Workday -Full`.

## Counting Workdays

`Get-WorkdayDelta` counts, by default, the start date (when it is a workday) and not the end date. That is the Brazilian financial convention, set by Banco Central's Circular 2.456/1994, and the inverse of `Add-Workday`: from a workday `$d`, `Get-WorkdayDelta $d (Add-Workday 5 $d)` is 5. When the end comes before the start, the result is negative.

| `-Mode` | Counts |
|---------|--------|
| `Financial` (default), `None` | The start, not the end |
| `Full` | Both ends, like Excel's `NETWORKDAYS` |
| `StartOnNextWork`, `StartOnPrevWork` | As `Financial`, after moving a non-working start to the next (previous) workday |
| `EndOnNextWork`, `EndOnPrevWork` | The same, moving the end |
| `StartAndEndOnNext`, `StartAndEndOnPrev` | The same, moving both |
| `StartAndEndExpanding` | The same, moving the start back and the end forward |
| `StartAndEndCollapsing` | The same, moving the start forward and the end back |

## Business Day Conventions

`Add-CalendarDay` adds calendar days and, with `-Adjust`, moves a result that is not a workday:

| `-Adjust` | A non-working result moves to |
|-----------|-------------------------------|
| `None` (default) | Nowhere: it stays |
| `Following` | The next workday |
| `Preceding` | The previous workday |
| `ModifiedFollowing` | The next workday, unless it falls in another month; then the previous one |
| `ModifiedPreceding` | The previous workday, unless it falls in another month; then the next one |

```powershell
Add-CalendarDay 30 -Date 2026-10-01 -Adjust ModifiedFollowing -Calendar ./holidays/br.txt   # 2026-10-30
```

## Using It from Other Modules

The module is meant to be the calendar engine of other scripts and modules, which then need to know nothing about holidays or weekends. A scheduler, for instance, maps its conditions straight onto it:

| Run the job... | Condition |
|----------------|-----------|
| on workdays | `Test-Workday -Date $day -Calendar $calendars` |
| on the eve of a workday | `Test-NextDayIsWorkday -Date $day -Calendar $calendars` |
| on the day after a workday | `Test-PreviousDayIsWorkday -Date $day -Calendar $calendars` |
| on the Nth workday of the month | `(Get-NthWorkdayInMonth $n -Date $day -Calendar $calendars) -eq $day` |

## Correspondence with the RiskSystem Calendar

The results are those of the `Calendar` class of Elekto's RiskSystem:

| RiskSystem `ICalendar` | ElektoCalendarPosh |
|------------------------|--------------------|
| `IsWorkday` | `Test-Workday` |
| `GetNextWorkday`, `GetNextOrSameWorkday` | `Get-NextWorkday`, `Get-NextOrSameWorkday` |
| `GetPrevWorkday`, `GetPrevOrSameWorkday` | `Get-PreviousWorkday`, `Get-PreviousOrSameWorkday` |
| `AddWorkDays` | `Add-Workday` |
| `AddActualDays` with `FinalDateAdjust` | `Add-CalendarDay -Adjust` (adds `Preceding` and `ModifiedPreceding`) |
| `GetDeltaWorkDays` with `DeltaTerminalDayAdjust` | `Get-WorkdayDelta -Mode` |
| `GetWorkingMonthHead`, `GetWorkingMonthTail` | `Get-FirstWorkdayInMonth`, `Get-LastWorkdayInMonth` |
| `GetWorkDates` with `Full` | `Get-Workday` |
| `UnionWith` | Several calendars in `-Calendar` |

One difference: a RiskSystem calendar covers from its first to its last holiday, while here it covers their whole years.

## Development

The source has one file per function, under `Public` and `Private`. `Build.ps1` parses every script, validates the manifest, runs PSScriptAnalyzer and the [Pester](https://pester.dev) tests (when installed) and stages the package in `./out`, with all the functions in a single `.psm1`, which loads faster:

```powershell
Install-PSResource Pester, PSScriptAnalyzer
./Build.ps1
```

The tests alone: `Invoke-Pester ./Tests`.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

**JP Negri** - [Elekto Produtos Financeiros](https://github.com/elekto-com-br)
