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
        try { Find-Workday $resolved (ConvertTo-CalendarDate $Date) -1 -OrSame }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }
}
