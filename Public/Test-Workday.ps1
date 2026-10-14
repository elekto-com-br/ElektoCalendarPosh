<#
.SYNOPSIS
Tells whether a date is a workday.

.DESCRIPTION
A date is a workday when it is neither one of the calendar's non-working weekdays (Saturday and
Sunday, unless the calendar says otherwise) nor one of its holidays.

.PARAMETER Date
The date; the time of day is ignored. Today when omitted. Accepts pipeline input, also from a
property named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Test-Workday -Date 2026-11-20 -Calendar ./holidays/br.txt

False when br.txt lists 2026-11-20 (Black Consciousness Day) as a holiday.

.EXAMPLE
if (Test-Workday) { ./Send-DailyReport.ps1 }

Sends the report only on workdays of the default calendar.

.EXAMPLE
'2026-11-19', '2026-11-20', '2026-11-21' | Test-Workday -Calendar ./holidays/br.txt

True, False, False: a Thursday, a holiday and a Saturday.

.NOTES
An error about a date (one the calendar does not cover, for instance) stops the command. With
-ErrorAction, it follows the action chosen instead: -ErrorAction SilentlyContinue skips that date and
goes on with the next ones, and -ErrorVariable collects the errors.

.OUTPUTS
System.Boolean
#>
function Test-Workday {
    [CmdletBinding()]
    [OutputType([bool])]
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
        # The date is checked first: a date outside the calendar is then reported without an exception
        $problem = $null
        try {
            $day = ConvertTo-CalendarDate $Date
            $problem = Get-CalendarCoverageError $resolved $day
            if (-not $problem) { Test-CalendarDay $resolved $day }
        }
        catch { $problem = $_ }
        if ($problem) { Write-CalendarError $PSCmdlet $problem }
    }
}
