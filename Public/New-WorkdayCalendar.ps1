<#
.SYNOPSIS
Creates a workday calendar from a holiday file, a list of dates, or both.

.DESCRIPTION
A calendar is a set of non-working weekdays (Saturday and Sunday, unless told otherwise) plus a set
of holidays. Every function in this module takes the calendar in its -Calendar parameter, which also
accepts the path of a holiday file directly; New-WorkdayCalendar is for when the file needs
adjustments (another name, another weekend, extra holidays) or when there is no file at all.

The holiday file is plain text, UTF-8:

    # Comments start with '#'. Blank lines are ignored.
    # Optional: the non-working weekdays, by English name. Saturday and Sunday when omitted.
    Saturday Sunday

    # One holiday per line, as yyyy-MM-dd; the rest of the line is a free description.
    2026-01-01  New Year's Day
    2026-11-20  Black Consciousness Day

A calendar with holidays covers the whole years they span, and asking about a date outside them is
an error: a file that lacks next year's holidays must not treat them as workdays. A calendar without
holidays covers every date.

.PARAMETER Path
The holiday file. Relative paths are relative to the current location.

.PARAMETER Holiday
Holidays to add, besides those in the file.

.PARAMETER Weekend
The non-working weekdays, replacing those declared in the file and the default Saturday and Sunday.
An empty list (@()) makes every weekday a workday.

.PARAMETER Name
The calendar name, shown in messages. The file name without extension when omitted.

.EXAMPLE
$br = New-WorkdayCalendar -Path ./holidays/br.txt
Get-NextWorkday -Date 2026-11-19 -Calendar $br

Reads the file once and uses the calendar.

.EXAMPLE
New-WorkdayCalendar -Path ./holidays/br.txt -Holiday 2026-12-24, 2026-12-31 -Name 'br-office'

The national calendar plus two days the office is closed.

.EXAMPLE
New-WorkdayCalendar -Weekend Friday, Saturday

A calendar for a Friday and Saturday weekend, without holidays.

.OUTPUTS
ElektoCalendarPosh.Calendar
#>
function New-WorkdayCalendar {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only creates an object in memory.')]
    [CmdletBinding()]
    [OutputType('ElektoCalendarPosh.Calendar')]
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [datetime[]]$Holiday = @(),

        [DayOfWeek[]]$Weekend,

        [string]$Name
    )

    try {
        $holidays = [System.Collections.Generic.List[datetime]]::new()
        $weekendDays = $script:DefaultWeekend
        $source = $null

        if ($Path) {
            $parsed = Read-CalendarFile (Get-FullPath $Path)
            $holidays.AddRange($parsed.Holidays)
            if ($parsed.Weekend.Count -gt 0) { $weekendDays = $parsed.Weekend }
            if (-not $Name) { $Name = $parsed.Name }
            $source = $parsed.Path
        }

        foreach ($day in $Holiday) { $holidays.Add($day) }
        if ($PSBoundParameters.ContainsKey('Weekend')) { $weekendDays = $Weekend }
        if (-not $Name) { $Name = 'Custom' }

        New-CalendarObject -Name $Name -Path $source -Holidays $holidays -Weekend $weekendDays
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
