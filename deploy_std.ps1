[CmdletBinding()]
param(
    [Alias("help","h")]
    [switch]$ShowHelp,

    [string]$Branch = "main",
    [string]$Remote = "origin",
    [string]$CommitMessage = "Publish reviewed update",

    [switch]$AllowInit,
    [switch]$Push,
    [switch]$DryRun,
    [switch]$CI,

    [string]$AutoSetRemoteUrl,
    [string[]]$RequiredPaths = @("README.md")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO","WARN","OK","ERROR")][string]$Level = "INFO"
    )

    if ($CI) {
        Write-Host "[$Level] $Message"
        return
    }

    $color = switch ($Level) {
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        "ERROR" { "Red" }
        default { "Cyan" }
    }

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts][$Level] $Message" -ForegroundColor $color
}

function Fail {
    param([Parameter(Mandatory = $true)][string]$Message)
    throw $Message
}

function Show-Intro {
    if ($CI) { return }

    Write-Host ""
    Write-Host "====================================================" -ForegroundColor DarkCyan
    Write-Host " Standard Publish Utility - Daniel Franco Fajardo" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor DarkCyan
    Write-Host "Use for repositories where commit history must remain intact."
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\deploy_std.ps1 -ShowHelp"
    Write-Host "  .\deploy_std.ps1 -DryRun"
    Write-Host "  .\deploy_std.ps1 -Push"
    Write-Host "  .\deploy_std.ps1 -AllowInit -Push"
    Write-Host ""
}

function Test-IsMutatingGitCommand {
    param([Parameter(Mandatory = $true)][string[]]$Args)

    if ($Args.Count -eq 0) { return $false }

    switch ($Args[0]) {
        "init"     { return $true }
        "checkout" { return $true }
        "switch"   { return $true }
        "restore"  { return $true }
        "add"      { return $true }
        "commit"   { return $true }
        "merge"    { return $true }
        "rebase"   { return $true }
        "tag"      { return $true }
        "push"     { return $true }
        "pull"     { return $true }
        "clone"    { return $true }
        "fetch"    { return $true }
        "remote" {
            if ($Args.Count -ge 2 -and $Args[1] -in @("add","remove","rm","rename","set-url")) {
                return $true
            }
            return $false
        }
        "branch" {
            if ($Args.Count -ge 2 -and $Args[1] -match "^-") {
                return $true
            }
            return $false
        }
        default { return $false }
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]]$Args,
        [switch]$Capture,
        [switch]$AllowFailure
    )

    $cmd = "git " + ($Args -join " ")
    $isMutating = Test-IsMutatingGitCommand -Args $Args

    if ($DryRun -and $isMutating) {
        Write-Step -Message ("[DRY-RUN] " + $cmd) -Level "WARN"
        if ($Capture) { return "" }
        return
    }

    if ($Capture) {
        $output = & git @Args 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -and -not $AllowFailure) {
            Fail ("Git failed: " + $cmd + "`n" + ($output -join "`n"))
        }
        return ($output -join "`n")
    }

    & git @Args
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Fail ("Git failed: " + $cmd)
    }
}

function Ensure-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Fail "git is not available in PATH."
    }
}

function Test-GitRepository {
    $result = Invoke-Git -Args @("rev-parse","--show-toplevel") -Capture -AllowFailure
    return -not [string]::IsNullOrWhiteSpace($result)
}

function Get-RepositoryRoot {
    $root = Invoke-Git -Args @("rev-parse","--show-toplevel") -Capture -AllowFailure
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }
    return $root.Trim()
}

function Ensure-Repository {
    if (-not (Test-GitRepository)) {
        if (-not $AllowInit) {
            Fail "No git repository detected. Re-run with -AllowInit to initialize intentionally."
        }

        Write-Step -Message "Initializing repository."
        Invoke-Git -Args @("init")
    }

    $root = Get-RepositoryRoot
    if ([string]::IsNullOrWhiteSpace($root)) {
        $root = (Get-Location).Path
    } else {
        Set-Location $root
    }

    Write-Step -Message ("Repository root: " + $root)
    return $root
}

function Ensure-Remote {
    $url = Invoke-Git -Args @("remote","get-url",$Remote) -Capture -AllowFailure
    if (-not [string]::IsNullOrWhiteSpace($url)) { return }

    if (-not $AutoSetRemoteUrl) {
        Fail ("Remote '" + $Remote + "' does not exist. Re-run with -AutoSetRemoteUrl.")
    }

    Write-Step -Message ("Configuring remote '" + $Remote + "' -> " + $AutoSetRemoteUrl)
    Invoke-Git -Args @("remote","add",$Remote,$AutoSetRemoteUrl)
}

function Ensure-BranchCheckedOut {
    if ($DryRun) {
        $current = (Invoke-Git -Args @("rev-parse","--abbrev-ref","HEAD") -Capture -AllowFailure).Trim()
        Write-Step -Message ("[DRY-RUN] current branch: " + $current + " ; target branch: " + $Branch) -Level "WARN"
        return
    }

    $current = (Invoke-Git -Args @("rev-parse","--abbrev-ref","HEAD") -Capture -AllowFailure).Trim()

    if ($current -eq "HEAD") {
        & git checkout -B $Branch
        if ($LASTEXITCODE -ne 0) {
            Fail ("Failed to check out '" + $Branch + "' from detached HEAD.")
        }
        return
    }

    $exists = Invoke-Git -Args @("show-ref","--verify","refs/heads/$Branch") -Capture -AllowFailure
    if (-not [string]::IsNullOrWhiteSpace($exists)) {
        & git checkout $Branch
        if ($LASTEXITCODE -ne 0) {
            Fail ("Failed to check out existing '" + $Branch + "'.")
        }
    } else {
        & git checkout -b $Branch
        if ($LASTEXITCODE -ne 0) {
            Fail ("Failed to create '" + $Branch + "'.")
        }
    }
}

function Assert-RequiredPaths {
    $missing = @($RequiredPaths | Where-Object { -not (Test-Path $_) })
    if ($missing.Count -gt 0) {
        Fail ("Missing required files or folders:`n- " + ($missing -join "`n- "))
    }
}

function Assert-NoMergeConflicts {
    $status = Invoke-Git -Args @("status","--porcelain") -Capture -AllowFailure
    if ($status -match '(^|\n)UU ') {
        Fail "Unresolved merge conflicts detected. Resolve them before deploy."
    }
}

function Test-HasCommits {
    $result = Invoke-Git -Args @("rev-parse","--verify","HEAD") -Capture -AllowFailure
    return -not [string]::IsNullOrWhiteSpace($result)
}

function Assert-PushIsFastForwardSafe {
    Ensure-Remote

    $remoteRef = "{0}/{1}" -f $Remote, $Branch

    Write-Step -Message "Fetching remote refs before push validation."
    Invoke-Git -Args @("fetch",$Remote,"--prune") -AllowFailure

    $localSha  = (Invoke-Git -Args @("rev-parse",$Branch) -Capture -AllowFailure).Trim()
    $remoteSha = (Invoke-Git -Args @("rev-parse",$remoteRef) -Capture -AllowFailure).Trim()

    if ([string]::IsNullOrWhiteSpace($remoteSha)) {
        Write-Step -Message "Remote branch does not exist yet. Initial push is allowed." -Level "WARN"
        return
    }

    $baseSha = (Invoke-Git -Args @("merge-base",$Branch,$remoteRef) -Capture -AllowFailure).Trim()

    if ($localSha -eq $remoteSha) {
        Write-Step -Message "Local and remote branch are aligned." -Level "OK"
        return
    }

    if ($baseSha -eq $remoteSha) {
        Write-Step -Message "Local branch is ahead of remote. Fast-forward push is allowed." -Level "OK"
        return
    }

    if ($baseSha -eq $localSha) {
        Fail ("Local '" + $Branch + "' is behind '" + $remoteRef + "'. Pull or reset before standard push.")
    }

    Fail ("Local '" + $Branch + "' and '" + $remoteRef + "' have diverged. If this came from deploy_clean -ApplyLocal, publish with deploy_clean -Push instead of deploy_std.")
}

function Publish-Standard {
    Write-Step -Message "Mode: StandardPublish"
    Ensure-BranchCheckedOut

    $hasCommits = Test-HasCommits
    $statusBefore = Invoke-Git -Args @("status","--porcelain") -Capture -AllowFailure

    if ([string]::IsNullOrWhiteSpace($statusBefore) -and $hasCommits) {
        Write-Step -Message "No changes detected. Nothing to commit." -Level "OK"
    } else {
        Write-Step -Message "Staging repository content."
        Invoke-Git -Args @("add","-A")

        $statusAfter = Invoke-Git -Args @("status","--porcelain") -Capture -AllowFailure
        if ([string]::IsNullOrWhiteSpace($statusAfter) -and $hasCommits) {
            Write-Step -Message "Nothing new to commit after staging." -Level "OK"
        } else {
            Write-Step -Message "Creating commit."
            Invoke-Git -Args @("commit","-m",$CommitMessage)
        }
    }

    if ($Push) {
        Assert-PushIsFastForwardSafe
        Write-Step -Message ("Publishing to " + $Remote + "/" + $Branch)
        Invoke-Git -Args @("push","-u",$Remote,$Branch)
    } else {
        Write-Step -Message "Push not requested. Review locally, then publish when ready."
    }
}

function Main {
    if ($ShowHelp) {
        Show-Intro
        return
    }

    Show-Intro
    Ensure-Git
    $null = Ensure-Repository
    Assert-NoMergeConflicts
    Assert-RequiredPaths
    Publish-Standard

    Write-Host ""
    Write-Host "Validation:" -ForegroundColor Yellow
    Write-Host "  .\deploy_std.ps1 -ShowHelp"
    Write-Host "  git log --oneline --decorate -n 5"
    Write-Host "  git status"
    Write-Host "  git branch --list"
}

Main