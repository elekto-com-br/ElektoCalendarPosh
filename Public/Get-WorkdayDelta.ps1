<#
.SYNOPSIS
Counts the workdays between two dates.

.DESCRIPTION
By default (the Financial mode) the count includes the start date, when it is a workday, and
excludes the end date: the Brazilian financial convention, set by Banco Central's Circular 2.456 of
1994 ("the count of workdays between two dates shall include the first and exclude the last"). From
a workday, it counts the steps of Add-Workday: Get-WorkdayDelta $d (Add-Workday 5 $d) is 5.

The result is negative when End comes before Start, with the same magnitude as the other way round.

Other modes:

- Full: includes both dates when they are workdays, like Excel's NETWORKDAYS.
- None: the same as Financial.
- StartOnNextWork, StartOnPrevWork: a non-working start moves first to the next (previous) workday.
- EndOnNextWork, EndOnPrevWork: the same for the end.
- StartAndEndOnNext, StartAndEndOnPrev: both move to the next (previous) workday.
- StartAndEndExpanding: the start moves back and the end moves forward.
- StartAndEndCollapsing: the start moves forward and the end moves back.

The modes and their results are those of the RiskSystem calendar (DeltaTerminalDayAdjust).

.PARAMETER Start
The start date; the time of day is ignored. Today when omitted.

.PARAMETER End
The end date; the time of day is ignored. Today when omitted.

Either date can come from the pipeline, or from a property of the same name: piped values go to the
one not given by name, to Start when neither is.

.PARAMETER Mode
How to count the ends: Financial (default), Full, None, StartOnNextWork, StartOnPrevWork,
EndOnNextWork, EndOnPrevWork, StartAndEndOnNext, StartAndEndOnPrev, StartAndEndExpanding or
StartAndEndCollapsing.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Get-WorkdayDelta -Start 2026-11-16 -End 2026-11-24 -Calendar ./holidays/br.txt

5: the 16th, 17th, 18th, 19th and 23rd. The 20th is a holiday and the 24th, the end, does not count.

.EXAMPLE
Get-WorkdayDelta -Start 2026-11-16 -End 2026-11-24 -Mode Full -Calendar ./holidays/br.txt

6: now the 24th counts too.

.EXAMPLE
'2026-12-31', '2027-06-30' | Get-WorkdayDelta -Start (Get-Date)

The workdays from today until each date.

.OUTPUTS
System.Int32
#>
function Get-WorkdayDelta {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [datetime]$Start = [datetime]::Today,

        [Parameter(Position = 1, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [datetime]$End = [datetime]::Today,

        [ValidateSet('Financial', 'Full', 'None', 'StartOnNextWork', 'StartOnPrevWork', 'EndOnNextWork',
            'EndOnPrevWork', 'StartAndEndOnNext', 'StartAndEndOnPrev', 'StartAndEndExpanding',
            'StartAndEndCollapsing')]
        [string]$Mode = 'Financial',

        [object[]]$Calendar
    )

    begin {
        try { $resolved = Resolve-Calendar $Calendar }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }

    process {
        try { Get-CalendarDelta $resolved (ConvertTo-CalendarDate $Start) (ConvertTo-CalendarDate $End) $Mode }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }
}
