<#
.SYNOPSIS
Tells whether the day before a date was a workday.

.DESCRIPTION
Looks at the previous calendar day, whatever the date itself is: true on the day after a workday.
Handy for jobs that process the previous business day, which must run on a Saturday after a working
Friday but not on a Tuesday after a holiday.

.PARAMETER Date
The date; the time of day is ignored. Today when omitted. Accepts pipeline input, also from a
property named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Test-PreviousDayIsWorkday -Date 2026-11-21 -Calendar ./holidays/br.txt

False: 2026-11-20 is a holiday in Brazil.

.EXAMPLE
if (Test-PreviousDayIsWorkday) { ./Import-YesterdayTrades.ps1 }

Imports yesterday's trades only when yesterday was a workday.

.NOTES
An error about a date (one the calendar does not cover, for instance) stops the command. With
-ErrorAction, it follows the action chosen instead: -ErrorAction SilentlyContinue skips that date and
goes on with the next ones, and -ErrorVariable collects the errors.

.OUTPUTS
System.Boolean
#>
function Test-PreviousDayIsWorkday {
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
        # The day is checked first: a day outside the calendar is then reported without an exception
        $problem = $null
        try {
            $day = (ConvertTo-CalendarDate $Date).AddDays(-1)
            $problem = Get-CalendarCoverageError $resolved $day
            if (-not $problem) { Test-CalendarDay $resolved $day }
        }
        catch { $problem = $_ }
        if ($problem) { Write-CalendarError $PSCmdlet $problem }
    }
}
