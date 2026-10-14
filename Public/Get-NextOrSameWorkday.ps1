<#
.SYNOPSIS
Returns the date itself if it is a workday, otherwise the first workday after it.

.DESCRIPTION
The "following" business day convention: a non-working date moves forward to the next workday.

.PARAMETER Date
The date; the time of day is ignored. Today when omitted. Accepts pipeline input, also from a
property named Date.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them. When omitted, the
default calendar is used (see Set-WorkdayCalendar).

.EXAMPLE
Get-NextOrSameWorkday -Date 2026-11-20 -Calendar ./holidays/br.txt

2026-11-23: the 20th is a holiday and the 21st and 22nd are a weekend.

.EXAMPLE
Get-NextOrSameWorkday -Date 2026-11-19 -Calendar ./holidays/br.txt

2026-11-19 itself, a working Thursday.

.OUTPUTS
System.DateTime
#>
function Get-NextOrSameWorkday {
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
        try { Find-Workday $resolved (ConvertTo-CalendarDate $Date) 1 -OrSame }
        catch { $PSCmdlet.ThrowTerminatingError($_) }
    }
}
