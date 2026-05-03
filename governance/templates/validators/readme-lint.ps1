param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$RequiredHeadingsJson = '[]'
)
$ErrorActionPreference = 'Stop'
$readme = Join-Path $RepoRoot 'README.md'
if (-not (Test-Path $readme)) { Write-Error 'README.md not found'; exit 1 }
$text = Get-Content -Raw -LiteralPath $readme
$required = @()
if (-not [string]::IsNullOrWhiteSpace($RequiredHeadingsJson)) { $required = @($RequiredHeadingsJson | ConvertFrom-Json) }
foreach ($heading in $required) {
    if ($text -notmatch [regex]::Escape($heading)) { Write-Error ("Missing heading or term: {0}" -f $heading); exit 1 }
}
$blocked = @('TODO', 'TBD', 'lorem ipsum')
foreach ($term in $blocked) {
    if ($text -match [regex]::Escape($term)) { Write-Error ("Blocked placeholder detected: {0}" -f $term); exit 1 }
}
Write-Host 'README lint passed.'
exit 0
