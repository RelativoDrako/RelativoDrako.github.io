param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$TargetFilesJson = '[]'
)
$ErrorActionPreference = 'Stop'
$files = @($TargetFilesJson | ConvertFrom-Json)
if ($files.Count -eq 0) { Write-Host 'No target files specified.'; exit 0 }
$pattern = '\[[^\]]+\]\(([^)]+)\)'
$fail = $false
foreach ($file in $files) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path $path)) { Write-Error ("Target file not found: {0}" -f $file); exit 1 }
    $text = Get-Content -Raw -LiteralPath $path
    $matches = [regex]::Matches($text, $pattern)
    foreach ($m in $matches) {
        $target = $m.Groups[1].Value
        if ($target -match '^(http|https|mailto):') { continue }
        if ($target.StartsWith('#')) { continue }
        $clean = $target.Split('#')[0]
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        $dest = Join-Path (Split-Path -Parent $path) $clean
        if (-not (Test-Path $dest)) {
            Write-Error ("Missing relative link target in {0}: {1}" -f $file, $target)
            $fail = $true
        }
    }
}
if ($fail) { exit 1 }
Write-Host 'Links check passed.'
exit 0
