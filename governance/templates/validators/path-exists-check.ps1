param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$ExpectedPathsJson = '[]'
)
$ErrorActionPreference = 'Stop'
$items = @($ExpectedPathsJson | ConvertFrom-Json)
foreach ($item in $items) {
    $path = Join-Path $RepoRoot $item
    if (-not (Test-Path $path)) { Write-Error ("Expected path missing: {0}" -f $item); exit 1 }
}
Write-Host 'Path exists check passed.'
exit 0
