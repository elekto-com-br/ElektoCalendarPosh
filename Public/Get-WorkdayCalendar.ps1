<#
.SYNOPSIS
Returns a calendar: the default one, or the one given.

.DESCRIPTION
Without -Calendar, returns the calendar the module uses by default (see Set-WorkdayCalendar). With
it, returns the calendar it describes, which is handy to read a holiday file once, or to combine
several, and pass the result to many calls.

The calendar shows its name, its non-working weekdays and the period it covers; its Holidays
property lists the holidays.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them.

.EXAMPLE
Get-WorkdayCalendar

Shows the calendar in effect.

.EXAMPLE
$both = Get-WorkdayCalendar ./holidays/br.txt, ./holidays/us.txt
Get-NextWorkday -Calendar $both

Combines two calendars once and reuses the result.

.EXAMPLE
(Get-WorkdayCalendar ./holidays/br.txt).Holidays | Where-Object Year -EQ 2026

Lists the holidays of 2026.

.OUTPUTS
ElektoCalendarPosh.Calendar
#>
function Get-WorkdayCalendar {
    [CmdletBinding()]
    [OutputType('ElektoCalendarPosh.Calendar')]
    param(
        [Parameter(Position = 0)]
        [object[]]$Calendar
    )

    try {
        Resolve-Calendar $Calendar
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
