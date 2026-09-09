# Operations

## Windows lifecycle

The current-user scheduled task `Multica-PC-Runtime` starts at Windows sign-in
and runs the Multica daemon in the foreground. Task Scheduler can therefore
observe it and retry an ordinary unexpected exit up to ten times at one-minute
intervals. A separate one-minute repetition trigger recovers termination
states, including `0xC000013A`, that Windows does not classify as restartable
failures. Multiple-instance policy remains `IgnoreNew`, so a healthy daemon is
not duplicated. The task uses a Windows Script Host launcher so retries remain
windowless. Windows ends the task during sign-out or shutdown; the next sign-in
starts the same daemon identity and re-registers the existing provider runtimes
rather than creating new ones.

The PowerShell supervisor remains alive while the task is enabled, but the
Multica daemon is Docker-bound: it starts only after `docker info` succeeds and
is stopped when Docker becomes unavailable. Docker and Multica-server outages
are retried inside the windowless supervisor without spawning a visible console
on every attempt. Docker discovery uses the current process `PATH` with Docker
Desktop's stable installation path as a fallback, because a long-running Task
Scheduler process can inherit a stale environment. This keeps the PC operations
runtime aligned with the local service execution surface.

The fallback invokes Docker Desktop by its resolved absolute executable path.
This matters at sign-in: `docker.exe` may not yet be discoverable through the
scheduled process's inherited `PATH` even though Docker Desktop becomes ready
later. The supervisor continues polling that stable path and starts Multica
once `docker info` succeeds.

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
already-running unsupervised daemon; supervision takes over at the next sign-in.
Use `Restart` only after confirming that no Multica task is active because
stopping the daemon interrupts active local work.

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
