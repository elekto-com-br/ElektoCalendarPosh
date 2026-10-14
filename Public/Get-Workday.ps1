<#
.SYNOPSIS
Lists the workdays between two dates.

.DESCRIPTION
Both dates are included when they are workdays. When End comes before Start, the list runs
backwards, from Start to End.

.PARAMETER Start
The first date; the time of day is ignored.

.PARAMETER End
The last date; the time of day is ignored.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Get-Workday 2026-11-16 2026-11-24 -Calendar ./holidays/br.txt

The 16th, 17th, 18th, 19th, 23rd and 24th of November 2026; the 20th is a holiday in Brazil.

.EXAMPLE
foreach ($day in Get-Workday 2026-01-01 2026-01-31) { ./Import-Prices.ps1 -Date $day }

Runs an import for each workday of January.

.OUTPUTS
System.DateTime
#>
function Get-Workday {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [datetime]$Start,

        [Parameter(Mandatory, Position = 1)]
        [datetime]$End,

        [object[]]$Calendar
    )

    try {
        $resolved = Resolve-Calendar $Calendar
        $day = ConvertTo-CalendarDate $Start
        $last = ConvertTo-CalendarDate $End
        $step = if ($day -le $last) { 1 } else { -1 }

        # Both ends first, so that a range the calendar does not fully cover fails before any output
        Assert-CalendarCoverage $resolved $day
        Assert-CalendarCoverage $resolved $last

        while ($true) {
            if (Test-CalendarDay $resolved $day) { $day }
            if ($day -eq $last) { break }
            $day = $day.AddDays($step)
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError((ConvertTo-CalendarErrorRecord $_))
    }
}
