# Known answers. The 2008-2013 cases come from RiskSystem's CalendarTests (lib/PRA.Tests/Calendars),
# with the same perpetual calendars: br-BC (national) and BM&F (national plus Sao Paulo's holidays and
# the last days of the year). The 2026 cases are those of the help and the README.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifestPath -Force

    $script:bc = New-WorkdayCalendar -Holiday (Get-BrazilianHoliday -From 2005 -To 2030) -Name br-BC
    $script:bmf = New-WorkdayCalendar -Holiday (Get-BrazilianHoliday -From 2005 -To 2030 -Exchange) -Name BMF
    $script:br = Join-Path (Split-Path $PSScriptRoot -Parent) 'Examples/br-national.txt'
}

Describe 'Test-Workday' {

    It '<Date> is a workday in <Calendar>: <Expected>' -ForEach @(
        @{ Calendar = 'bc'; Date = '2012-11-13'; Expected = $true }
        @{ Calendar = 'bc'; Date = '2012-11-15'; Expected = $false }  # Proclamation of the Republic
        @{ Calendar = 'bc'; Date = '2012-11-17'; Expected = $false }  # Saturday
        @{ Calendar = 'bc'; Date = '2012-11-20'; Expected = $true }   # not national before 2024
        @{ Calendar = 'bmf'; Date = '2012-11-20'; Expected = $false } # Sao Paulo, at BM&F
        @{ Calendar = 'bc'; Date = '2026-11-20'; Expected = $false }  # national from 2024 on
        @{ Calendar = 'bmf'; Date = '2013-01-01'; Expected = $false }
        @{ Calendar = 'bmf'; Date = '2013-01-02'; Expected = $true }
    ) {
        $calendar = Get-Variable -Name $Calendar -ValueOnly
        Test-Workday -Date $Date -Calendar $calendar | Should -Be $Expected
    }

    It 'ignores the time of day' {
        Test-Workday -Date '2026-11-20 23:59:59' -Calendar $br | Should -BeFalse
        Test-Workday -Date '2026-11-19 00:00:01' -Calendar $br | Should -BeTrue
    }

    It 'takes dates from the pipeline, also as a Date property' {
        '2026-11-19', '2026-11-20', '2026-11-21' | Test-Workday -Calendar $br | Should -Be @($true, $false, $false)
        [pscustomobject]@{ Date = '2026-11-20' } | Test-Workday -Calendar $br | Should -BeFalse
    }

    It 'without a date, answers for today' {
        Test-Workday -Calendar $bc | Should -Be (Test-Workday ([datetime]::Today) -Calendar $bc)
    }
}

Describe 'The next and the previous workday' {

    It 'reproduces the RiskSystem report on <Date> in BM&F' -ForEach @(
        @{ Date = '2013-01-01'; Previous = '2012-12-28'; Next = '2013-01-02'; Workday = $false }
        @{ Date = '2013-01-02'; Previous = '2012-12-28'; Next = '2013-01-03'; Workday = $true }
        @{ Date = '2013-01-03'; Previous = '2013-01-02'; Next = '2013-01-04'; Workday = $true }
        @{ Date = '2013-01-04'; Previous = '2013-01-03'; Next = '2013-01-07'; Workday = $true }
        @{ Date = '2013-01-05'; Previous = '2013-01-04'; Next = '2013-01-07'; Workday = $false }
        @{ Date = '2013-01-06'; Previous = '2013-01-04'; Next = '2013-01-07'; Workday = $false }
        @{ Date = '2013-01-07'; Previous = '2013-01-04'; Next = '2013-01-08'; Workday = $true }
        @{ Date = '2013-01-08'; Previous = '2013-01-07'; Next = '2013-01-09'; Workday = $true }
    ) {
        Get-PreviousWorkday $Date -Calendar $bmf | Should -Be ([datetime]$Previous)
        Get-NextWorkday $Date -Calendar $bmf | Should -Be ([datetime]$Next)
        Test-Workday $Date -Calendar $bmf | Should -Be $Workday
    }

    It 'never returns the date itself, workday or not' {
        Get-NextWorkday 2026-11-19 -Calendar $br | Should -Be ([datetime]'2026-11-23')
        Get-PreviousWorkday 2026-11-23 -Calendar $br | Should -Be ([datetime]'2026-11-19')
    }

    It 'returns the date itself, when it is a workday, with OrSame' {
        Get-NextOrSameWorkday 2026-11-19 -Calendar $br | Should -Be ([datetime]'2026-11-19')
        Get-NextOrSameWorkday 2026-11-20 -Calendar $br | Should -Be ([datetime]'2026-11-23')
        Get-PreviousOrSameWorkday 2026-11-23 -Calendar $br | Should -Be ([datetime]'2026-11-23')
        Get-PreviousOrSameWorkday 2026-11-22 -Calendar $br | Should -Be ([datetime]'2026-11-19')
    }

    It 'returns dates at midnight, without time zone kind' {
        $next = Get-NextWorkday (Get-Date '2026-11-19 15:30') -Calendar $br
        $next.TimeOfDay | Should -Be ([timespan]::Zero)
        $next.Kind | Should -Be ([DateTimeKind]::Unspecified)
    }

    It 'takes dates from the pipeline' {
        '2026-11-19', '2026-11-20' | Get-NextWorkday -Calendar $br | Should -Be @([datetime]'2026-11-23', [datetime]'2026-11-23')
    }
}

Describe 'The day before and the day after' {

    It 'the day after <Date> is a workday: <Expected>' -ForEach @(
        @{ Date = '2026-11-18'; Expected = $true }
        @{ Date = '2026-11-19'; Expected = $false }  # Friday the 20th is a holiday
        @{ Date = '2026-11-21'; Expected = $false }  # Sunday
        @{ Date = '2026-11-22'; Expected = $true }   # Sunday before a working Monday
    ) {
        Test-NextDayIsWorkday $Date -Calendar $br | Should -Be $Expected
    }

    It 'the day before <Date> was a workday: <Expected>' -ForEach @(
        @{ Date = '2026-11-20'; Expected = $true }   # a holiday after a working Thursday
        @{ Date = '2026-11-21'; Expected = $false }  # Saturday after a holiday
        @{ Date = '2026-11-23'; Expected = $false }  # Monday after a Sunday
        @{ Date = '2026-11-24'; Expected = $true }
    ) {
        Test-PreviousDayIsWorkday $Date -Calendar $br | Should -Be $Expected
    }
}

Describe 'Add-Workday' {

    It 'reproduces RiskSystem in BM&F from 2012-11-13' {
        Add-Workday 0 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-13')
        Add-Workday -2 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-09')
        Add-Workday -6 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-05')
        Add-Workday -7 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-01')  # the 2nd is All Souls' Day
    }

    It 'reproduces RiskSystem going back from a Sunday, over a holiday' {
        $calendar = New-WorkdayCalendar -Holiday 2009-08-31
        $expected = '2009-09-04', '2009-09-03', '2009-09-02', '2009-09-01', '2009-08-28', '2009-08-27', '2009-08-26',
        '2009-08-25', '2009-08-24', '2009-08-21'
        for ($days = 1; $days -le 10; $days++) {
            Add-Workday (-$days) 2009-09-06 -Calendar $calendar | Should -Be ([datetime]$expected[$days - 1])
        }
    }

    It 'reproduces RiskSystem from 2008-01-18 in br-BC' {
        Add-Workday -6 2008-01-18 -Calendar $bc | Should -Be ([datetime]'2008-01-10')
    }

    It 'counts from a non-working date' {
        Add-Workday 1 2026-11-21 -Calendar $br | Should -Be ([datetime]'2026-11-23')
        Add-Workday -1 2026-11-21 -Calendar $br | Should -Be ([datetime]'2026-11-19')
    }

    It 'returns the date unchanged with 0 days, even when it is not a workday' {
        Add-Workday 0 2026-11-21 -Calendar $br | Should -Be ([datetime]'2026-11-21')
    }

    It 'goes and comes back to the same workday' {
        $start = [datetime]'2026-01-02'
        foreach ($days in 1, 2, 5, 6, 10, 21, 63, 252, 1000, 2520) {
            $there = Add-Workday $days $start -Calendar $br
            Add-Workday (-$days) $there -Calendar $br | Should -Be $start
            Get-WorkdayDelta $start $there -Calendar $br | Should -Be $days
        }
    }

    It 'takes dates from the pipeline, also as a Date property' {
        '2026-11-16', '2026-11-19' | Add-Workday 5 -Calendar $br | Should -Be @([datetime]'2026-11-24', [datetime]'2026-11-27')
        [pscustomobject]@{ Date = '2026-11-16' } | Add-Workday 5 -Calendar $br | Should -Be ([datetime]'2026-11-24')
    }

    It 'jumps over a long closure' {
        $closure = 0..20 | ForEach-Object { ([datetime]'2026-07-01').AddDays($_) }
        $calendar = New-WorkdayCalendar -Holiday ($closure + [datetime]'2026-01-01' + [datetime]'2027-01-01')
        Add-Workday 1 2026-06-30 -Calendar $calendar | Should -Be ([datetime]'2026-07-22')
        Add-Workday -1 2026-07-22 -Calendar $calendar | Should -Be ([datetime]'2026-06-30')
    }
}

Describe 'Add-CalendarDay' {

    It 'with <Adjust>, 30 days from 2026-10-01 is <Expected>' -ForEach @(
        @{ Adjust = 'None'; Expected = '2026-10-31' }               # a Saturday
        @{ Adjust = 'Following'; Expected = '2026-11-03' }          # after a Sunday and All Souls' Day
        @{ Adjust = 'ModifiedFollowing'; Expected = '2026-10-30' }  # November is another month
        @{ Adjust = 'Preceding'; Expected = '2026-10-30' }
        @{ Adjust = 'ModifiedPreceding'; Expected = '2026-10-30' }
    ) {
        Add-CalendarDay 30 -Date 2026-10-01 -Adjust $Adjust -Calendar $br | Should -Be ([datetime]$Expected)
    }

    It 'with ModifiedPreceding, stays in the month' {
        Add-CalendarDay 0 -Date 2026-11-01 -Adjust Preceding -Calendar $br | Should -Be ([datetime]'2026-10-30')
        Add-CalendarDay 0 -Date 2026-11-01 -Adjust ModifiedPreceding -Calendar $br | Should -Be ([datetime]'2026-11-03')
    }

    It 'reproduces RiskSystem with ModifiedFollowing at the end of September 2012' {
        Add-CalendarDay 0 -Date 2012-09-30 -Adjust ModifiedFollowing -Calendar $bmf | Should -Be ([datetime]'2012-09-28')
    }

    It 'adds plain days, and goes back with negative ones' {
        Add-CalendarDay 1 -Date 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-14')
        Add-CalendarDay -10 -Date 2026-11-30 -Calendar $br | Should -Be ([datetime]'2026-11-20')
    }

    It 'does not need the calendar to cover the date without adjustment' {
        Add-CalendarDay 1 -Date 2200-01-01 -Calendar $br | Should -Be ([datetime]'2200-01-02')
    }
}

Describe 'Get-WorkdayDelta' {

    It 'counts the start and not the end, by default' {
        Get-WorkdayDelta 2026-11-16 2026-11-24 -Calendar $br | Should -Be 5
        Get-WorkdayDelta 2026-11-16 2026-11-24 -Mode Full -Calendar $br | Should -Be 6
        Get-WorkdayDelta 2026-11-24 2026-11-16 -Calendar $br | Should -Be -5
    }

    It 'reproduces RiskSystem from 2012-11-15 to 2012-11-17 in BM&F, mode <Mode>' -ForEach @(
        @{ Mode = 'Financial'; Expected = 1 }
        @{ Mode = 'Full'; Expected = 1 }
        @{ Mode = 'StartAndEndCollapsing'; Expected = 0 }
        @{ Mode = 'StartAndEndExpanding'; Expected = 2 }
        @{ Mode = 'EndOnNextWork'; Expected = 1 }
        @{ Mode = 'EndOnPrevWork'; Expected = 0 }
        @{ Mode = 'None'; Expected = 1 }
        @{ Mode = 'StartAndEndOnNext'; Expected = 1 }
        @{ Mode = 'StartAndEndOnPrev'; Expected = 1 }
        @{ Mode = 'StartOnNextWork'; Expected = 1 }
        @{ Mode = 'StartOnPrevWork'; Expected = 2 }
    ) {
        Get-WorkdayDelta 2012-11-15 2012-11-17 -Mode $Mode -Calendar $bmf | Should -Be $Expected
    }

    It 'reproduces RiskSystem around 2012-11-13 in BM&F' {
        Get-WorkdayDelta 2012-11-13 2012-11-13 -Mode Full -Calendar $bmf | Should -Be 1
        Get-WorkdayDelta 2012-11-13 2012-11-20 -Mode Full -Calendar $bmf | Should -Be 4
        Get-WorkdayDelta 2012-11-15 2012-11-15 -Calendar $bmf | Should -Be 0
        Get-WorkdayDelta 2012-11-15 2012-11-15 -Mode Full -Calendar $bmf | Should -Be 0
        Get-WorkdayDelta 2012-11-17 2012-11-15 -Calendar $bmf | Should -Be -1
        Get-WorkdayDelta 2012-11-17 2012-11-15 -Mode Full -Calendar $bmf | Should -Be -1
    }

    It 'reproduces the RiskSystem report from 2013-01-01 in BM&F' {
        $financial = 0, 0, 1, 2, 3, 3, 3, 4
        $full = 0, 1, 2, 3, 3, 3, 4, 5
        for ($i = 0; $i -lt 8; $i++) {
            $date = ([datetime]'2013-01-01').AddDays($i)
            Get-WorkdayDelta 2013-01-01 $date -Calendar $bmf | Should -Be $financial[$i]
            Get-WorkdayDelta 2013-01-01 $date -Mode Full -Calendar $bmf | Should -Be $full[$i]
        }
    }

    It 'reproduces RiskSystem in a world where Mondays are not workdays' {
        $dream = New-WorkdayCalendar -Holiday (Get-BrazilianHoliday -From 2012 -To 2012) -Weekend Saturday, Sunday, Monday
        Get-WorkdayDelta 2012-11-13 2012-11-20 -Mode Full -Calendar $dream | Should -Be 4
    }

    It 'takes from the pipeline the date not given by name' {
        '2026-11-24' | Get-WorkdayDelta -Start 2026-11-16 -Calendar $br | Should -Be 5
        '2026-11-16' | Get-WorkdayDelta -End 2026-11-24 -Calendar $br | Should -Be 5
        [pscustomobject]@{ Start = '2026-11-16'; End = '2026-11-24' } | Get-WorkdayDelta -Calendar $br | Should -Be 5
    }

    It 'counts a whole century at once' {
        $oracle = New-OracleCalendar -Holidays (Get-WorkdayCalendar $br).Holidays -Weekend Saturday, Sunday
        Get-WorkdayDelta 2001-01-01 2099-12-31 -Mode Full -Calendar $br |
            Should -Be (Get-OracleDelta $oracle ([datetime]'2001-01-01') ([datetime]'2099-12-31') 'Full')
    }
}

Describe 'Month boundaries' {

    It 'the first workday of <Month> is <Expected>' -ForEach @(
        @{ Month = '2026-11-15'; Expected = '2026-11-03' }  # Sunday the 1st, then All Souls' Day
        @{ Month = '2026-02-10'; Expected = '2026-02-02' }  # Sunday the 1st
        @{ Month = '2027-01-31'; Expected = '2027-01-04' }  # New Year's Day on a Friday, then the weekend
    ) {
        Get-FirstWorkdayInMonth $Month -Calendar $br | Should -Be ([datetime]$Expected)
    }

    It 'the last workday of <Month> is <Expected>' -ForEach @(
        @{ Month = '2026-10-14'; Expected = '2026-10-30' }  # Saturday the 31st
        @{ Month = '2026-11-01'; Expected = '2026-11-30' }
        @{ Month = '2026-12-01'; Expected = '2026-12-31' }
        @{ Month = '2028-02-01'; Expected = '2028-02-25' }  # the 28th and 29th are Carnival
    ) {
        Get-LastWorkdayInMonth $Month -Calendar $br | Should -Be ([datetime]$Expected)
    }

    It 'in BM&F, the last workday of 2012 is <Expected> for <Month>' -ForEach @(
        @{ Month = '2012-12-15'; Expected = '2012-12-28' }  # the 31st is a holiday at the exchange
    ) {
        Get-LastWorkdayInMonth $Month -Calendar $bmf | Should -Be ([datetime]$Expected)
    }

    It 'the workday <Nth> of November 2026 is <Expected>' -ForEach @(
        @{ Nth = 1; Expected = '2026-11-03' }
        @{ Nth = 2; Expected = '2026-11-04' }
        @{ Nth = 5; Expected = '2026-11-09' }
        @{ Nth = 19; Expected = '2026-11-30' }
        @{ Nth = -1; Expected = '2026-11-30' }
        @{ Nth = -2; Expected = '2026-11-27' }
        @{ Nth = -19; Expected = '2026-11-03' }
    ) {
        Get-NthWorkdayInMonth $Nth -Date 2026-11-15 -Calendar $br | Should -Be ([datetime]$Expected)
    }

    It 'reproduces RiskSystem: the Nth (to last) workday of November 2012 in BM&F' {
        Get-NthWorkdayInMonth 1 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-01')
        Get-NthWorkdayInMonth 2 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-05')
        Get-NthWorkdayInMonth 3 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-06')
        Get-NthWorkdayInMonth -1 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-30')
        Get-NthWorkdayInMonth -2 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-29')
        Get-NthWorkdayInMonth -3 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-28')
        Get-NthWorkdayInMonth -6 2012-11-13 -Calendar $bmf | Should -Be ([datetime]'2012-11-23')
    }

    It 'stops at the last workday when the month has fewer, as RiskSystem: <Nth> gives <Expected>' -ForEach @(
        @{ Nth = 20; Expected = '2026-11-30' }   # November 2026 has 19 workdays
        @{ Nth = 31; Expected = '2026-11-30' }
        @{ Nth = -20; Expected = '2026-11-03' }  # from the end, the first one
        @{ Nth = -31; Expected = '2026-11-03' }
    ) {
        Get-NthWorkdayInMonth $Nth -Date 2026-11-15 -Calendar $br | Should -Be ([datetime]$Expected)
    }

    It 'refuses position <Nth>' -ForEach @(
        @{ Nth = 0; Expected = '*cannot be 0*' }
        @{ Nth = 32; Expected = '*maximum allowed range of 31*' }
        @{ Nth = -32; Expected = '*minimum allowed range of -31*' }
    ) {
        { Get-NthWorkdayInMonth $Nth -Calendar $br } | Should -Throw -ExpectedMessage $Expected
    }
}

Describe 'Get-Workday' {

    It 'reproduces RiskSystem from 2012-11-13 to 2012-11-20 in br-BC' {
        $expected = [datetime[]]('2012-11-13', '2012-11-14', '2012-11-16', '2012-11-19', '2012-11-20')
        Get-Workday 2012-11-13 2012-11-20 -Calendar $bc | Should -Be $expected
        Get-Workday 2012-11-20 2012-11-13 -Calendar $bc | Should -Be ([datetime[]]@($expected[4..0]))
    }

    It 'lists one day, or none' {
        Get-Workday 2012-11-13 2012-11-13 -Calendar $bc | Should -Be ([datetime]'2012-11-13')
        Get-Workday 2012-11-15 2012-11-15 -Calendar $bc | Should -BeNullOrEmpty
    }

    It 'fails before listing anything when the calendar does not cover the range' {
        $output = [System.Collections.Generic.List[object]]::new()
        { Get-Workday 2099-12-01 2100-01-31 -Calendar $br | ForEach-Object { $output.Add($_) } } | Should -Throw -ExpectedMessage '*cannot tell*'
        $output.Count | Should -Be 0
    }
}

Describe 'Example calendar' {

    It 'covers 2001 to 2099, thanks to New Year''s Day of 2100' {
        $calendar = Get-WorkdayCalendar $br
        $calendar.MinDate | Should -Be ([datetime]'2001-01-01')
        $calendar.MaxDate | Should -Be ([datetime]'2100-01-01')
        Get-LastWorkdayInMonth 2099-12-01 -Calendar $br | Should -Be ([datetime]'2099-12-31')
    }

    It 'has the Brazilian national holidays of 2026' {
        $holidays = (Get-WorkdayCalendar $br).Holidays | Where-Object Year -EQ 2026
        $holidays | Should -Be ([datetime[]]('2026-01-01', '2026-02-16', '2026-02-17', '2026-04-03', '2026-04-21', '2026-05-01',
                '2026-06-04', '2026-09-07', '2026-10-12', '2026-11-02', '2026-11-15', '2026-11-20', '2026-12-25'))
    }

    It 'agrees with the perpetual br-BC calendar of RiskSystem from 2005 to 2030' {
        $fromFile = (Get-WorkdayCalendar $br).Holidays | Where-Object { $_.Year -ge 2005 -and $_.Year -le 2030 }
        $fromFile | Should -Be $bc.Holidays
    }
}
