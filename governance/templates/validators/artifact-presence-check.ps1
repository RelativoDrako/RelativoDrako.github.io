param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$ExpectedArtifactsJson = '[]'
)
$ErrorActionPreference = 'Stop'
$items = @($ExpectedArtifactsJson | ConvertFrom-Json)
foreach ($item in $items) {
    $path = Join-Path $RepoRoot $item
    if (-not (Test-Path $path)) { Write-Error ("Expected artifact missing: {0}" -f $item); exit 1 }
}
Write-Host 'Artifact presence check passed.'
exit 0
