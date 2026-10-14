<#
.SYNOPSIS
Adds workdays to a date, or subtracts them.

.DESCRIPTION
Returns the Days-th workday after the date, or before it when Days is negative. The date itself
does not need to be a workday: one workday after a Saturday is the following Monday, and one workday
before it is the Friday (when they are workdays).

With Days 0 the date comes back unchanged, even if it is not a workday; Get-NextOrSameWorkday and
Get-PreviousOrSameWorkday move a date to a workday.

From a workday, Get-WorkdayDelta between the date and the result gives Days back.

.PARAMETER Days
How many workdays to add; negative to go back.

.PARAMETER Date
The date; the time of day is ignored. Today when omitted. Accepts pipeline input, also from a
property named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Add-Workday 5 -Date 2026-11-16 -Calendar ./holidays/br.txt

2026-11-24: the 17th, 18th, 19th, 23rd and 24th; the 20th is a holiday in Brazil.

.EXAMPLE
Add-Workday -2

Two workdays before today (D-2), in the default calendar.

.EXAMPLE
Import-Csv trades.csv | Add-Workday 2

The settlement date (D+2) of each trade, taken from the Date column.

.NOTES
An error about a date (one the calendar does not cover, for instance) stops the command. With
-ErrorAction, it follows the action chosen instead: -ErrorAction SilentlyContinue skips that date and
goes on with the next ones, and -ErrorVariable collects the errors.

.OUTPUTS
System.DateTime
#>
function Add-Workday {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int]$Days,

        [Parameter(Position = 1, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [datetime]$Date = [datetime]::Today,

        [object[]]$Calendar
    )

    begin {
        try { $resolved = Resolve-Calendar $Calendar }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }

    process {
        # The date is checked first: a date outside the calendar is then reported without an exception.
        # Not with 0 days, which gives the date back without consulting the calendar.
        $problem = $null
        try {
            $day = ConvertTo-CalendarDate $Date
            if ($Days -ne 0) { $problem = Get-CalendarCoverageError $resolved $day }
            if (-not $problem) { Add-CalendarWorkday $resolved $day $Days }
        }
        catch { $problem = $_ }
        if ($problem) { Write-CalendarError $PSCmdlet $problem }
    }
}
