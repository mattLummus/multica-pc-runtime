# Operations

## Windows lifecycle

The current-user scheduled task `Multica-PC-Runtime` starts at Windows sign-in
and runs the Multica daemon in the foreground. Task Scheduler can therefore
observe it and retry an unexpected exit up to ten times at one-minute
intervals. Windows ends the task during sign-out or shutdown; the next sign-in
starts the same daemon identity and re-registers the existing provider
runtimes rather than creating new ones.

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
`%LOCALAPPDATA%\OpenAI\Codex\bin`. The selected directory is prepended only to
the scheduled process environment. This is required because Codex Desktop can
make its CLI available to interactive child processes without adding that
versioned directory to the persistent Windows `PATH` inherited by Task
Scheduler. If no installed Codex CLI can be found, the task exits nonzero so
its configured retry and failure reporting remain effective.

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
maintenance. Installation does not interrupt an already-running unsupervised
daemon; supervision takes over at the next sign-in. Use `Restart` only after
confirming that no Multica task is active because stopping the daemon interrupts
active local work.

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
