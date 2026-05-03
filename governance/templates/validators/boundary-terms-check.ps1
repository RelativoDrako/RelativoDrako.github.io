param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$TargetFilesJson = '[]',
    [string]$RequiredTermsJson = '[]'
)
$ErrorActionPreference = 'Stop'
$files = @($TargetFilesJson | ConvertFrom-Json)
$terms = @($RequiredTermsJson | ConvertFrom-Json)
if ($files.Count -eq 0 -or $terms.Count -eq 0) { Write-Host 'Nothing to validate.'; exit 0 }
$textAggregate = ''
foreach ($file in $files) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path $path)) { Write-Error ("Target file not found: {0}" -f $file); exit 1 }
    $textAggregate += "`n" + (Get-Content -Raw -LiteralPath $path)
}
foreach ($term in $terms) {
    if ($textAggregate -notmatch [regex]::Escape($term)) {
        Write-Error ("Required boundary term missing: {0}" -f $term)
        exit 1
    }
}
Write-Host 'Boundary terms check passed.'
exit 0
