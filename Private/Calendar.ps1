# Calendar core: building calendars and the day arithmetic every public function relies on.
#
# A calendar is a plain object (PSTypeName ElektoCalendarPosh.Calendar) holding the non-working
# weekdays and the holidays. As in RiskSystem, a calendar covers from its first holiday to its last:
# asking about a date outside them is an error, so that a file missing next year's holidays never
# silently treats them as workdays. A single holiday covers from a year before it to a year after it
# (RiskSystem goes 25 years back and 75 ahead, more than a scripting tool needs); a calendar without
# holidays covers every date.
#
# Counting never walks day by day: whole weeks are counted arithmetically and the holidays that fall
# on working weekdays are found by binary search, so the cost does not grow with the distance between
# the dates. The results are the same as those of the Calendar class of Elekto's RiskSystem.

$script:WeekdayNames = [Enum]::GetNames([DayOfWeek])
$script:DefaultWeekend = [DayOfWeek[]]@('Saturday', 'Sunday')

# Parsed holiday files, by full path, reused while the file keeps its size and write time
$script:FileCache = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)

# What Set-WorkdayCalendar stored: calendar objects and/or file paths, resolved on every use
$script:DefaultCalendar = $null

# The last joint calendar, reused while the same calendars are combined, as in a loop over dates
$script:LastJoint = $null

function ConvertTo-CalendarDate([datetime]$Date) {
    # Calendars work with dates only: midnight, and no time zone kind
    [datetime]::SpecifyKind($Date.Date, [DateTimeKind]::Unspecified)
}

function New-CalendarError {
    # An error record that scripts can catch by exception type and tell apart by its id
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only creates an object in memory.')]
    param([string]$Message, [string]$Id, [Management.Automation.ErrorCategory]$Category, [object]$Target,
        [type]$ExceptionType = [ArgumentException])

    $exception = $ExceptionType::new($Message, [Exception]$null)
    [Management.Automation.ErrorRecord]::new($exception, $Id, $Category, $Target)
}

function New-CalendarObject {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only creates an object in memory.')]
    param(
        [string]$Name,
        [string]$Path,
        [datetime[]]$Holidays = @(),
        [DayOfWeek[]]$Weekend = $script:DefaultWeekend,
        # Coverage; computed from the holidays unless given
        [Nullable[datetime]]$MinDate,
        [Nullable[datetime]]$MaxDate
    )

    $isWeekend = [bool[]]::new(7)
    foreach ($day in $Weekend) { $isWeekend[[int]$day] = $true }
    $workdaysPerWeek = @($isWeekend -eq $false).Count
    if ($workdaysPerWeek -eq 0) {
        throw (New-CalendarError "Calendar '$Name' has no working weekday: at least one day of the week must be a workday." `
                'NoWorkingWeekday' InvalidArgument $Weekend)
    }

    $holidaySet = [System.Collections.Generic.HashSet[datetime]]::new()
    foreach ($holiday in $Holidays) { [void]$holidaySet.Add([datetime]::SpecifyKind($holiday.Date, [DateTimeKind]::Unspecified)) }
    $sortedHolidays = [datetime[]]::new($holidaySet.Count)
    $holidaySet.CopyTo($sortedHolidays)
    [Array]::Sort($sortedHolidays)

    # Only the holidays on working weekdays change a count; weekends are counted apart
    $workingHolidays = [System.Collections.Generic.List[datetime]]::new()
    foreach ($holiday in $sortedHolidays) {
        if (-not $isWeekend[[int]$holiday.DayOfWeek]) { $workingHolidays.Add($holiday) }
    }

    if (-not $PSBoundParameters.ContainsKey('MinDate')) {
        if ($sortedHolidays.Count -eq 1) {
            $MinDate = $sortedHolidays[0].AddYears(-1)
            $MaxDate = $sortedHolidays[0].AddYears(1)
        }
        elseif ($sortedHolidays.Count -gt 1) {
            $MinDate = $sortedHolidays[0]
            $MaxDate = $sortedHolidays[-1]
        }
    }

    [pscustomobject]@{
        PSTypeName      = 'ElektoCalendarPosh.Calendar'
        Name            = $Name
        Weekend         = [DayOfWeek[]]@($Weekend | Sort-Object -Unique { ([int]$_ + 6) % 7 }) # Monday first
        MinDate         = $MinDate
        MaxDate         = $MaxDate
        Path            = $Path
        Holidays        = $sortedHolidays
        HolidaySet      = $holidaySet
        IsWeekend       = $isWeekend
        WorkdaysPerWeek = $workdaysPerWeek
        WorkingHolidays = $workingHolidays.ToArray()
    }
}

function Read-CalendarFile([string]$Path) {
    # Reads a holiday file: one yyyy-MM-dd date per line, the rest of the line free; '#' starts a
    # comment. Before the first holiday, lines of weekday names declare the non-working weekdays, or
    # NoWeekend, as the first line that is not a comment, declares that there are none. Returns the
    # holidays and the weekend, if declared. The parse is cached by path.
    $file = [IO.FileInfo]::new($Path)
    if (-not $file.Exists) {
        throw (New-CalendarError "Calendar file '$Path' not found." 'CalendarFileNotFound' ObjectNotFound $Path `
                ([IO.FileNotFoundException]))
    }

    $stamp = '{0}|{1}' -f $file.LastWriteTimeUtc.Ticks, $file.Length
    $cached = $null
    if ($script:FileCache.TryGetValue($file.FullName, [ref]$cached) -and $cached.Stamp -eq $stamp) {
        return $cached
    }

    $holidays = [System.Collections.Generic.List[datetime]]::new()
    $weekend = [System.Collections.Generic.List[DayOfWeek]]::new()
    $noWeekend = $false
    $lineNumber = 0
    $contentLines = 0
    # All lines at once: a lazy reader left open by an error would keep the file locked on Windows
    foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
        $lineNumber++
        $content = $line.Trim()
        if ($content.Length -eq 0 -or $content[0] -eq '#') { continue }
        $contentLines++

        # A date line, by far the most common, is told by its first ten characters and what follows them
        $date = [datetime]::MinValue
        if ($content.Length -ge 10 -and [char]::IsDigit($content[0]) -and
            [datetime]::TryParseExact($content.Substring(0, 10), 'yyyy-MM-dd', [cultureinfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None, [ref]$date) -and
            ($content.Length -eq 10 -or [char]::IsWhiteSpace($content[10]) -or ',#'.Contains($content[10]))) {
            $holidays.Add($date)
            continue
        }

        $tokens = ($content -replace '#.*$', '').Trim() -split '[\s,]+'
        $isNoWeekend = $tokens.Count -eq 1 -and $tokens[0] -eq 'NoWeekend'
        $isWeekdays = @($tokens | Where-Object { $_ -notin $script:WeekdayNames }).Count -eq 0
        $problem = $null
        if ($isNoWeekend -and $contentLines -gt 1) { $problem = 'NoWeekend must be the first line that is not a comment' }
        elseif ($isNoWeekend) { $noWeekend = $true }
        elseif ($isWeekdays -and $noWeekend) { $problem = 'weekday names cannot follow NoWeekend' }
        elseif ($isWeekdays -and $holidays.Count -gt 0) { $problem = 'the non-working weekdays must come before the first holiday' }
        elseif ($isWeekdays) { foreach ($token in $tokens) { $weekend.Add([DayOfWeek]$token) } }
        else { $problem = 'this is neither a date (yyyy-MM-dd), nor weekday names, nor NoWeekend' }

        if ($problem) {
            throw (New-CalendarError "Line $lineNumber of '$($file.FullName)': $problem. Found '$line'." `
                    'InvalidCalendarLine' InvalidData $line ([FormatException]))
        }
    }

    $parsed = [pscustomobject]@{
        Stamp           = $stamp
        Path            = $file.FullName
        Name            = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        Holidays        = $holidays.ToArray()
        Weekend         = $weekend.ToArray()
        WeekendDeclared = $noWeekend -or $weekend.Count -gt 0
        Calendar        = $null  # the calendar of the file as it is, built on first use
    }
    $script:FileCache[$file.FullName] = $parsed
    $parsed
}

function Import-CalendarFile([string]$Path) {
    # The calendar of a holiday file, built once for each version of the file
    $parsed = Read-CalendarFile $Path
    if (-not $parsed.Calendar) {
        $weekend = if ($parsed.WeekendDeclared) { $parsed.Weekend } else { $script:DefaultWeekend }
        $parsed.Calendar = New-CalendarObject -Name $parsed.Name -Path $parsed.Path -Holidays $parsed.Holidays -Weekend $weekend
    }
    $parsed.Calendar
}

function Get-FullPath([string]$Path) {
    # Relative paths are relative to the PowerShell location, not to the process directory
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Join-Calendar([object[]]$Calendars) {
    # A day is a workday only if it is a workday in every calendar: holidays and weekends add up, and
    # the coverage is what all of them cover
    $holidays = foreach ($calendar in $Calendars) { $calendar.Holidays }
    $weekend = foreach ($calendar in $Calendars) { $calendar.Weekend }
    $bounded = @($Calendars | Where-Object { $null -ne $_.MinDate })
    $minDate = $null
    $maxDate = $null
    if ($bounded.Count -gt 0) {
        $minDate = ($bounded | ForEach-Object MinDate | Sort-Object)[-1]
        $maxDate = ($bounded | ForEach-Object MaxDate | Sort-Object)[0]
        if ($minDate -gt $maxDate) {
            throw (New-CalendarError "Calendars '$($Calendars.Name -join "', '")' have no period in common." `
                    'NoCommonPeriod' InvalidArgument $Calendars)
        }
    }

    New-CalendarObject -Name ($Calendars.Name -join '+') -Holidays $holidays -Weekend $weekend `
        -MinDate $minDate -MaxDate $maxDate
}

function Get-DefaultCalendar {
    if ($script:DefaultCalendar) { return Resolve-Calendar $script:DefaultCalendar }
    $paths = @($env:WORKDAY_CALENDAR -split [IO.Path]::PathSeparator | Where-Object { $_.Trim() })
    if ($paths.Count -gt 0) { return Resolve-Calendar $paths }
    $script:WeekendsOnly
}

function Resolve-Calendar([object[]]$Calendar) {
    # Turns what the -Calendar parameter received (calendar objects, file paths, or nothing) into a
    # single calendar: the default one when nothing was given, a joint one when several were
    $items = @($Calendar | Where-Object { $null -ne $_ -and ($_ -isnot [string] -or $_.Trim()) })
    if ($items.Count -eq 0) { return Get-DefaultCalendar }

    $calendars = @(foreach ($item in $items) {
            if ($item.PSObject.TypeNames -contains 'ElektoCalendarPosh.Calendar') { $item }
            elseif ($item -is [IO.FileInfo]) { Import-CalendarFile $item.FullName }
            elseif ($item -is [System.Management.Automation.PathInfo]) { Import-CalendarFile $item.ProviderPath }
            elseif ($item -is [string]) { Import-CalendarFile (Get-FullPath $item) }
            else {
                throw (New-CalendarError "A calendar must be an object from New-WorkdayCalendar or the path of a holiday file, not '$item'." `
                        'InvalidCalendar' InvalidArgument $item)
            }
        })
    if ($calendars.Count -eq 1) { return $calendars[0] }

    $last = $script:LastJoint
    if ($last -and $last.Parts.Count -eq $calendars.Count) {
        $same = $true
        for ($i = 0; $i -lt $calendars.Count; $i++) {
            if (-not [object]::ReferenceEquals($last.Parts[$i], $calendars[$i])) { $same = $false; break }
        }
        if ($same) { return $last.Calendar }
    }
    $joint = Join-Calendar $calendars
    $script:LastJoint = @{ Parts = $calendars; Calendar = $joint }
    $joint
}

function Assert-CalendarCoverage($Calendar, [datetime]$Date) {
    if (($null -eq $Calendar.MinDate -or $Date -ge $Calendar.MinDate) -and
        ($null -eq $Calendar.MaxDate -or $Date -le $Calendar.MaxDate)) { return }

    $template = "Calendar '{0}' covers {1:yyyy-MM-dd} to {2:yyyy-MM-dd} and cannot tell whether {3:yyyy-MM-dd} is a workday."
    $message = $template -f $Calendar.Name, $Calendar.MinDate, $Calendar.MaxDate, $Date
    if ($Calendar.Path) {
        $message += if ($Date -gt $Calendar.MaxDate) {
            " Add the holidays after {0:yyyy-MM-dd} to '{1}'." -f $Calendar.MaxDate, $Calendar.Path
        }
        else {
            " Add the holidays before {0:yyyy-MM-dd} to '{1}'." -f $Calendar.MinDate, $Calendar.Path
        }
    }
    throw (New-CalendarError $message 'DateOutsideCalendar' InvalidArgument $Date ([ArgumentOutOfRangeException]))
}

function Test-CalendarDay($Calendar, [datetime]$Date) {
    Assert-CalendarCoverage $Calendar $Date
    -not $Calendar.IsWeekend[[int]$Date.DayOfWeek] -and -not $Calendar.HolidaySet.Contains($Date)
}

function Find-Workday($Calendar, [datetime]$Date, [int]$Direction, [switch]$OrSame) {
    # The first workday after Date (Direction 1) or before it (Direction -1); Date itself with OrSame
    Assert-CalendarCoverage $Calendar $Date
    if (-not $OrSame) { $Date = $Date.AddDays($Direction) }
    while (-not (Test-CalendarDay $Calendar $Date)) { $Date = $Date.AddDays($Direction) }
    $Date
}

function Find-LowerBound([datetime[]]$Sorted, [datetime]$Value) {
    # Index of the first element not less than Value (the elements are unique)
    $index = [Array]::BinarySearch($Sorted, $Value)
    if ($index -lt 0) { -bnot $index } else { $index }
}

function Measure-CalendarHoliday($Calendar, [datetime]$Start, [datetime]$End) {
    # Holidays on working weekdays in [Start, End)
    (Find-LowerBound $Calendar.WorkingHolidays $End) - (Find-LowerBound $Calendar.WorkingHolidays $Start)
}

function Measure-CalendarWorkday($Calendar, [datetime]$Start, [datetime]$End) {
    # Workdays in [Start, End), for Start <= End
    $days = ($End - $Start).Days
    if ($days -le 0) { return 0 }
    Assert-CalendarCoverage $Calendar $Start
    Assert-CalendarCoverage $Calendar $End.AddDays(-1)

    $weeks = [int][Math]::Floor($days / 7)
    $count = $weeks * $Calendar.WorkdaysPerWeek
    for ($day = $Start.AddDays(7 * $weeks); $day -lt $End; $day = $day.AddDays(1)) {
        if (-not $Calendar.IsWeekend[[int]$day.DayOfWeek]) { $count++ }
    }
    $count - (Measure-CalendarHoliday $Calendar $Start $End)
}

function Step-WorkingWeekday($Calendar, [datetime]$Date, [int]$Count) {
    # The Count-th working weekday after Date (before it, when negative), ignoring holidays
    $direction = [Math]::Sign($Count)
    $left = [Math]::Abs($Count)
    $weeks = [int][Math]::Floor(($left - 1) / $Calendar.WorkdaysPerWeek)
    $Date = $Date.AddDays(7 * $weeks * $direction)
    $left -= $weeks * $Calendar.WorkdaysPerWeek
    while ($left -gt 0) {
        $Date = $Date.AddDays($direction)
        if (-not $Calendar.IsWeekend[[int]$Date.DayOfWeek]) { $left-- }
    }
    $Date
}

function Add-CalendarWorkday($Calendar, [datetime]$Date, [int]$Days) {
    # The Days-th workday after Date (before it, when negative); Date itself when Days is 0, workday
    # or not. As RiskSystem's Calendar.AddWorkDays.
    if ($Days -eq 0) { return $Date }
    Assert-CalendarCoverage $Calendar $Date

    $direction = [Math]::Sign($Days)
    $pending = [Math]::Abs($Days)
    while ($pending -gt 0) {
        $target = Step-WorkingWeekday $Calendar $Date ($pending * $direction)
        Assert-CalendarCoverage $Calendar $target
        # The holidays stepped over did not count: go on for as many days as they were
        $pending = if ($direction -gt 0) {
            Measure-CalendarHoliday $Calendar $Date.AddDays(1) $target.AddDays(1)
        }
        else {
            Measure-CalendarHoliday $Calendar $target $Date
        }
        $Date = $target
    }
    $Date
}

function Get-CalendarPeriodDelta($Calendar, [datetime]$From, [datetime]$To) {
    # Workdays in (From, To]; negative, and in (To, From], when To comes first. The difference of
    # RiskSystem's cumulative workday counts at To and at From.
    if ($From -le $To) { Measure-CalendarWorkday $Calendar $From.AddDays(1) $To.AddDays(1) }
    else { -(Measure-CalendarWorkday $Calendar $To.AddDays(1) $From.AddDays(1)) }
}

function Get-CalendarDelta($Calendar, [datetime]$Start, [datetime]$End, [string]$Mode) {
    # Workdays between Start and End under Mode, as RiskSystem's Calendar.GetDeltaWorkDays
    if ($Start -eq $End) { return [int]($Mode -eq 'Full' -and (Test-CalendarDay $Calendar $Start)) }
    if ($Start -gt $End) { return -(Get-CalendarDelta $Calendar $End $Start $Mode) }

    switch ($Mode) {
        'StartOnNextWork' { $Start = Find-Workday $Calendar $Start 1 -OrSame }
        'StartOnPrevWork' { $Start = Find-Workday $Calendar $Start -1 -OrSame }
        'EndOnNextWork' { $End = Find-Workday $Calendar $End 1 -OrSame }
        'EndOnPrevWork' { $End = Find-Workday $Calendar $End -1 -OrSame }
        'StartAndEndOnNext' {
            $Start = Find-Workday $Calendar $Start 1 -OrSame
            $End = Find-Workday $Calendar $End 1 -OrSame
        }
        'StartAndEndOnPrev' {
            $Start = Find-Workday $Calendar $Start -1 -OrSame
            $End = Find-Workday $Calendar $End -1 -OrSame
        }
        'StartAndEndExpanding' {
            $Start = Find-Workday $Calendar $Start -1 -OrSame
            $End = Find-Workday $Calendar $End 1 -OrSame
        }
        'StartAndEndCollapsing' {
            $Start = Find-Workday $Calendar $Start 1 -OrSame
            $End = Find-Workday $Calendar $End -1 -OrSame
        }
    }
    if ($Start -eq $End) { return [int]($Mode -eq 'Full' -and (Test-CalendarDay $Calendar $Start)) }

    $startIsWorkday = Test-CalendarDay $Calendar $Start
    $endIsWorkday = Test-CalendarDay $Calendar $End
    $delta = Get-CalendarPeriodDelta $Calendar $Start $End

    # (Start, End] becomes [Start, End], or [Start, End) in every mode but Full. RiskSystem has one more
    # case, delta 0 with a working Start and a non-working End, already covered by the last one here.
    if ($Mode -eq 'Full') {
        if ($startIsWorkday) { $delta++ }
    }
    elseif (-not $startIsWorkday -and $endIsWorkday) { $delta-- }
    elseif ($startIsWorkday -and -not $endIsWorkday) { $delta++ }
    $delta
}

function Get-AdjustedDate($Calendar, [datetime]$Date, [string]$Adjust) {
    # Moves a non-working Date to a workday under one of the usual business day conventions
    switch ($Adjust) {
        'Following' { Find-Workday $Calendar $Date 1 -OrSame }
        'Preceding' { Find-Workday $Calendar $Date -1 -OrSame }
        'ModifiedFollowing' {
            $adjusted = Find-Workday $Calendar $Date 1 -OrSame
            if ($adjusted.Month -ne $Date.Month) { $adjusted = Find-Workday $Calendar $adjusted -1 }
            $adjusted
        }
        'ModifiedPreceding' {
            $adjusted = Find-Workday $Calendar $Date -1 -OrSame
            if ($adjusted.Month -ne $Date.Month) { $adjusted = Find-Workday $Calendar $adjusted 1 }
            $adjusted
        }
        default { $Date }
    }
}

function Get-NthCalendarWorkdayInMonth($Calendar, [datetime]$Date, [int]$Nth) {
    # The Nth workday of Date's month, counting from its last one when Nth is negative. A month with
    # fewer workdays gives its last one (its first, from the end), so that a task meant for the end of
    # the month still runs. As RiskSystem's GetNthWorkingDay and GetNthToLastWorkingDay, and with
    # GetWorkingMonthHead and GetWorkingMonthTail for 1 and -1.
    $first = [datetime]::new($Date.Year, $Date.Month, 1)
    $last = $first.AddMonths(1).AddDays(-1)
    if ($Nth -gt 0) {
        $head = Find-Workday $Calendar $first 1 -OrSame
        if ($Nth -eq 1) { return $head }
        $candidate = Add-CalendarWorkday $Calendar $head ($Nth - 1)
        if ($candidate -gt $last) { return Find-Workday $Calendar $last -1 -OrSame }
        return $candidate
    }

    $tail = Find-Workday $Calendar $last -1 -OrSame
    if ($Nth -eq -1) { return $tail }
    $candidate = Add-CalendarWorkday $Calendar $tail ($Nth + 1)
    if ($candidate -lt $first) { return Find-Workday $Calendar $first 1 -OrSame }
    $candidate
}

$script:WeekendsOnly = New-CalendarObject -Name 'Weekends'

# Format-List shows what matters too (the table view is in the format file); the lookup structures stay out of sight
Update-TypeData -TypeName 'ElektoCalendarPosh.Calendar' -DefaultDisplayPropertySet Name, Weekend, MinDate, MaxDate, Path -Force
