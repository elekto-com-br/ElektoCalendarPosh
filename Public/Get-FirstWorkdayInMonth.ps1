<#
.SYNOPSIS
Returns the first workday of a month.

.DESCRIPTION
The first day of the month if it is a workday, otherwise the first workday after it. Get-NthWorkdayInMonth
gives the second, the third, and so on.

.PARAMETER Date
Any date in the month; the current month when omitted. Accepts pipeline input, also from a property
named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Get-FirstWorkdayInMonth -Date 2026-11-15 -Calendar ./holidays/br.txt

2026-11-03: November 1st is a Sunday and the 2nd is All Souls' Day.

.EXAMPLE
Get-FirstWorkdayInMonth -Date (Get-Date).AddMonths(1)

The first workday of next month.

.OUTPUTS
System.DateTime
#>
function Get-FirstWorkdayInMonth {
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
        try { Get-NthCalendarWorkdayInMonth $resolved (ConvertTo-CalendarDate $Date) 1 }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }
}
