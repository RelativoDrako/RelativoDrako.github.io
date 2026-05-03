param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$RequiredHtmlFilesJson = '["index.html"]',
    [string]$RequiredSelectorsJson = '[]'
)
$ErrorActionPreference = 'Stop'
$files = @($RequiredHtmlFilesJson | ConvertFrom-Json)
foreach ($file in $files) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path $path)) { Write-Error ("HTML file missing: {0}" -f $file); exit 1 }
    $text = Get-Content -Raw -LiteralPath $path
    foreach ($needle in @('<html', '<head', '<body')) {
        if ($text -notmatch [regex]::Escape($needle)) {
            Write-Error ("Missing basic HTML structure token {0} in {1}" -f $needle, $file)
            exit 1
        }
    }
}
Write-Host 'HTML structure check passed.'
exit 0
