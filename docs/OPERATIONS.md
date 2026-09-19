# Operations

## Windows lifecycle

The current-user scheduled task `Multica-PC-Runtime` starts at Windows sign-in
and repeats once per minute. Each invocation is a short-lived reconciliation:
it checks Docker, starts the existing Multica daemon identity when needed, or
stops it when Docker is unavailable, then exits. Multiple-instance policy is
`IgnoreNew`, so a still-running reconciliation is not duplicated. The task
uses a Windows Script Host launcher so each invocation remains windowless.
The next sign-in starts the same daemon identity and re-registers the existing
provider runtimes rather than creating new ones.

The Multica daemon is Docker-bound: it starts only after `docker info` succeeds
and is stopped when Docker becomes unavailable. Docker and Multica-server
outages are retried by later scheduled reconciliations without spawning a
visible console. Docker discovery uses the current process `PATH` with Docker
Desktop's stable installation path as a fallback. Each reconciliation also
gets a fresh process environment, avoiding stale CLI paths after Codex Desktop
or Docker Desktop updates.

The fallback invokes Docker Desktop by its resolved absolute executable path.
This matters at sign-in: `docker.exe` may not yet be discoverable through the
scheduled process's inherited `PATH` even though Docker Desktop becomes ready
later. The next scheduled reconciliation starts Multica once `docker info`
succeeds.

Each `docker info` readiness probe is executed without a visible window and has
a hard ten-second deadline. If the Docker client or engine stalls, the
reconciler terminates only that probe process and exits. The next one-minute
trigger tries again. Multica start and stop commands have a separate hard
30-second deadline. This prevents a stuck wrapper from suppressing every later
recovery trigger while Multica remains offline.

Sanitized reconciliation outcomes are retained in bounded rotating logs:

```text
C:\AgentRuntimes\pc-qwen-service\activation\supervisor.log
C:\AgentRuntimes\pc-qwen-service\activation\supervisor.previous.log
```

The supervisor uses these existing authorities:

```text
Multica profile: pc-qwen-service
Daemon ID:       e1f47508-6d16-43c6-ad47-a34edb029c89
Device name:     [Local] PC Qwen
Runtime name:    [Local] PC Qwen service
Workspace root:  C:\AgentRuntimes\pc-qwen-service
```

The historical names are retained to preserve identity. This is a daemon-backed
Codex runtime used to operate the PC Ollama/Qwen service; it is not a local Qwen
provider/client runtime.

Before starting the daemon, the supervisor resolves `codex.exe` from the
current process `PATH` or from Codex Desktop's versioned installation beneath
`%LOCALAPPDATA%\OpenAI\Codex\bin`. It similarly resolves `git.exe` from the
current process `PATH`, Git for Windows, or GitHub Desktop. It also resolves a
runnable `python3.exe` from the current process `PATH` or a per-user Python
installation beneath `%LOCALAPPDATA%\Programs\Python`; the Windows Store
application-execution alias is explicitly rejected. The selected directories
are prepended only to the scheduled process environment. This is required
because desktop applications can make their CLIs available to interactive
child processes without adding those versioned directories to the persistent
Windows `PATH` inherited by Task Scheduler. A missing required CLI causes a
nonzero exit so failure reporting and recovery remain effective.

## Install and operate

Run from a normal Windows PowerShell session:

```powershell
# Reconcile the scheduled task and start it when no daemon is already active.
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Install

# Read-only local daemon and provider-runtime status.
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Status

# Explicit lifecycle operations.
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Start
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Stop
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Restart
```

Use `-NoStart` with `Install` when reconciling task configuration during
maintenance; this leaves the scheduled task disabled so the recovery trigger
cannot start it. `Start` re-enables the task. Installation does not interrupt an
already-running unsupervised daemon; a later reconciliation observes it.
Use `Restart` only after confirming that no Multica task is active because
stopping the daemon interrupts active local work.

### Daemon starts but the runtime remains offline

The scheduled supervisor and the Multica daemon are separate health layers. A
running `Multica-PC-Runtime` task proves only that supervision is active. Check
the native daemon and workspace registration separately:

```powershell
C:\AgentRuntimes\pc-qwen-service\bin\multica.exe --profile pc-qwen-service daemon status
C:\AgentRuntimes\pc-qwen-service\bin\multica.exe --profile pc-qwen-service runtime list
```

Daemon diagnostics are retained outside Git under the profile directory:

```text
%USERPROFILE%\.multica\profiles\pc-qwen-service\daemon.log
%USERPROFILE%\.multica\profiles\pc-qwen-service\daemon.err.log
```

The validated CLI version is `0.5.0`. Version `0.4.36` was observed starting,
authenticating, and opening `127.0.0.1:20012`, then exiting after authenticated
token-renewal and `/api/daemon/workspaces` timeouts. The supervisor correctly
retried it, but retries could not make that incompatible daemon path healthy.
If this exact signature recurs, first confirm Docker and the self-hosted server
are reachable, stop the scheduled supervisor, use the CLI's supported `update`
command, and restart the existing scheduled task. Preserve the profile, daemon
ID, workspace root, and credentials; do not create a replacement runtime.

`Uninstall` removes only the scheduled task after stopping the daemon. It does
not delete the runtime root, profile, credentials, task workspaces, or remote
runtime records.

## Provider health

`Status` reports three separate conditions:

1. scheduled-task supervision state;
2. native daemon state;
3. the native Codex runtime row returned by the Multica workspace.

The Codex runtime is registered directly by the daemon. Multica also projects
the workspace-visible `R38 Qwen Reserved` profile onto this daemon, producing
an inert offline PC registration row when `qwen-r38-reserved` is unavailable.
That row does not represent a local Qwen installation, agent, credential, model,
or required provider runtime, and its offline state is not a daemon failure.

Reservation-backed Qwen clients run on the private R38 runtime and consume the
PC Ollama/Qwen service remotely. Provisioning a second PC-local Qwen provider
runtime is outside this repository's scope.

Do not put the Multica PAT, profile `config.json`, environment secrets, provider
credentials, prompts, or task artifacts in this repository or command output.
