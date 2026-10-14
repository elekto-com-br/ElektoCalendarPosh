<#
.SYNOPSIS
Returns the date itself if it is a workday, otherwise the last workday before it.

.DESCRIPTION
The "preceding" business day convention: a non-working date moves back to the previous workday.

.PARAMETER Date
The date; the time of day is ignored. Today when omitted. Accepts pipeline input, also from a
property named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Get-PreviousOrSameWorkday -Date 2026-11-22 -Calendar ./holidays/br.txt

2026-11-19: the 22nd and 21st are a weekend and the 20th is a holiday in Brazil.

.EXAMPLE
Get-PreviousOrSameWorkday

Today if it is a workday, otherwise the last workday before it.

.NOTES
An error about a date (one the calendar does not cover, for instance) stops the command. With
-ErrorAction, it follows the action chosen instead: -ErrorAction SilentlyContinue skips that date and
goes on with the next ones, and -ErrorVariable collects the errors.

.OUTPUTS
System.DateTime
#>
function Get-PreviousOrSameWorkday {
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
        # The date is checked first: a date outside the calendar is then reported without an exception
        $problem = $null
        try {
            $day = ConvertTo-CalendarDate $Date
            $problem = Get-CalendarCoverageError $resolved $day
            if (-not $problem) { Find-Workday $resolved $day -1 -OrSame }
        }
        catch { $problem = $_ }
        if ($problem) { Write-CalendarError $PSCmdlet $problem }
    }
}
