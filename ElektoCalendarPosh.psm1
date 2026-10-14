# Loads the private helpers and the public functions; the manifest exports only the public ones.
# The published package has, instead of this loader, a single .psm1 with all of them (see Build.ps1).
foreach ($folder in 'Private', 'Public') {
    Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' | ForEach-Object { . $_.FullName }
}
