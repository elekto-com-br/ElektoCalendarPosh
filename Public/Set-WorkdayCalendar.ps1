<#
.SYNOPSIS
Sets the calendar the module uses when a function is called without -Calendar.

.DESCRIPTION
Without -Calendar, every function uses the default calendar, which is, in order of precedence:

1. The calendar set by Set-WorkdayCalendar in the current session.
2. The holiday file named by the WORKDAY_CALENDAR environment variable (several files may be given,
   separated by ';' on Windows and ':' elsewhere, and are combined).
3. Saturday and Sunday as the only non-working days.

Calling Set-WorkdayCalendar without a calendar goes back to the second and third options.

A holiday file set here is read again whenever it changes, so a long-running script always sees the
current version.

.PARAMETER Calendar
The calendar: an object from New-WorkdayCalendar, the path of a holiday file, or several of them,
combined so that a day is a workday only if it is a workday in all of them.

.PARAMETER PassThru
Returns the calendar now in effect.

.EXAMPLE
Set-WorkdayCalendar ./holidays/br.txt
Add-Workday 2

At the top of a script: from then on, every function uses the Brazilian calendar.

.EXAMPLE
Set-WorkdayCalendar ./holidays/br.txt, ./holidays/us.txt

A day is a workday only if it is a workday both in Brazil and in the United States.

.EXAMPLE
Set-WorkdayCalendar

Back to WORKDAY_CALENDAR or, without it, to Saturday and Sunday only.

.OUTPUTS
ElektoCalendarPosh.Calendar, with -PassThru.
#>
function Set-WorkdayCalendar {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('ElektoCalendarPosh.Calendar')]
    param(
        [Parameter(Position = 0)]
        [object[]]$Calendar,

        [switch]$PassThru
    )

    try {
        # Paths become absolute now, so that a later change of location does not change the calendar
        $items = @(foreach ($item in $Calendar) { if ($item -is [string]) { Get-FullPath $item } else { $item } })

        # Resolving now reports a missing or malformed file here, not on first use
        $target = if ($items.Count -gt 0) { "calendar '$((Resolve-Calendar $items).Name)'" } else { 'the built-in default' }
        if ($PSCmdlet.ShouldProcess('default workday calendar', "Set to $target")) {
            $script:DefaultCalendar = if ($items.Count -gt 0) { $items } else { $null }
        }

        if ($PassThru) { Get-DefaultCalendar }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
