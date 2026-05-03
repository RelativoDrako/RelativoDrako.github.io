param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$ExpectedDocsJson = '[]'
)
$ErrorActionPreference = 'Stop'
$docs = @($ExpectedDocsJson | ConvertFrom-Json)
foreach ($doc in $docs) {
    $path = Join-Path $RepoRoot $doc
    if (-not (Test-Path $path)) { Write-Error ("Expected documentation path missing: {0}" -f $doc); exit 1 }
}
Write-Host 'Documentation presence check passed.'
exit 0
