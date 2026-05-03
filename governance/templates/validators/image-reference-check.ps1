param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$TargetFilesJson = '[]'
)

$ErrorActionPreference = 'Stop'

$files = @()

try {
    $parsed = ConvertFrom-Json -InputObject $TargetFilesJson -ErrorAction Stop

    if ($parsed -is [System.Array]) {
        $files = @($parsed | ForEach-Object { [string]$_ })
    }
    elseif ($null -ne $parsed) {
        $files = @([string]$parsed)
    }
}
catch {
    if (-not [string]::IsNullOrWhiteSpace($TargetFilesJson)) {
        if ($TargetFilesJson.Contains(',')) {
            $files = @(
                $TargetFilesJson.Split(',') |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }
        else {
            $files = @($TargetFilesJson.Trim())
        }
    }
}

if ($files.Count -eq 0) {
    Write-Error "No target files were provided."
    exit 1
}

$fail = $false

$patterns = @(
    '!\[[^\]]*\]\((?<target>[^)]+\.(?:png|jpg|jpeg|svg|gif|webp)(?:\?[^)]*)?)\)',
    '\[[^\]]+\]\((?<target>[^)]+\.(?:png|jpg|jpeg|svg|gif|webp)(?:\?[^)]*)?)\)',
    '(src|href)=["''](?<target>[^"'']+\.(?:png|jpg|jpeg|svg|gif|webp)(?:\?[^"'']*)?)["'']'
)

foreach ($file in $files) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path $path)) {
        Write-Error ("Target file not found: {0}" -f $file)
        exit 1
    }

    $text = Get-Content -Raw -LiteralPath $path
    $dir = Split-Path -Parent $path

    foreach ($pattern in $patterns) {
        $matches = [regex]::Matches($text, $pattern)
        foreach ($m in $matches) {
            $target = $m.Groups['target'].Value

            if ([string]::IsNullOrWhiteSpace($target)) { continue }
            if ($target -match '^(http|https|mailto):') { continue }
            if ($target.StartsWith('#')) { continue }

            $clean = $target.Split('?')[0].Split('#')[0]
            if ([string]::IsNullOrWhiteSpace($clean)) { continue }

            $dest = Join-Path $dir $clean
            if (-not (Test-Path $dest)) {
                Write-Error ("Missing asset referenced in {0}: {1}" -f $file, $target)
                $fail = $true
            }
        }
    }
}

if ($fail) { exit 1 }
Write-Host 'Image reference check passed.'
exit 0
