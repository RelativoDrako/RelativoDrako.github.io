[CmdletBinding()]
param(
    [Alias("help","h")]
    [switch]$ShowHelp,

    [ValidateSet(
        "CleanHistoryPublish",
        "ListBackupBranches",
        "DeleteBackupBranches"
    )]
    [string]$Mode = "CleanHistoryPublish",

    [string]$Branch = "main",
    [string]$Remote = "origin",
    [string]$CommitMessage = "Polish repository presentation and publish a clean canonical update",

    [switch]$AllowInit,
    [switch]$Push,
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$ApplyLocal,
    [switch]$AllowDirtyWorktree,
    [switch]$CI,
    [switch]$SkipFetch,
    [switch]$DeleteRemoteBackups,
    [switch]$DeleteLocalBackups,
    [switch]$PruneAfterDelete,

    [string]$AutoSetRemoteUrl,
    [string[]]$RequiredPaths = @("README.md"),
    [string[]]$ExcludeNames = @(
        ".git",
        ".gitlab",
        ".idea",
        ".vscode",
        "__pycache__",
        ".venv",
        "venv",
        "node_modules",
        "dist",
        "build",
        "coverage",
        "output",
        "logs",
        ".deploy.lock"
    ),
    [string]$BackupPrefix = "backup/pre-clean-"
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
    Write-Host " Clean History Deploy Utility - Daniel Franco Fajardo" -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor DarkCyan
    Write-Host "Use only for curated public editorial repositories."
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\deploy_clean.ps1 -ShowHelp"
    Write-Host "  .\deploy_clean.ps1 -DryRun"
    Write-Host "  .\deploy_clean.ps1"
    Write-Host "  .\deploy_clean.ps1 -ApplyLocal"
    Write-Host "  .\deploy_clean.ps1 -Push -NoBackup"
    Write-Host "  .\deploy_clean.ps1 -Mode ListBackupBranches"
    Write-Host "  .\deploy_clean.ps1 -Mode DeleteBackupBranches -DeleteRemoteBackups -PruneAfterDelete"
    Write-Host ""
    Write-Host "Behavior:" -ForegroundColor Yellow
    Write-Host "  - no -Push and no -ApplyLocal => keep result in review branch only"
    Write-Host "  - -ApplyLocal                 => replace local main"
    Write-Host "  - -Push                       => replace local main and publish"
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

function Assert-CleanWorkingTreeForSnapshot {
    if ($AllowDirtyWorktree) {
        Write-Step -Message "AllowDirtyWorktree enabled. Proceeding with current local modifications." -Level "WARN"
        return
    }

    $status = Invoke-Git -Args @("status","--porcelain") -Capture -AllowFailure
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        Fail "Working tree is dirty. Commit or stash changes first, or rerun with -AllowDirtyWorktree if you intentionally want to snapshot uncommitted changes."
    }
}

function Test-HasCommits {
    $result = Invoke-Git -Args @("rev-parse","--verify","HEAD") -Capture -AllowFailure
    return -not [string]::IsNullOrWhiteSpace($result)
}

function Get-LockPath {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    $repoName = Split-Path $RepoRoot -Leaf
    return (Join-Path $env:TEMP ("deploy_" + $repoName + ".lock"))
}

function Export-Snapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$SnapshotDir
    )

    New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null

    Get-ChildItem -LiteralPath $SourceDir -Force | Where-Object {
        -not ($ExcludeNames -contains $_.Name)
    } | ForEach-Object {
        $destination = Join-Path $SnapshotDir $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
        }
    }
}

function Clear-WorkingTree {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)
    Get-ChildItem -LiteralPath $RepoRoot -Force | Where-Object { $_.Name -ne ".git" } | Remove-Item -Recurse -Force
}

function Restore-Snapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotDir,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    Get-ChildItem -LiteralPath $SnapshotDir -Force | ForEach-Object {
        $destination = Join-Path $RepoRoot $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
        } else {
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
        }
    }
}

function Get-RemoteMainSha {
    $line = Invoke-Git -Args @("ls-remote","--heads",$Remote,$Branch) -Capture -AllowFailure
    if ([string]::IsNullOrWhiteSpace($line)) { return "" }
    $firstLine = ($line -split "`n")[0].Trim()
    if ([string]::IsNullOrWhiteSpace($firstLine)) { return "" }
    return ($firstLine -split "`t")[0].Trim()
}

function Get-BackupBranches {
    $results = New-Object System.Collections.Generic.List[string]

    $local = Invoke-Git -Args @("for-each-ref","--format=%(refname:short)","refs/heads") -Capture -AllowFailure
    if (-not [string]::IsNullOrWhiteSpace($local)) {
        foreach ($line in ($local -split "`n")) {
            $name = $line.Trim()
            if (-not [string]::IsNullOrWhiteSpace($name) -and $name -like "$BackupPrefix*") {
                [void]$results.Add("local::" + $name)
            }
        }
    }

    $remoteLines = Invoke-Git -Args @("ls-remote","--heads",$Remote) -Capture -AllowFailure
    if (-not [string]::IsNullOrWhiteSpace($remoteLines)) {
        foreach ($line in ($remoteLines -split "`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split "`t"
            if ($parts.Count -lt 2) { continue }
            $ref = $parts[1].Trim()
            if ($ref -like "refs/heads/$BackupPrefix*") {
                $name = $ref -replace "^refs/heads/",""
                [void]$results.Add("remote::" + $name)
            }
        }
    }

    return @($results)
}

function List-BackupBranchesFlow {
    Write-Step -Message "Listing backup branches."
    $branches = @(Get-BackupBranches)

    if ($branches.Count -eq 0) {
        Write-Step -Message "No backup branches found." -Level "OK"
        return
    }

    foreach ($b in $branches) {
        Write-Host $b
    }
}

function Delete-BackupBranchesFlow {
    if (-not $DeleteLocalBackups -and -not $DeleteRemoteBackups) {
        Fail "DeleteBackupBranches requires -DeleteLocalBackups, -DeleteRemoteBackups, or both."
    }

    Write-Step -Message "Deleting backup branches."
    $branches = @(Get-BackupBranches)

    if ($branches.Count -eq 0) {
        Write-Step -Message "No backup branches found." -Level "OK"
        return
    }

    foreach ($entry in $branches) {
        $parts = $entry -split "::", 2

        if ($parts.Count -ne 2) {
            Write-Step -Message ("Skipping malformed backup entry: " + $entry) -Level "WARN"
            continue
        }

        $scope = $parts[0].Trim()
        $name  = $parts[1].Trim()

        if ([string]::IsNullOrWhiteSpace($name)) {
            Write-Step -Message ("Skipping empty backup entry: " + $entry) -Level "WARN"
            continue
        }

        if ($scope -eq "local" -and $DeleteLocalBackups) {
            Write-Step -Message ("Deleting local backup branch: " + $name)
            Invoke-Git -Args @("branch","-D",$name) -AllowFailure
        }

        if ($scope -eq "remote" -and $DeleteRemoteBackups) {
            Write-Step -Message ("Deleting remote backup branch: " + $name)
            Invoke-Git -Args @("push",$Remote,"--delete",$name) -AllowFailure
        }
    }

    if ($PruneAfterDelete) {
        Write-Step -Message "Pruning remote references."
        Invoke-Git -Args @("fetch",$Remote,"--prune") -AllowFailure
    }

    Write-Step -Message "Backup branch cleanup completed." -Level "OK"
}

function Confirm-ForcePush {
    if ($CI -or $DryRun) { return }

    Write-Host ""
    Write-Host "WARNING: This will rewrite the history of '$Branch'." -ForegroundColor Yellow
    $resp = Read-Host "Type YES to continue"
    if ($resp -ne "YES") {
        Fail "Operation cancelled by user."
    }
}

function Publish-Clean {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $lock = Get-LockPath -RepoRoot $RepoRoot
    if ((Test-Path $lock) -and -not $DryRun) {
        Fail ("Another deploy process seems active: " + $lock)
    }

    if (-not $DryRun) {
        New-Item -Path $lock -ItemType File -Force | Out-Null
    }

    $hasCommits = Test-HasCommits
    $originalBranch = ""
    $remoteShaBefore = ""

    if (-not $DryRun) {
        $originalBranch = (Invoke-Git -Args @("rev-parse","--abbrev-ref","HEAD") -Capture -AllowFailure).Trim()
    }

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupBranch = "$BackupPrefix$Branch-$ts"
    $tempBranch = "__clean_publish_$ts"
    $tmp = Join-Path $env:TEMP ("deploy_" + [guid]::NewGuid().ToString("N"))
    $snapshot = Join-Path $tmp "snapshot"

    try {
        Ensure-Remote

        if (-not $SkipFetch) {
            Write-Step -Message "Fetching remote refs."
            Invoke-Git -Args @("fetch",$Remote,"--prune") -AllowFailure
        }

        $remoteShaBefore = Get-RemoteMainSha

        Write-Step -Message "Exporting working tree snapshot."
        if (-not $DryRun) {
            Export-Snapshot -SourceDir $RepoRoot -SnapshotDir $snapshot
        } else {
            Write-Step -Message "[DRY-RUN] export current working tree snapshot" -Level "WARN"
        }

        if (($Push -or $ApplyLocal) -and $hasCommits -and -not $NoBackup) {
            Write-Step -Message ("Creating backup branch: " + $backupBranch)
            Invoke-Git -Args @("branch",$backupBranch)
        }

        Write-Step -Message ("Creating orphan branch: " + $tempBranch)
        Invoke-Git -Args @("checkout","--orphan",$tempBranch)

        Write-Step -Message "Clearing working tree on orphan branch."
        if (-not $DryRun) {
            Clear-WorkingTree -RepoRoot $RepoRoot
        } else {
            Write-Step -Message "[DRY-RUN] clear working tree except .git" -Level "WARN"
        }

        Write-Step -Message "Restoring curated snapshot into orphan branch."
        if (-not $DryRun) {
            Restore-Snapshot -SnapshotDir $snapshot -RepoRoot $RepoRoot
        } else {
            Write-Step -Message "[DRY-RUN] restore snapshot into orphan branch" -Level "WARN"
        }

        Write-Step -Message "Creating clean canonical commit."
        Invoke-Git -Args @("add","-A")
        Invoke-Git -Args @("commit","-m",$CommitMessage)

        if ($Push -or $ApplyLocal) {
            Write-Step -Message ("Replacing local branch '" + $Branch + "' with the cleaned orphan branch.")
            Invoke-Git -Args @("branch","-D",$Branch) -AllowFailure
            Invoke-Git -Args @("branch","-M",$Branch)
        } else {
            Write-Step -Message ("Leaving clean snapshot in review branch: " + $tempBranch) -Level "WARN"
            Write-Step -Message "Recommended action: inspect the review branch, then rerun with -ApplyLocal or -Push if approved." -Level "WARN"
        }

        if ($Push) {
            Confirm-ForcePush

            $remoteShaNow = Get-RemoteMainSha
            if ($remoteShaBefore -ne $remoteShaNow) {
                Fail ("Remote '" + $Remote + "/" + $Branch + "' changed during execution. Fetch, inspect remote state, and rerun only if still required.")
            }

            if ([string]::IsNullOrWhiteSpace($remoteShaNow)) {
                Write-Step -Message "Remote branch does not exist yet. Publishing initial branch."
                Invoke-Git -Args @("push","-u",$Remote,$Branch)
            } else {
                Write-Step -Message ("Publishing rewritten '" + $Branch + "' with --force-with-lease.")
                Invoke-Git -Args @("push","--force-with-lease",$Remote,$Branch)
            }

            if ($hasCommits -and -not $NoBackup) {
                Write-Step -Message ("Pushing backup branch: " + $backupBranch)
                Invoke-Git -Args @("push",$Remote,$backupBranch) -AllowFailure
            }
        } else {
            Write-Step -Message "Push not requested. Clean result remains local only."
        }

        Write-Step -Message "Clean-history flow completed." -Level "OK"
    }
    catch {
        Write-Step -Message "Error detected. Attempting rollback." -Level "ERROR"
        if (-not $DryRun -and -not [string]::IsNullOrWhiteSpace($originalBranch)) {
            Invoke-Git -Args @("checkout",$originalBranch) -AllowFailure
        }
        throw
    }
    finally {
        if (Test-Path $tmp) {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $lock) {
            Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
        }
    }
}

function Main {
    if ($ShowHelp) {
        Show-Intro
        return
    }

    Show-Intro
    Ensure-Git
    $root = Ensure-Repository
    Assert-NoMergeConflicts
    Assert-RequiredPaths

    if ($Mode -eq "CleanHistoryPublish") {
        Assert-CleanWorkingTreeForSnapshot
    }

    switch ($Mode) {
        "CleanHistoryPublish"  { Publish-Clean -RepoRoot $root }
        "ListBackupBranches"   { Ensure-Remote; List-BackupBranchesFlow }
        "DeleteBackupBranches" { Ensure-Remote; Delete-BackupBranchesFlow }
        default                { Fail ("Unsupported mode: " + $Mode) }
    }

    Write-Host ""
    Write-Host "Validation:" -ForegroundColor Yellow
    Write-Host "  .\deploy_clean.ps1 -ShowHelp"
    Write-Host "  git log --oneline --decorate -n 5"
    Write-Host "  git status"
    Write-Host "  git branch --list"
}

Main