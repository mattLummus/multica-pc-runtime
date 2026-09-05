# Multica PC Runtime

Version-controlled lifecycle authority for the native Windows Multica runtime
on Matt's PC. This repository is intentionally separate from both
`ollama-windows-bridge` and the generated runtime root.

## Boundaries

This repository owns:

- current-user Windows startup and supervision for the Multica daemon;
- reproducible installation, status, start, stop, and restart commands;
- documentation of the existing PC runtime identities and their provider
  activation requirements.

It does **not** own:

- Ollama, the Qwen proxy, reservations, ports, models, or credentials;
- Multica task workspaces, caches, downloaded binaries, or task artifacts;
- provider-specific launch wrappers maintained by their source repositories.

The generated installation remains at:

```text
C:\AgentRuntimes\pc-qwen-service
```

That root is not a Git repository. Installation copies the reviewed supervisor
into its `activation` directory so Windows startup does not depend on this
checkout remaining at a particular path.

At startup, the supervisor locates the current Codex Desktop CLI and a supported
Git CLI, then adds their versioned directories to the daemon process
environment. It does not change the persistent user or machine `PATH`, and it
does not hard-code an application release directory that an update can replace.

The scheduled task has both a sign-in trigger and a one-minute recovery
trigger. The latter restores the daemon after termination modes that Windows
does not classify as a restartable failure. An intentional `Stop` disables the
task first, while `Start` re-enables supervision.

## Native runtime inventory

| Provider | Runtime ID | Current role |
|---|---|---|
| Codex | `713a5202-c384-4cf0-8190-876e36f8bdcf` | Direct runtime registered by the native daemon |

The existing profile and device names contain `Qwen` because this Codex runtime
operates the PC Ollama/Qwen service. That service target does not make this a
Qwen provider/client runtime. This repository does not rename or recreate the
runtime.

The workspace-visible `R38 Qwen Reserved` custom profile is automatically
projected onto connected daemons by Multica. Its offline PC row
`25ba7103-2183-4c26-a09c-2e427d7de09d` and offline Mac row
`880f6484-8a16-4d1d-8448-805ee1ec012b` are registration projections only—not
Qwen installations, credentials, agents, models, or usable provider runtimes.
They are not health targets of this repository.

The operational reservation-backed Qwen provider runtime remains the private
R38 runtime `970f127e-bfff-402b-b14c-d24d022d0b6a`. It is outside this
repository and sends inference requests to the PC Ollama/Qwen service.

## Quick start

```powershell
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Install
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Status
```

See [docs/OPERATIONS.md](docs/OPERATIONS.md) for lifecycle details.
