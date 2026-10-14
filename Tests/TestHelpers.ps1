# Shared by the test files: dot-source it in BeforeAll.

$ModuleManifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'ElektoCalendarPosh.psd1'

$DeltaModes = @('Financial', 'Full', 'None', 'StartOnNextWork', 'StartOnPrevWork', 'EndOnNextWork', 'EndOnPrevWork',
    'StartAndEndOnNext', 'StartAndEndOnPrev', 'StartAndEndExpanding', 'StartAndEndCollapsing')

$AdjustConventions = @('None', 'Following', 'Preceding', 'ModifiedFollowing', 'ModifiedPreceding')

function New-TestCalendarFile {
    # Writes a holiday file in the test drive and returns its path
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Content = '')
    $path = Join-Path $TestDrive $Name
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $Content, [Text.UTF8Encoding]::new($false))
    $path
}

function Get-EasterSunday([int]$Year) {
    # Anonymous Gregorian algorithm, as in RiskSystem's perpetual calendars
    $a = $Year % 19
    $b = [Math]::Floor($Year / 100)
    $c = $Year % 100
    $d = [Math]::Floor($b / 4)
    $e = $b % 4
    $g = [Math]::Floor((8 * $b + 13) / 25)
    $h = (19 * $a + $b - $d - $g + 15) % 30
    $i = [Math]::Floor($c / 4)
    $k = $c % 4
    $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7
    $m = [Math]::Floor(($a + 11 * $h + 19 * $l) / 433)
    $n = [Math]::Floor(($h + $l - 7 * $m + 90) / 25)
    $p = ($h + $l - 7 * $m + 33 * $n + 19) % 32
    [datetime]::new($Year, $n, $p)
}

function Get-BrazilianHoliday {
    # The holidays of RiskSystem's perpetual calendars: br-BC (national, for CDI and Selic) and, with
    # -Exchange, the BM&F one, which adds Sao Paulo's holidays and the last days of the year
    param([int]$From, [int]$To, [switch]$Exchange)
    for ($year = $From; $year -le $To; $year++) {
        $easter = Get-EasterSunday $year
        $easter.AddDays(-48)                    # Carnival Monday
        $easter.AddDays(-47)                    # Carnival Tuesday
        $easter.AddDays(-2)                     # Good Friday
        if ($year -ge 1986 -and $year -le 1999) { $easter.AddDays(-3) } # Holy Thursday
        $easter.AddDays(60)                     # Corpus Christi
        foreach ($monthDay in '01-01', '04-21', '05-01', '09-07', '10-12', '11-02', '11-15', '12-25') {
            [datetime]"$year-$monthDay"
        }
        if ($year -ge 2024) { [datetime]"$year-11-20" }
        if ($year -eq 1996) { [datetime]'1996-10-03' }
        if ($Exchange) {
            foreach ($monthDay in '01-25', '07-09', '11-20', '12-24', '12-31') { [datetime]"$year-$monthDay" }
        }
    }
}

# A literal port of RiskSystem's Calendar class (lib/PRA/Calendars/Calendar.cs): cumulative workday
# counts over the whole range, and day-by-day stepping. Slow and plain, it is the reference the
# module is checked against.

function New-OracleCalendar {
    param([datetime[]]$Holidays, [DayOfWeek[]]$Weekend, [datetime]$MinDate, [datetime]$MaxDate)

    $holidaySet = [System.Collections.Generic.HashSet[datetime]]::new()
    foreach ($holiday in $Holidays) { [void]$holidaySet.Add($holiday.Date) }
    $weekendSet = [System.Collections.Generic.HashSet[DayOfWeek]]::new()
    foreach ($day in $Weekend) { [void]$weekendSet.Add($day) }

    $size = ($MaxDate - $MinDate).Days + 1
    $period = [int[]]::new($size)
    $count = 0
    for ($i = 0; $i -lt $size; $i++) {
        $date = $MinDate.AddDays($i)
        if (-not $weekendSet.Contains($date.DayOfWeek) -and -not $holidaySet.Contains($date)) { $count++ }
        $period[$i] = $count
    }

    [pscustomobject]@{
        Holidays = $holidaySet
        Weekend  = $weekendSet
        MinDate  = $MinDate
        MaxDate  = $MaxDate
        Period   = $period
    }
}

function Test-OracleWorkday($Oracle, [datetime]$Date) {
    if ($Date -lt $Oracle.MinDate -or $Date -gt $Oracle.MaxDate) { throw "Out of range: $Date" }
    -not $Oracle.Weekend.Contains($Date.DayOfWeek) -and -not $Oracle.Holidays.Contains($Date)
}

function Get-OracleNextWorkday($Oracle, [datetime]$Date) {
    if ($Date -lt $Oracle.MinDate -or $Date -gt $Oracle.MaxDate) { throw "Out of range: $Date" }
    $Date = $Date.AddDays(1)
    while (-not (Test-OracleWorkday $Oracle $Date)) { $Date = $Date.AddDays(1) }
    $Date
}

function Get-OraclePreviousWorkday($Oracle, [datetime]$Date) {
    if ($Date -lt $Oracle.MinDate -or $Date -gt $Oracle.MaxDate) { throw "Out of range: $Date" }
    $Date = $Date.AddDays(-1)
    while (-not (Test-OracleWorkday $Oracle $Date)) { $Date = $Date.AddDays(-1) }
    $Date
}

function Get-OracleNextOrSameWorkday($Oracle, [datetime]$Date) {
    if (Test-OracleWorkday $Oracle $Date) { $Date } else { Get-OracleNextWorkday $Oracle $Date }
}

function Get-OraclePreviousOrSameWorkday($Oracle, [datetime]$Date) {
    if (Test-OracleWorkday $Oracle $Date) { $Date } else { Get-OraclePreviousWorkday $Oracle $Date }
}

function Add-OracleWorkday($Oracle, [datetime]$Date, [int]$Days) {
    # AddWorkDaysOneByOne: RiskSystem uses it up to 5 days, and its faster method must agree with it
    if ($Days -gt 0) { for ($i = 0; $i -lt $Days; $i++) { $Date = Get-OracleNextWorkday $Oracle $Date } }
    else { for ($i = 0; $i -gt $Days; $i--) { $Date = Get-OraclePreviousWorkday $Oracle $Date } }
    $Date
}

function Get-OracleAdjustedDate($Oracle, [datetime]$Date, [string]$Adjust) {
    # AdjustFinalDate, plus the two preceding conventions RiskSystem does not have
    switch ($Adjust) {
        'Following' { Get-OracleNextOrSameWorkday $Oracle $Date }
        'ModifiedFollowing' {
            $adjusted = Get-OracleNextOrSameWorkday $Oracle $Date
            if ($adjusted.Month -ne $Date.Month) { $adjusted = Get-OraclePreviousWorkday $Oracle $adjusted }
            $adjusted
        }
        'Preceding' { Get-OraclePreviousOrSameWorkday $Oracle $Date }
        'ModifiedPreceding' {
            $adjusted = Get-OraclePreviousOrSameWorkday $Oracle $Date
            if ($adjusted.Month -ne $Date.Month) { $adjusted = Get-OracleNextWorkday $Oracle $adjusted }
            $adjusted
        }
        default { $Date }
    }
}

function Get-OracleDelta($Oracle, [datetime]$Ini, [datetime]$End, [string]$Adjust) {
    # GetDeltaWorkDays, line by line
    if ($Ini -eq $End) {
        if ($Adjust -eq 'Full' -and (Test-OracleWorkday $Oracle $Ini)) { return 1 }
        return 0
    }
    if ($Ini -gt $End) { return -(Get-OracleDelta $Oracle $End $Ini $Adjust) }

    switch ($Adjust) {
        'EndOnNextWork' { $End = Get-OracleNextOrSameWorkday $Oracle $End }
        'EndOnPrevWork' { $End = Get-OraclePreviousOrSameWorkday $Oracle $End }
        'StartAndEndCollapsing' {
            $Ini = Get-OracleNextOrSameWorkday $Oracle $Ini
            $End = Get-OraclePreviousOrSameWorkday $Oracle $End
        }
        'StartAndEndExpanding' {
            $Ini = Get-OraclePreviousOrSameWorkday $Oracle $Ini
            $End = Get-OracleNextOrSameWorkday $Oracle $End
        }
        'StartAndEndOnNext' {
            $Ini = Get-OracleNextOrSameWorkday $Oracle $Ini
            $End = Get-OracleNextOrSameWorkday $Oracle $End
        }
        'StartAndEndOnPrev' {
            $Ini = Get-OraclePreviousOrSameWorkday $Oracle $Ini
            $End = Get-OraclePreviousOrSameWorkday $Oracle $End
        }
        'StartOnNextWork' { $Ini = Get-OracleNextOrSameWorkday $Oracle $Ini }
        'StartOnPrevWork' { $Ini = Get-OraclePreviousOrSameWorkday $Oracle $Ini }
    }

    if ($Ini -eq $End) {
        if ($Adjust -eq 'Full' -and (Test-OracleWorkday $Oracle $Ini)) { return 1 }
        return 0
    }
    foreach ($date in $Ini, $End) {
        if ($date -lt $Oracle.MinDate -or $date -gt $Oracle.MaxDate) { throw "Out of range: $date" }
    }

    $delta = $Oracle.Period[($End - $Oracle.MinDate).Days] - $Oracle.Period[($Ini - $Oracle.MinDate).Days]
    $iniWorkday = Test-OracleWorkday $Oracle $Ini
    $endWorkday = Test-OracleWorkday $Oracle $End
    if ($Adjust -eq 'Full') {
        if ($iniWorkday) { $delta++ }
    }
    else {
        if ($delta -eq 0 -and $iniWorkday -and -not $endWorkday) { $delta++ }
        elseif (-not $iniWorkday -and $endWorkday) { $delta-- }
        elseif ($iniWorkday -and -not $endWorkday) { $delta++ }
    }
    $delta
}

function Get-OracleWorkdayInMonth($Oracle, [datetime]$Date, [int]$Nth) {
    # The Nth workday of the month by its definition: list them and pick
    $first = [datetime]::new($Date.Year, $Date.Month, 1)
    $workdays = @(for ($day = $first; $day.Month -eq $first.Month; $day = $day.AddDays(1)) {
            if (Test-OracleWorkday $Oracle $day) { $day }
        })
    $index = if ($Nth -gt 0) { $Nth - 1 } else { $workdays.Count + $Nth }
    if ($index -ge 0 -and $index -lt $workdays.Count) { $workdays[$index] }
}

function Invoke-Safely([scriptblock]$Script) {
    # The result, or 'error' when it throws: lets a comparison check that both sides fail together
    try { & $Script } catch { 'error' }
}
