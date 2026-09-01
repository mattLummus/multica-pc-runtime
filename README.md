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

## Existing runtime inventory

| Provider | Runtime ID | Current role |
|---|---|---|
| Codex | `713a5202-c384-4cf0-8190-876e36f8bdcf` | Direct runtime registered by the native daemon |
| Qwen | `25ba7103-2183-4c26-a09c-2e427d7de09d` | Profile-backed `R38 Qwen Reserved` runtime |

The existing profile and device names contain `Qwen` for historical continuity,
but the daemon also hosts Codex. This repository does not rename or recreate
either runtime.

The Qwen runtime additionally depends on its host-local custom-profile
executable pin. Daemon availability and Qwen provider activation are separate
health conditions and must be reported separately.

## Quick start

```powershell
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Install
.\scripts\Manage-MulticaPcRuntime.ps1 -Action Status
```

See [docs/OPERATIONS.md](docs/OPERATIONS.md) for lifecycle details.

