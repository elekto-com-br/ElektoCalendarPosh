BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifestPath -Force

    $script:savedEnvironment = $env:WORKDAY_CALENDAR
}

AfterAll {
    $env:WORKDAY_CALENDAR = $savedEnvironment
    Set-WorkdayCalendar
}

Describe 'Holiday file' {

    It 'reads dates with descriptions, comments and blank lines' {
        $path = New-TestCalendarFile 'br.txt' @'
# Brazil, a few days of 2026

2026-11-02  All Souls' Day
2026-11-20  Black Consciousness Day   # a Friday
2026-12-25
'@
        $calendar = New-WorkdayCalendar $path
        $calendar.Holidays | Should -Be @([datetime]'2026-11-02', [datetime]'2026-11-20', [datetime]'2026-12-25')
        $calendar.Weekend | Should -Be @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
        $calendar.Name | Should -Be 'br'
        $calendar.Path | Should -Be $path
    }

    It 'reads the non-working weekdays: <Label>' -ForEach @(
        @{ Label = 'on one line'; Content = "Friday Saturday`n2026-11-20"; Expected = @('Friday', 'Saturday') }
        @{ Label = 'one per line, like bizdays'; Content = "Saturday`nSunday`n2026-11-20"; Expected = @('Saturday', 'Sunday') }
        @{ Label = 'with commas and in any case'; Content = "friday, SATURDAY`n2026-11-20"; Expected = @('Friday', 'Saturday') }
        @{ Label = 'a single day'; Content = "Sunday`n2026-11-20"; Expected = @('Sunday') }
        @{ Label = 'after a comment'; Content = "# weekend`nThursday Friday # in some places`n2026-11-20"; Expected = @('Thursday', 'Friday') }
    ) {
        $path = New-TestCalendarFile 'weekend.txt' $Content
        (New-WorkdayCalendar $path).Weekend | Should -Be ([DayOfWeek[]]$Expected)
    }

    It 'takes Saturday and Sunday when the file declares no weekday' {
        $path = New-TestCalendarFile 'plain.txt' '2026-11-20'
        (New-WorkdayCalendar $path).Weekend | Should -Be @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
    }

    It 'makes every day of the week a workday with NoWeekend <Label>' -ForEach @(
        @{ Label = 'on the first line'; Content = "NoWeekend`n2026-01-01`n2026-12-25" }
        @{ Label = 'after comments, in any case'; Content = "# open every day`n`nnoweekend  # no days off`n2026-01-01`n2026-12-25" }
    ) {
        $path = New-TestCalendarFile 'always.txt' $Content
        $calendar = New-WorkdayCalendar $path
        $calendar.Weekend | Should -BeNullOrEmpty
        $calendar | Out-String | Should -BeLike '*always*NoWeekend*2026-01-01*2026-12-25*'
        Test-Workday 2026-11-21 -Calendar $path | Should -BeTrue   # a Saturday
        Test-Workday 2026-12-25 -Calendar $path | Should -BeFalse
    }

    It 'lets -Weekend replace NoWeekend' {
        $path = New-TestCalendarFile 'always.txt' "NoWeekend`n2026-12-25"
        (New-WorkdayCalendar $path -Weekend Sunday).Weekend | Should -Be @([DayOfWeek]::Sunday)
    }

    It 'rejects <Label>' -ForEach @(
        @{ Label = 'weekday names after a holiday'; Content = "2026-11-02`nSaturday"; Expected = '*Line 2 *must come before the first holiday*' }
        @{ Label = 'NoWeekend after a holiday'; Content = "2026-11-02`nNoWeekend"; Expected = '*Line 2 *NoWeekend must be the first line*' }
        @{ Label = 'NoWeekend after weekday names'; Content = "Sunday`nNoWeekend"; Expected = '*Line 2 *NoWeekend must be the first line*' }
        @{ Label = 'weekday names after NoWeekend'; Content = "NoWeekend`nSaturday"; Expected = '*Line 2 *cannot follow NoWeekend*' }
        @{ Label = 'NoWeekend with weekday names'; Content = "NoWeekend Saturday`n2026-11-02"; Expected = '*Line 1 *neither a date*' }
    ) {
        $path = New-TestCalendarFile 'misplaced.txt' $Content
        $failure = { New-WorkdayCalendar $path } | Should -Throw -PassThru
        $failure.FullyQualifiedErrorId | Should -BeLike 'InvalidCalendarLine*'
        $failure.Exception.Message | Should -BeLike $Expected
    }

    It 'reads a file with a byte order mark' {
        $path = Join-Path $TestDrive 'bom.txt'
        [IO.File]::WriteAllText($path, "Saturday Sunday`n2026-11-20  Feriado da Consci`u{00EA}ncia Negra", [Text.UTF8Encoding]::new($true))
        (New-WorkdayCalendar $path).Holidays | Should -Be @([datetime]'2026-11-20')
    }

    It 'rejects <Label>, naming the line' -ForEach @(
        @{ Label = 'an impossible date'; Line = '2026-13-01' }
        @{ Label = 'a date in another format'; Line = '20/11/2026' }
        @{ Label = 'a misspelt weekday'; Line = 'Satruday' }
        @{ Label = 'a date glued to its description'; Line = '2026-11-20Holiday' }
        @{ Label = 'a weekday followed by a description'; Line = 'Sunday is a day off' }
    ) {
        $path = New-TestCalendarFile 'bad.txt' "2026-11-02`n$Line"
        $failure = { New-WorkdayCalendar $path } | Should -Throw -PassThru
        $failure.Exception | Should -BeOfType [FormatException]
        $failure.FullyQualifiedErrorId | Should -BeLike 'InvalidCalendarLine*'
        $failure.Exception.Message | Should -BeLike "*Line 2 of*bad.txt*$Line*"
    }

    It 'leaves a rejected file free to be fixed' {
        $path = New-TestCalendarFile 'locked.txt' "2026-11-02`nwrong"
        { New-WorkdayCalendar $path } | Should -Throw
        [IO.File]::WriteAllText($path, '2026-11-02')
        (New-WorkdayCalendar $path).Holidays | Should -Be @([datetime]'2026-11-02')
    }

    It 'reports a missing file' {
        $failure = { Test-Workday -Calendar (Join-Path $TestDrive 'missing.txt') } | Should -Throw -PassThru
        $failure.Exception | Should -BeOfType [IO.FileNotFoundException]
        $failure.FullyQualifiedErrorId | Should -BeLike 'CalendarFileNotFound*'
    }

    It 'resolves relative paths from the current location' {
        New-TestCalendarFile 'relative/br.txt' '2026-11-20' | Out-Null
        Push-Location (Join-Path $TestDrive 'relative')
        try {
            Test-Workday 2026-11-20 -Calendar ./br.txt | Should -BeFalse
            Test-Workday 2026-11-19 -Calendar br.txt | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It 'reads the file again when it changes' {
        $path = New-TestCalendarFile 'changing.txt' '2026-11-20'
        Test-Workday 2026-11-19 -Calendar $path | Should -BeTrue

        [IO.File]::WriteAllText($path, "2026-11-19`n2026-11-20")
        (Get-Item $path).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(1)
        Test-Workday 2026-11-19 -Calendar $path | Should -BeFalse
    }
}

Describe 'Coverage' {

    BeforeAll {
        $script:coveragePath = New-TestCalendarFile 'coverage.txt' "2025-06-02`n2027-03-01"
    }

    It 'goes from the first holiday to the last' {
        $calendar = Get-WorkdayCalendar $coveragePath
        $calendar.MinDate | Should -Be ([datetime]'2025-06-02')
        $calendar.MaxDate | Should -Be ([datetime]'2027-03-01')
        Test-Workday 2025-06-02 -Calendar $coveragePath | Should -BeFalse
        Test-Workday 2025-06-03 -Calendar $coveragePath | Should -BeTrue
        Test-Workday 2027-03-01 -Calendar $coveragePath | Should -BeFalse
    }

    It 'refuses a date <Label>' -ForEach @(
        @{ Label = 'after the last holiday'; Date = '2027-03-02'; Advice = 'after 2027-03-01' }
        @{ Label = 'before the first holiday'; Date = '2025-05-30'; Advice = 'before 2025-06-02' }
    ) {
        $failure = { Test-Workday $Date -Calendar $coveragePath } | Should -Throw -PassThru
        $failure.Exception | Should -BeOfType [ArgumentOutOfRangeException]
        $failure.FullyQualifiedErrorId | Should -BeLike 'DateOutsideCalendar*'
        $failure.Exception.Message | Should -BeLike "*covers 2025-06-02 to 2027-03-01*$Date*holidays $Advice to*coverage.txt*"
    }

    It 'refuses an answer that needs a day beyond it' {
        { Get-NextWorkday 2027-03-01 -Calendar $coveragePath } | Should -Throw -ExpectedMessage '*2027-03-02*'
        { Add-Workday 10 2027-02-25 -Calendar $coveragePath } | Should -Throw -ExpectedMessage '*cannot tell*'
        { Get-WorkdayDelta 2027-02-01 2027-03-10 -Calendar $coveragePath } | Should -Throw -ExpectedMessage '*cannot tell*'
    }

    It 'reaches the end of a year with the next January 1st' {
        $path = New-TestCalendarFile 'to-year-end.txt' "2026-11-20`n2026-12-25`n2027-01-01"
        Test-Workday 2026-12-31 -Calendar $path | Should -BeTrue
        Get-LastWorkdayInMonth 2026-12-01 -Calendar $path | Should -Be ([datetime]'2026-12-31')
    }

    It 'spans 25 years before a single holiday and 75 after it' {
        $calendar = New-WorkdayCalendar -Holiday 2026-11-20
        $calendar.MinDate | Should -Be ([datetime]'2001-11-20')
        $calendar.MaxDate | Should -Be ([datetime]'2101-11-20')
    }

    It 'has no limit without holidays' {
        $path = New-TestCalendarFile 'weekend-only.txt' "# only the weekend`nFriday Saturday"
        $calendar = Get-WorkdayCalendar $path
        $calendar.MinDate | Should -BeNullOrEmpty
        $calendar.MaxDate | Should -BeNullOrEmpty
        Test-Workday 1900-01-05 -Calendar $path | Should -BeFalse   # a Friday
        Test-Workday 2200-01-05 -Calendar $path | Should -BeTrue    # a Sunday
    }
}

Describe 'Default calendar' {

    BeforeEach {
        $env:WORKDAY_CALENDAR = $null
        Set-WorkdayCalendar
    }

    It 'is Saturday and Sunday only, covering every date' {
        $calendar = Get-WorkdayCalendar
        $calendar.Weekend | Should -Be @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
        $calendar.Holidays | Should -BeNullOrEmpty
        Test-Workday 2026-11-20 | Should -BeTrue    # a holiday in Brazil, but not here
        Test-Workday 2026-11-21 | Should -BeFalse
        Get-NextWorkday 1999-12-31 | Should -Be ([datetime]'2000-01-03')
    }

    It 'comes from WORKDAY_CALENDAR' {
        $env:WORKDAY_CALENDAR = New-TestCalendarFile 'env.txt' '2026-11-20'
        Test-Workday 2026-11-20 | Should -BeFalse
        (Get-WorkdayCalendar).Name | Should -Be 'env'
    }

    It 'combines the files in WORKDAY_CALENDAR' {
        $br = New-TestCalendarFile 'env-br.txt' '2026-11-20'
        $us = New-TestCalendarFile 'env-us.txt' '2026-11-26'
        $env:WORKDAY_CALENDAR = $br, $us -join [IO.Path]::PathSeparator
        Test-Workday 2026-11-20 | Should -BeFalse
        Test-Workday 2026-11-26 | Should -BeFalse
        (Get-WorkdayCalendar).Name | Should -Be 'env-br+env-us'
    }

    It 'comes from Set-WorkdayCalendar, before WORKDAY_CALENDAR' {
        $env:WORKDAY_CALENDAR = New-TestCalendarFile 'env.txt' '2026-11-20'
        Set-WorkdayCalendar (New-TestCalendarFile 'set.txt' '2026-11-19')
        Test-Workday 2026-11-19 | Should -BeFalse
        Test-Workday 2026-11-20 | Should -BeTrue

        Set-WorkdayCalendar
        Test-Workday 2026-11-20 | Should -BeFalse
    }

    It 'keeps a relative path pointing to the same file after a change of location' {
        New-TestCalendarFile 'set/br.txt' '2026-11-20' | Out-Null
        Push-Location (Join-Path $TestDrive 'set')
        try { Set-WorkdayCalendar ./br.txt } finally { Pop-Location }
        Test-Workday 2026-11-20 | Should -BeFalse
    }

    It 'accepts a calendar object and returns it with -PassThru' {
        $calendar = New-WorkdayCalendar -Holiday 2026-11-20 -Name custom
        (Set-WorkdayCalendar $calendar -PassThru).Name | Should -Be 'custom'
        Test-Workday 2026-11-20 | Should -BeFalse
    }

    It 'does not change with -WhatIf' {
        Set-WorkdayCalendar (New-TestCalendarFile 'whatif.txt' '2026-11-20') -WhatIf
        Test-Workday 2026-11-20 | Should -BeTrue
    }

    It 'does not change when the new one fails' {
        { Set-WorkdayCalendar (Join-Path $TestDrive 'missing.txt') } | Should -Throw
        (Get-WorkdayCalendar).Name | Should -Be 'Weekends'
    }
}

Describe 'Calendar parameter' {

    BeforeAll {
        $script:brPath = New-TestCalendarFile 'param-br.txt' "2026-01-01`n2026-11-02`n2026-11-20`n2027-01-01"
        $script:usPath = New-TestCalendarFile 'param-us.txt' "2026-01-01`n2026-11-11`n2026-11-26`n2027-01-01"
    }

    It 'accepts <Label>' -ForEach @(
        @{ Label = 'a path'; Make = { $brPath } }
        @{ Label = 'a file object'; Make = { Get-Item $brPath } }
        @{ Label = 'a resolved path'; Make = { Resolve-Path $brPath } }
        @{ Label = 'a calendar object'; Make = { New-WorkdayCalendar $brPath } }
    ) {
        Test-Workday 2026-11-20 -Calendar (& $Make) | Should -BeFalse
    }

    It 'combines several calendars: a day is a workday only if it is one in all of them' {
        $joint = Get-WorkdayCalendar $brPath, $usPath
        $joint.Name | Should -Be 'param-br+param-us'
        $joint.Holidays.Count | Should -Be 6
        Test-Workday 2026-11-19 -Calendar $brPath, $usPath | Should -BeTrue
        Test-Workday 2026-11-20 -Calendar $brPath, $usPath | Should -BeFalse
        Test-Workday 2026-11-26 -Calendar $brPath, $usPath | Should -BeFalse
        Get-NextWorkday 2026-11-25 -Calendar $brPath, $usPath | Should -Be ([datetime]'2026-11-27')
    }

    It 'reuses a combination while its calendars do not change' {
        $first = Get-WorkdayCalendar $brPath, $usPath
        [object]::ReferenceEquals($first, (Get-WorkdayCalendar $brPath, $usPath)) | Should -BeTrue

        $path = New-TestCalendarFile 'param-changing.txt' '2026-11-11'
        $before = Get-WorkdayCalendar $brPath, $path
        [IO.File]::WriteAllText($path, "2026-11-11`n2026-11-12")
        (Get-Item $path).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(1)
        $after = Get-WorkdayCalendar $brPath, $path
        [object]::ReferenceEquals($before, $after) | Should -BeFalse
        Test-Workday 2026-11-12 -Calendar $brPath, $path | Should -BeFalse
    }

    It 'combines the weekends too' {
        $gulf = New-WorkdayCalendar -Weekend Friday, Saturday
        (Get-WorkdayCalendar $brPath, $gulf).Weekend | Should -Be @([DayOfWeek]::Friday, [DayOfWeek]::Saturday, [DayOfWeek]::Sunday)
    }

    It 'covers only what all the combined calendars cover' {
        $longer = New-WorkdayCalendar -Holiday 2020-01-01, 2030-12-25
        $joint = Get-WorkdayCalendar $brPath, $longer, (New-WorkdayCalendar)
        $joint.MinDate | Should -Be ([datetime]'2026-01-01')
        $joint.MaxDate | Should -Be ([datetime]'2027-01-01')
    }

    It 'refuses calendars with no period in common' {
        $other = New-WorkdayCalendar -Holiday 2030-01-01, 2030-12-25
        $failure = { Get-WorkdayCalendar $brPath, $other } | Should -Throw -PassThru
        $failure.FullyQualifiedErrorId | Should -BeLike 'NoCommonPeriod*'
    }

    It 'refuses something that is not a calendar' {
        $failure = { Test-Workday -Calendar 42 } | Should -Throw -PassThru
        $failure.FullyQualifiedErrorId | Should -BeLike 'InvalidCalendar*'
    }
}

Describe 'New-WorkdayCalendar' {

    It 'builds a calendar from dates alone' {
        $calendar = New-WorkdayCalendar -Holiday 2026-11-20, 2026-11-02
        $calendar.Name | Should -Be 'Custom'
        $calendar.Holidays | Should -Be @([datetime]'2026-11-02', [datetime]'2026-11-20')
        $calendar.MinDate | Should -Be ([datetime]'2026-11-02')
        $calendar.MaxDate | Should -Be ([datetime]'2026-11-20')
        $calendar.Path | Should -BeNullOrEmpty
    }

    It 'adds holidays to those of the file' {
        $path = New-TestCalendarFile 'office.txt' '2026-11-20'
        $calendar = New-WorkdayCalendar $path -Holiday 2026-12-24 -Name office
        $calendar.Name | Should -Be 'office'
        $calendar.Holidays | Should -Be @([datetime]'2026-11-20', [datetime]'2026-12-24')
    }

    It 'replaces the weekend of the file' {
        $path = New-TestCalendarFile 'gulf.txt' "Saturday Sunday`n2026-11-20"
        (New-WorkdayCalendar $path -Weekend Friday, Saturday).Weekend | Should -Be @([DayOfWeek]::Friday, [DayOfWeek]::Saturday)
    }

    It 'makes every day a workday with an empty weekend' {
        $always = New-WorkdayCalendar -Weekend @()
        $always.Weekend | Should -BeNullOrEmpty
        Test-Workday 2026-11-21 -Calendar $always | Should -BeTrue
        Add-Workday 7 2026-11-16 -Calendar $always | Should -Be ([datetime]'2026-11-23')
    }

    It 'refuses a week without workdays' {
        $failure = { New-WorkdayCalendar -Weekend ([Enum]::GetValues([DayOfWeek])) } | Should -Throw -PassThru
        $failure.FullyQualifiedErrorId | Should -BeLike 'NoWorkingWeekday*'
    }

    It 'shows its calendars as a table with ISO dates' {
        $text = New-WorkdayCalendar -Holiday 2026-01-01, 2026-11-20 -Name custom | Out-String
        $text | Should -BeLike '*Name*Weekend*MinDate*MaxDate*Holidays*Path*'
        $text | Should -BeLike '*custom*Saturday, Sunday*2026-01-01*2026-11-20*2*'
    }
}
