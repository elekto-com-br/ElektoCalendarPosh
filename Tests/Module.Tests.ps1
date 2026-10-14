BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifestPath -Force
}

Describe 'Module' {

    It 'has a valid manifest for PowerShell 7' {
        $manifest = Test-ModuleManifest -Path $ModuleManifestPath
        $manifest.PowerShellVersion | Should -Be ([version]'7.2')
        $manifest.CompatiblePSEditions | Should -Be @('Core')
    }

    It 'exports exactly the functions in the manifest' {
        $expected = (Import-PowerShellDataFile $ModuleManifestPath).FunctionsToExport | Sort-Object
        $exported = (Get-Command -Module ElektoCalendarPosh).Name | Sort-Object
        $exported | Should -Be $expected
    }

    It 'exports no private function' {
        Get-Command -Module ElektoCalendarPosh -Name Resolve-Calendar -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command -Module ElektoCalendarPosh -Name Find-Workday -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Help of <_>' -ForEach @((Import-PowerShellDataFile (Join-Path (Split-Path $PSScriptRoot -Parent) 'ElektoCalendarPosh.psd1')).FunctionsToExport) {

    BeforeAll {
        $help = Get-Help $_ -Full
    }

    It 'has a synopsis, a description and examples' {
        $help.Synopsis | Should -Not -BeLike "*$_*[[]*"  # not the auto-generated syntax line
        $help.Description.Text | Should -Not -BeNullOrEmpty
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'documents every parameter' {
        $common = @([System.Management.Automation.PSCmdlet]::CommonParameters) +
        @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
        $parameters = (Get-Command $_).Parameters.Keys | Where-Object { $_ -notin $common }
        foreach ($parameter in $parameters) {
            $description = ($help.Parameters.Parameter | Where-Object Name -EQ $parameter).Description.Text
            $description | Should -Not -BeNullOrEmpty -Because "-$parameter needs a description"
        }
    }
}
