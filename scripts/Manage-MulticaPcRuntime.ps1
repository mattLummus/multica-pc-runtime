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
            -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $quotedScript -Action RunForeground" `
            -WorkingDirectory $env:SystemRoot
        $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
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
            -Trigger $taskTrigger `
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
        if (-not $NoStart) {
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
