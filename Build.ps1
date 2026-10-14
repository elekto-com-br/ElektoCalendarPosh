<#
.SYNOPSIS
Validates the module, runs the tests and stages the files that go to the PowerShell Gallery.

.DESCRIPTION
The PowerShell equivalent of "does it compile and pass": every script is parsed for syntax errors,
the manifest is validated, PSScriptAnalyzer runs (when installed) and the Pester tests run (when
Pester 5 or later is installed). If everything passes, the package is staged at
./out/ElektoCalendarPosh, with all the functions in a single .psm1, and imported in a clean process
to check that every function in the manifest is exported. It is then ready for Publish-PSResource.

Used by the GitHub workflows; can also be run locally before committing or tagging.

.PARAMETER ExpectedVersion
When given (the publish workflow passes the tag version), fails unless the manifest declares this
version.

.PARAMETER SkipTests
Does not run the Pester tests.

.EXAMPLE
./Build.ps1

.EXAMPLE
./Build.ps1 -ExpectedVersion 0.1.0
#>
param (
    [string]$ExpectedVersion,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$moduleName = 'ElektoCalendarPosh'
$manifestPath = Join-Path $PSScriptRoot "$moduleName.psd1"
$packageFiles = @("$moduleName.psd1", "$moduleName.Format.ps1xml", 'Examples', 'LICENSE', 'README.md')

# 1. Syntax: parse every PowerShell file
$scripts = Get-ChildItem -Path $PSScriptRoot -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
    Where-Object { $_.FullName -notmatch '[\\/](out|\.git)[\\/]' }
$syntaxErrors = foreach ($script in $scripts) {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$parseErrors) | Out-Null
    $parseErrors | ForEach-Object { "$($script.Name):$($_.Extent.StartLineNumber): $($_.Message)" }
}
if ($syntaxErrors) { throw "Syntax errors:`n$($syntaxErrors -join "`n")" }
Write-Host "Syntax OK ($($scripts.Count) files)."

# 2. Manifest, and version against the tag
$manifest = Test-ModuleManifest -Path $manifestPath
if ($ExpectedVersion -and $manifest.Version.ToString() -ne $ExpectedVersion) {
    throw "Tag means version '$ExpectedVersion', but the manifest declares '$($manifest.Version)'. Set them to the same value and re-tag."
}
Write-Host "Manifest OK (version $($manifest.Version))."

# 3. Static analysis: errors fail the build, warnings are only shown. In the tests, Pester's blocks share
#    variables in ways the analyzer cannot follow, and the helpers that write files need no ShouldProcess.
if (Get-Module -ListAvailable PSScriptAnalyzer) {
    $severity = 'Error', 'Warning'
    $sources = "$moduleName.psd1", "$moduleName.psm1", 'Build.ps1', 'Private', 'Public' | ForEach-Object { Join-Path $PSScriptRoot $_ }
    $findings = @(
        foreach ($source in $sources) { Invoke-ScriptAnalyzer -Path $source -Recurse -Severity $severity -ExcludeRule PSAvoidUsingWriteHost }
        Invoke-ScriptAnalyzer -Path (Join-Path $PSScriptRoot 'Tests') -Recurse -Severity $severity -ExcludeRule PSAvoidUsingWriteHost,
        PSUseDeclaredVarsMoreThanAssignments, PSUseShouldProcessForStateChangingFunctions
    )
    if ($findings) { $findings | Format-Table -AutoSize RuleName, Severity, ScriptName, Line, Message | Out-String | Write-Host }
    $analyzerErrors = @($findings | Where-Object Severity -EQ 'Error')
    if ($analyzerErrors) { throw "PSScriptAnalyzer found $($analyzerErrors.Count) error(s)." }
    Write-Host 'PSScriptAnalyzer OK.'
}
else {
    Write-Warning 'PSScriptAnalyzer not installed; skipping static analysis.'
}

# 4. Tests, on the source
if ($SkipTests) {
    Write-Warning 'Skipping the tests (-SkipTests).'
}
elseif ($pester = Get-Module -ListAvailable Pester | Where-Object Version -GE '5.0' | Sort-Object Version -Descending | Select-Object -First 1) {
    Import-Module $pester -Force
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = Join-Path $PSScriptRoot 'Tests'
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Normal'
    $result = Invoke-Pester -Configuration $configuration
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { throw "Tests failed: $($result.FailedCount) of $($result.TotalCount)." }
    Write-Host "Tests OK ($($result.PassedCount) passed, Pester $($pester.Version))."
}
else {
    Write-Warning 'Pester 5 or later not installed; skipping the tests.'
}

# 5. Stage the package. Its .psm1 holds every function, in the order the source loader dot-sources them:
#    one file loads in about half the time of eighteen, which counts for scripts started every minute.
$outDir = Join-Path (Join-Path $PSScriptRoot 'out') $moduleName
if (Test-Path $outDir) { Remove-Item -Path $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir | Out-Null
foreach ($file in $packageFiles) {
    Copy-Item -Path (Join-Path $PSScriptRoot $file) -Destination $outDir -Recurse
}
$merged = foreach ($folder in 'Private', 'Public') {
    foreach ($script in Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1') {
        "#region $folder/$($script.Name)"
        [IO.File]::ReadAllText($script.FullName).TrimEnd()
        '#endregion'
        ''
    }
}
[IO.File]::WriteAllLines((Join-Path $outDir "$moduleName.psm1"), [string[]]$merged, [Text.UTF8Encoding]::new($false))
Write-Host "Package staged at $outDir."

# 6. Import the package in a clean process: every function in the manifest is exported, and works
pwsh -NoProfile -NonInteractive -Command {
    param($Manifest, $Name)
    Import-Module $Manifest -Force -ErrorAction Stop
    $missing = (Import-PowerShellDataFile $Manifest).FunctionsToExport |
        Where-Object { -not (Get-Command $_ -Module $Name -ErrorAction SilentlyContinue) }
    if ($missing) { throw "Not exported: $($missing -join ', ')" }
    $friday = [datetime]'2026-10-16'
    if ((Add-Workday 1 $friday) -ne $friday.AddDays(3)) { throw 'Add-Workday gave a wrong answer.' }
} -args (Join-Path $outDir "$moduleName.psd1"), $moduleName
if ($LASTEXITCODE -ne 0) { throw 'Package import check failed.' }
Write-Host 'Package import OK.'
