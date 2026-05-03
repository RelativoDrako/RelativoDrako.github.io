param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$YamlFilesJson = '[]'
)
$ErrorActionPreference = 'Stop'
$files = @($YamlFilesJson | ConvertFrom-Json)
foreach ($file in $files) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path $path)) { Write-Error ("YAML file not found: {0}" -f $file); exit 1 }
    $content = Get-Content -Raw -LiteralPath $path
    if ($content -notmatch '(^|\n)\s*name\s*:') {
        Write-Error ("Basic YAML structure check failed for: {0}" -f $file)
        exit 1
    }
}
Write-Host 'YAML syntax check passed.'
exit 0
