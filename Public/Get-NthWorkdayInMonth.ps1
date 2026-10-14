<#
.SYNOPSIS
Returns the Nth workday of a month, counting from its start or from its end.

.DESCRIPTION
1 is the first workday of the month, 2 the second, and so on; -1 is the last workday, -2 the second
to last. Returns nothing when the month has fewer workdays than asked for, so that comparing the
result with a date is simply false.

.PARAMETER Nth
The position: 1 to 31 from the start of the month, -1 to -31 from its end.

.PARAMETER Date
Any date in the month; the current month when omitted. Accepts pipeline input, also from a property
named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Get-NthWorkdayInMonth 5 -Date 2026-11-01 -Calendar ./holidays/br.txt

2026-11-09: the workdays of November 2026 start on the 3rd, after a Sunday and All Souls' Day.

.EXAMPLE
Get-NthWorkdayInMonth -2 -Date 2026-11-01 -Calendar ./holidays/br.txt

2026-11-27, the second to last workday of November 2026.

.EXAMPLE
if ((Get-NthWorkdayInMonth 3) -eq [datetime]::Today) { ./Send-MonthlyReport.ps1 }

Sends the report on the third workday of each month.

.OUTPUTS
System.DateTime
#>
function Get-NthWorkdayInMonth {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(-31, 31)]
        [ValidateScript({ $_ -ne 0 }, ErrorMessage = 'Nth cannot be 0: 1 is the first workday of the month and -1 the last.')]
        [int]$Nth,

        [Parameter(Position = 1, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [datetime]$Date = [datetime]::Today,

        [object[]]$Calendar
    )

    begin {
        try { $resolved = Resolve-Calendar $Calendar }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }

    process {
        try { Get-NthCalendarWorkdayInMonth $resolved (ConvertTo-CalendarDate $Date) $Nth }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }
}
