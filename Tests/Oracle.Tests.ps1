# Random cases against a literal port of RiskSystem's Calendar class (see TestHelpers.ps1), in calendars
# with odd weekends, random holidays and long closures. Both sides must give the same answer, or both
# must fail because the answer is outside the calendar.

BeforeDiscovery {
    $weekends = @(
        @{ Label = 'Saturday and Sunday'; Weekend = @('Saturday', 'Sunday') }
        @{ Label = 'Friday and Saturday'; Weekend = @('Friday', 'Saturday') }
        @{ Label = 'Sunday only'; Weekend = @('Sunday') }
        @{ Label = 'no weekend'; Weekend = @() }
        @{ Label = 'Saturday to Monday'; Weekend = @('Saturday', 'Sunday', 'Monday') }
        @{ Label = 'Wednesday the only workday'; Weekend = @('Monday', 'Tuesday', 'Thursday', 'Friday', 'Saturday', 'Sunday') }
    )
}

Describe 'Agreement with RiskSystem, weekend <Label>' -ForEach $weekends {

    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
        Import-Module $ModuleManifestPath -Force

        $random = [Random]::new(20261014 + $Weekend.Count)
        $minDate = [datetime]'2020-01-01'
        $maxDate = [datetime]'2029-12-31'
        $span = ($maxDate - $minDate).Days

        # The national holidays, random ones, and a few closures of up to three weeks
        $holidays = [System.Collections.Generic.List[datetime]](Get-BrazilianHoliday -From 2020 -To 2029)
        for ($i = 0; $i -lt 150; $i++) { $holidays.Add($minDate.AddDays($random.Next($span))) }
        for ($i = 0; $i -lt 6; $i++) {
            $start = $minDate.AddDays($random.Next($span - 30))
            $length = $random.Next(3, 22)
            for ($day = 0; $day -lt $length; $day++) { $holidays.Add($start.AddDays($day)) }
        }

        $calendar = New-WorkdayCalendar -Holiday $holidays -Weekend $Weekend -Name random
        $oracle = New-OracleCalendar -Holidays $holidays -Weekend $Weekend -MinDate $minDate -MaxDate $maxDate

        # Dates anywhere in the calendar, edges included; some answers fall outside it on purpose
        $cases = for ($i = 0; $i -lt 60; $i++) {
            $first = $minDate.AddDays($random.Next($span + 1))
            [pscustomobject]@{
                Date   = $first
                Other  = if ($i % 4 -eq 0) { $first.AddDays($random.Next(-10, 11)) } else { $minDate.AddDays($random.Next($span + 1)) }
                Days   = if ($i % 3 -eq 0) { $random.Next(-6, 7) } else { $random.Next(-400, 401) }
                Offset = $random.Next(-60, 61)
            }
        }
        $cases = @($cases) + [pscustomobject]@{ Date = $minDate; Other = $maxDate; Days = 1; Offset = -1 } +
        [pscustomobject]@{ Date = $maxDate; Other = $minDate; Days = -1; Offset = 1 }

        function Find-Mismatch([scriptblock]$Expected, [scriptblock]$Actual, [string]$Label) {
            $want = Invoke-Safely $Expected
            $got = Invoke-Safely $Actual
            if ("$want" -ne "$got") { "${Label}: expected '$want', got '$got'" }
        }
    }

    It 'Test-Workday, Test-NextDayIsWorkday and Test-PreviousDayIsWorkday' {
        $mismatches = foreach ($case in $cases) {
            $d = $case.Date
            Find-Mismatch { Test-OracleWorkday $oracle $d } { Test-Workday $d -Calendar $calendar } "Test-Workday $d"
            Find-Mismatch { Test-OracleWorkday $oracle $d.AddDays(1) } { Test-NextDayIsWorkday $d -Calendar $calendar } "Test-NextDayIsWorkday $d"
            Find-Mismatch { Test-OracleWorkday $oracle $d.AddDays(-1) } { Test-PreviousDayIsWorkday $d -Calendar $calendar } "Test-PreviousDayIsWorkday $d"
        }
        $mismatches | Should -BeNullOrEmpty
    }

    It 'the next and previous workdays' {
        $mismatches = foreach ($case in $cases) {
            $d = $case.Date
            Find-Mismatch { Get-OracleNextWorkday $oracle $d } { Get-NextWorkday $d -Calendar $calendar } "Get-NextWorkday $d"
            Find-Mismatch { Get-OracleNextOrSameWorkday $oracle $d } { Get-NextOrSameWorkday $d -Calendar $calendar } "Get-NextOrSameWorkday $d"
            Find-Mismatch { Get-OraclePreviousWorkday $oracle $d } { Get-PreviousWorkday $d -Calendar $calendar } "Get-PreviousWorkday $d"
            Find-Mismatch { Get-OraclePreviousOrSameWorkday $oracle $d } { Get-PreviousOrSameWorkday $d -Calendar $calendar } "Get-PreviousOrSameWorkday $d"
        }
        $mismatches | Should -BeNullOrEmpty
    }

    It 'Add-Workday' {
        $mismatches = foreach ($case in $cases) {
            $d = $case.Date
            $n = $case.Days
            Find-Mismatch { Add-OracleWorkday $oracle $d $n } { Add-Workday $n $d -Calendar $calendar } "Add-Workday $n $d"
        }
        $mismatches | Should -BeNullOrEmpty
    }

    It 'Add-CalendarDay with every convention' {
        $mismatches = foreach ($case in $cases) {
            $d = $case.Date
            $n = $case.Offset
            foreach ($adjust in $AdjustConventions) {
                Find-Mismatch { Get-OracleAdjustedDate $oracle $d.AddDays($n) $adjust } `
                { Add-CalendarDay $n $d -Adjust $adjust -Calendar $calendar } "Add-CalendarDay $n $d $adjust"
            }
        }
        $mismatches | Should -BeNullOrEmpty
    }

    It 'Get-WorkdayDelta in every mode' {
        $mismatches = foreach ($case in $cases) {
            $a = $case.Date
            $b = $case.Other
            foreach ($mode in $DeltaModes) {
                Find-Mismatch { Get-OracleDelta $oracle $a $b $mode } { Get-WorkdayDelta $a $b -Mode $mode -Calendar $calendar } "Get-WorkdayDelta $a $b $mode"
            }
        }
        $mismatches | Should -BeNullOrEmpty
    }

    It 'the first, last and Nth workdays of the month' {
        $mismatches = foreach ($case in ($cases | Select-Object -First 25)) {
            $d = $case.Date
            Find-Mismatch { Get-OracleWorkdayInMonth $oracle $d 1 } { Get-FirstWorkdayInMonth $d -Calendar $calendar } "Get-FirstWorkdayInMonth $d"
            Find-Mismatch { Get-OracleWorkdayInMonth $oracle $d -1 } { Get-LastWorkdayInMonth $d -Calendar $calendar } "Get-LastWorkdayInMonth $d"
            foreach ($nth in 2, 5, 12, 23, -2, -9, -23) {
                Find-Mismatch { Get-OracleWorkdayInMonth $oracle $d $nth } { Get-NthWorkdayInMonth $nth $d -Calendar $calendar } "Get-NthWorkdayInMonth $nth $d"
            }
        }
        $mismatches | Should -BeNullOrEmpty
    }

    It 'Get-Workday' {
        $mismatches = foreach ($case in ($cases | Select-Object -First 15)) {
            $a = $case.Date
            $b = $a.AddDays($case.Offset)
            $expected = {
                # Both ends first, so that a range partly outside the calendar fails before listing
                Test-OracleWorkday $oracle $a | Out-Null
                Test-OracleWorkday $oracle $b | Out-Null
                $step = if ($a -le $b) { 1 } else { -1 }
                for ($day = $a; ; $day = $day.AddDays($step)) {
                    if (Test-OracleWorkday $oracle $day) { $day }
                    if ($day -eq $b) { break }
                }
            }
            Find-Mismatch $expected { Get-Workday $a $b -Calendar $calendar } "Get-Workday $a $b"
        }
        $mismatches | Should -BeNullOrEmpty
    }
}
