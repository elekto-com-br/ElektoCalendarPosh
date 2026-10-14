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
        try { Get-NthCalendarWorkdayInMonth $resolved (ConvertTo-CalendarDate $Date) -1 }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }
}
