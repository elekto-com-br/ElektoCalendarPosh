<#
.SYNOPSIS
Returns the last workday of a month.

.DESCRIPTION
The last day of the month if it is a workday, otherwise the last workday before it.
Get-NthWorkdayInMonth with a negative position gives the second to last, the third to last, and so
on.

.PARAMETER Date
Any date in the month; the current month when omitted. Accepts pipeline input, also from a property
named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Get-LastWorkdayInMonth -Date 2026-10-14 -Calendar ./holidays/br.txt

2026-10-30: October 31st, 2026 is a Saturday.

.EXAMPLE
if ((Get-LastWorkdayInMonth) -eq [datetime]::Today) { ./Close-Month.ps1 }

Closes the month on its last workday.

.NOTES
An error about a date (one the calendar does not cover, for instance) stops the command. With
-ErrorAction, it follows the action chosen instead: -ErrorAction SilentlyContinue skips that date and
goes on with the next ones, and -ErrorVariable collects the errors.

.OUTPUTS
System.DateTime
#>
function Get-LastWorkdayInMonth {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [datetime]$Date = [datetime]::Today,

        [object[]]$Calendar
    )

    begin {
        try { $resolved = Resolve-Calendar $Calendar }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }

    process {
        # The last day of the month is checked first: one outside the calendar is then reported
        # without an exception
        $problem = $null
        try {
            $day = ConvertTo-CalendarDate $Date
            $problem = Get-CalendarCoverageError $resolved ([datetime]::new($day.Year, $day.Month, 1).AddMonths(1).AddDays(-1))
            if (-not $problem) { Get-NthCalendarWorkdayInMonth $resolved $day -1 }
        }
        catch { $problem = $_ }
        if ($problem) { Write-CalendarError $PSCmdlet $problem }
    }
}
