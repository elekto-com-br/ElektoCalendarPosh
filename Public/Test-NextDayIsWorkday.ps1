<#
.SYNOPSIS
Tells whether the day after a date is a workday.

.DESCRIPTION
Looks at the next calendar day, whatever the date itself is: true on the eve of a workday. Handy for
jobs that prepare the next business day, which must run on a Sunday before a working Monday but not
on a Thursday before a holiday.

.PARAMETER Date
The date; the time of day is ignored. Today when omitted. Accepts pipeline input, also from a
property named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Test-NextDayIsWorkday -Date 2026-11-19 -Calendar ./holidays/br.txt

False: 2026-11-20 is a holiday in Brazil.

.EXAMPLE
if (Test-NextDayIsWorkday) { ./Prepare-NextDay.ps1 }

Prepares tomorrow only when tomorrow is a workday.

.OUTPUTS
System.Boolean
#>
function Test-NextDayIsWorkday {
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
        try { Test-CalendarDay $resolved (ConvertTo-CalendarDate $Date).AddDays(1) }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }
}
