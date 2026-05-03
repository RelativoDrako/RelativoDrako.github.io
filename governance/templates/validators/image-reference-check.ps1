param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$TargetFilesJson = '[]'
)
$ErrorActionPreference = 'Stop'
$files = @($TargetFilesJson | ConvertFrom-Json)
$pattern = '([A-Za-z0-9_\-\/\.]+\.(png|jpg|jpeg|svg|gif|webp))'
$fail = $false
foreach ($file in $files) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path $path)) { Write-Error ("Target file not found: {0}" -f $file); exit 1 }
    $text = Get-Content -Raw -LiteralPath $path
    $matches = [regex]::Matches($text, $pattern)
    foreach ($m in $matches) {
        $asset = $m.Groups[1].Value
        if ($asset -match '^(http|https):') { continue }
        $dest = Join-Path (Split-Path -Parent $path) $asset
        if (-not (Test-Path $dest)) {
            Write-Error ("Missing asset referenced in {0}: {1}" -f $file, $asset)
            $fail = $true
        }
    }
}
if ($fail) { exit 1 }
Write-Host 'Image reference check passed.'
exit 0
