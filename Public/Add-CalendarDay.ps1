<#
.SYNOPSIS
Adds calendar days to a date and, optionally, moves the result to a workday.

.DESCRIPTION
The days are plain calendar days. When the result is not a workday, -Adjust says what to do with it,
following the usual business day conventions:

- None (default): keep it.
- Following: move it to the next workday.
- Preceding: move it to the previous workday.
- ModifiedFollowing: move it to the next workday, unless that falls in another month; then to the
  previous workday.
- ModifiedPreceding: move it to the previous workday, unless that falls in another month; then to
  the next workday.

With Days 0, it just applies the convention to the date.

.PARAMETER Days
How many calendar days to add; negative to go back.

.PARAMETER Date
The date; the time of day is ignored. Today when omitted. Accepts pipeline input, also from a
property named Date.

.PARAMETER Adjust
What to do when the result is not a workday: None, Following, Preceding, ModifiedFollowing or
ModifiedPreceding. None when omitted.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Add-CalendarDay 30 -Date 2026-10-01 -Adjust Following -Calendar ./holidays/br.txt

2026-11-03: thirty days later is Saturday, 2026-10-31; then come a Sunday and All Souls' Day.

.EXAMPLE
Add-CalendarDay 30 -Date 2026-10-01 -Adjust ModifiedFollowing -Calendar ./holidays/br.txt

2026-10-30: the following workday is in November, so the result goes back to the last workday of
October.

.EXAMPLE
Add-CalendarDay 0 -Date 2026-11-01 -Adjust Preceding -Calendar ./holidays/br.txt

2026-10-30: moves a Sunday back to the previous workday.

.OUTPUTS
System.DateTime
#>
function Add-CalendarDay {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int]$Days,

        [Parameter(Position = 1, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [datetime]$Date = [datetime]::Today,

        [ValidateSet('None', 'Following', 'Preceding', 'ModifiedFollowing', 'ModifiedPreceding')]
        [string]$Adjust = 'None',

        [object[]]$Calendar
    )

    begin {
        try { $resolved = Resolve-Calendar $Calendar }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }

    process {
        try { Get-AdjustedDate $resolved (ConvertTo-CalendarDate $Date).AddDays($Days) $Adjust }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }
}
