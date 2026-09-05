[CmdletBinding()]
param(
    [ValidateSet('Install', 'Start', 'Stop', 'Restart', 'Status', 'RunForeground', 'Uninstall')]
    [string]$Action = 'Status',

    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'

$TaskName = 'Multica-PC-Runtime'
$LegacyTaskName = 'Multica-PC-Qwen-Service'
$ProfileName = 'pc-qwen-service'
$DaemonId = 'e1f47508-6d16-43c6-ad47-a34edb029c89'
$DeviceName = '[Local] PC Qwen'
$RuntimeName = '[Local] PC Qwen service'
$RuntimeRoot = 'C:\AgentRuntimes\pc-qwen-service'
$CodexRuntimeId = '713a5202-c384-4cf0-8190-876e36f8bdcf'
$RecoveryIntervalMinutes = 1
$MulticaPath = Join-Path $RuntimeRoot 'bin\multica.exe'
$ActivationRoot = Join-Path $RuntimeRoot 'activation'
$DeployedScript = Join-Path $ActivationRoot 'Manage-MulticaPcRuntime.ps1'

function Assert-Installation {
    if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
        throw "Approved runtime root is missing: $RuntimeRoot"
    }
    if (-not (Test-Path -LiteralPath $MulticaPath -PathType Leaf)) {
        throw "Multica executable is missing from the approved runtime root: $MulticaPath"
    }
}

function Add-CodexCliToProcessPath {
    $existing = Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($existing) {
        return $existing.Source
    }

    $codexBinRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $candidates = @(
        Get-ChildItem -LiteralPath $codexBinRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $candidate = Join-Path $_.FullName 'codex.exe'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Get-Item -LiteralPath $candidate
                }
            } |
            Sort-Object LastWriteTimeUtc -Descending
    )

    if ($candidates.Count -eq 0) {
        throw "No Codex CLI installation was found under the supported Codex Desktop location: $codexBinRoot"
    }

    $codexPath = $candidates[0].FullName
    $codexDirectory = Split-Path -Parent $codexPath
    $pathEntries = @($env:PATH -split [IO.Path]::PathSeparator)
    if ($pathEntries -notcontains $codexDirectory) {
        $env:PATH = $codexDirectory + [IO.Path]::PathSeparator + $env:PATH
    }

    $resolved = Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $resolved) {
        throw 'The Codex CLI was found but could not be resolved after updating the daemon process PATH.'
    }

    return $resolved.Source
}

function Add-GitCliToProcessPath {
    $existing = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($existing) {
        return $existing.Source
    }

    $candidates = @()
    $programFilesGit = Join-Path $env:ProgramFiles 'Git\cmd\git.exe'
    if (Test-Path -LiteralPath $programFilesGit -PathType Leaf) {
        $candidates += Get-Item -LiteralPath $programFilesGit
    }

    $githubDesktopRoot = Join-Path $env:LOCALAPPDATA 'GitHubDesktop'
    $candidates += @(
        Get-ChildItem -LiteralPath $githubDesktopRoot -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
            ForEach-Object {
                $candidate = Join-Path $_.FullName 'resources\app\git\cmd\git.exe'
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Get-Item -LiteralPath $candidate
                }
            }
    )
    $candidates = @($candidates | Sort-Object LastWriteTimeUtc -Descending)

    if ($candidates.Count -eq 0) {
        throw 'No supported Git CLI installation was found in Program Files or GitHub Desktop.'
    }

    $gitPath = $candidates[0].FullName
    $gitDirectory = Split-Path -Parent $gitPath
    $pathEntries = @($env:PATH -split [IO.Path]::PathSeparator)
    if ($pathEntries -notcontains $gitDirectory) {
        $env:PATH = $gitDirectory + [IO.Path]::PathSeparator + $env:PATH
    }

    $resolved = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $resolved) {
        throw 'The Git CLI was found but could not be resolved after updating the daemon process PATH.'
    }

    return $resolved.Source
}

function Add-RequiredCliToolsToProcessPath {
    Add-CodexCliToProcessPath | Out-Null
    Add-GitCliToProcessPath | Out-Null
}

function Invoke-Multica {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$DiscardOutput
    )

    Assert-Installation
    Push-Location $env:SystemRoot
    try {
        if ($DiscardOutput) {
            & $MulticaPath --profile $ProfileName @Arguments *> $null
        }
        else {
            & $MulticaPath --profile $ProfileName @Arguments | Out-Host
        }
        return [int]$LASTEXITCODE
    }
    finally {
        Pop-Location
    }
}

function Get-MulticaDaemonProcess {
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -eq $MulticaPath
    }
}

function Get-RuntimeRows {
    Assert-Installation
    Push-Location $env:SystemRoot
    try {
        $rows = & $MulticaPath --profile $ProfileName runtime list
        if ($LASTEXITCODE -ne 0) {
            throw "Multica runtime list failed with exit code $LASTEXITCODE"
        }
        $row = $rows | Select-String -SimpleMatch $CodexRuntimeId
        if ($row) {
            Write-Output $row.Line
        }
        else {
            Write-Output "$CodexRuntimeId  not_returned"
        }
    }
    finally {
        Pop-Location
    }
}

function Get-DaemonStatus {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Output "scheduled_task=$($task.State.ToString().ToLowerInvariant())"
    }
    else {
        Write-Output 'scheduled_task=not_installed'
    }
    $exitCode = Invoke-Multica -Arguments @('daemon', 'status')
    if ($exitCode -ne 0) {
        throw "Multica daemon status failed with exit code $exitCode"
    }
    Get-RuntimeRows
}

function Start-SupervisedDaemon {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        throw "Scheduled task '$TaskName' is not installed. Run with -Action Install first."
    }
    if (-not $task.Settings.Enabled) {
        Enable-ScheduledTask -TaskName $TaskName | Out-Null
        $task = Get-ScheduledTask -TaskName $TaskName
    }
    if ($task.State -eq 'Running') {
        Write-Output 'supervised_daemon=already_running'
        return
    }
    if (Get-MulticaDaemonProcess) {
        Write-Output 'daemon=already_running_unsupervised'
        Write-Output 'supervision=will_take_over_at_next_sign_in'
        return
    }
    Start-ScheduledTask -TaskName $TaskName
    Write-Output 'supervised_daemon=start_requested'
}

function Stop-SupervisedDaemon {
    Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
    $exitCode = Invoke-Multica -Arguments @('daemon', 'stop')
    if ($exitCode -ne 0) {
        throw "Multica daemon stop failed with exit code $exitCode"
    }
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

switch ($Action) {
    'Install' {
        Assert-Installation
        New-Item -ItemType Directory -Path $ActivationRoot -Force | Out-Null
        $source = $MyInvocation.MyCommand.Path
        if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($DeployedScript)) {
            Copy-Item -LiteralPath $source -Destination $DeployedScript -Force
        }

        $powerShellPath = (Get-Command powershell.exe).Source
        $quotedScript = '"{0}"' -f $DeployedScript
        $taskAction = New-ScheduledTaskAction `
            -Execute $powerShellPath `
            -Argument "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $quotedScript -Action RunForeground" `
            -WorkingDirectory $env:SystemRoot
        $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $recoveryTrigger = New-ScheduledTaskTrigger `
            -Once `
            -At (Get-Date).AddMinutes($RecoveryIntervalMinutes) `
            -RepetitionInterval (New-TimeSpan -Minutes $RecoveryIntervalMinutes) `
            -RepetitionDuration (New-TimeSpan -Days 3650)
        $taskPrincipal = New-ScheduledTaskPrincipal `
            -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
            -LogonType Interactive `
            -RunLevel Limited
        $taskSettings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RestartCount 10 `
            -RestartInterval (New-TimeSpan -Minutes 1) `
            -ExecutionTimeLimit ([TimeSpan]::Zero) `
            -MultipleInstances IgnoreNew

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $taskAction `
            -Trigger @($taskTrigger, $recoveryTrigger) `
            -Principal $taskPrincipal `
            -Settings $taskSettings `
            -Description 'Supervises the native PC Multica Codex runtime used for PC service operations.' `
            -Force | Out-Null

        $legacy = Get-ScheduledTask -TaskName $LegacyTaskName -ErrorAction SilentlyContinue
        if ($legacy -and $legacy.State -ne 'Running') {
            Unregister-ScheduledTask -TaskName $LegacyTaskName -Confirm:$false
        }

        Write-Output "installed_task=$TaskName"
        Write-Output "runtime_root=$RuntimeRoot"
        if ($NoStart) {
            Disable-ScheduledTask -TaskName $TaskName | Out-Null
            Write-Output 'supervision=disabled'
        }
        else {
            Start-SupervisedDaemon
        }
    }
    'Start' {
        Start-SupervisedDaemon
    }
    'Stop' {
        Stop-SupervisedDaemon
    }
    'Restart' {
        Stop-SupervisedDaemon
        Start-Sleep -Seconds 1
        Start-SupervisedDaemon
    }
    'Status' {
        Get-DaemonStatus
    }
    'RunForeground' {
        Add-RequiredCliToolsToProcessPath
        $exitCode = Invoke-Multica -DiscardOutput -Arguments @(
            'daemon', 'start',
            '--foreground',
            '--daemon-id', $DaemonId,
            '--device-name', $DeviceName,
            '--runtime-name', $RuntimeName,
            '--workspaces-root', $RuntimeRoot,
            '--no-auto-update'
        )
        exit $exitCode
    }
    'Uninstall' {
        Stop-SupervisedDaemon
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Output "removed_task=$TaskName"
    }
}
