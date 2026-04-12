# Hermes Agent Helm Chart

Cloud-native Helm chart for [Nous Research's Hermes Agent](https://github.com/nousresearch/hermes-agent).

This chart keeps Hermes's mutable state in a PVC at `/opt/data`, injects secrets as environment variables, and bootstraps a Helm-managed `config.yaml` before the main process starts.

## What this chart optimizes for

- **Persistent Hermes state** in one volume: sessions, memories, skills, logs, cron jobs, and config
- **Gateway-first deployments** with `hermes gateway run` as the default runtime
- **Optional API server exposure** for OpenAI-compatible frontends
- **Cloud-native ergonomics**: service account, optional network policy, PDB, probes, and checksum-based rollouts
- **Hermes image compatibility** with `/dev/shm` sizing and optional npm package bootstrap

## Install

```bash
helm install hermes . \
  --set secrets.OPENROUTER_API_KEY=sk-or-... \
  --set config.values.model.default=anthropic/claude-sonnet-4.6
```

For a browser-friendly HTTP frontend:

```bash
helm install hermes . \
  --set apiServer.enabled=true \
  --set secrets.OPENROUTER_API_KEY=sk-or-... \
  --set secrets.API_SERVER_KEY=change-me \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=hermes.example.com
```

## Important paths

- **`/opt/data`** — authoritative Hermes home directory (`HERMES_HOME`)
- **`/opt/data/config.yaml`** — Helm-managed config bootstrap
- **`/opt/data/SOUL.md`** — optional chart-managed persona file
- **`/dev/shm`** — memory-backed shared memory mount for browser tools

## Runtime model

By default the chart runs:

```bash
hermes gateway run
```

You can override the runtime with `args`, for example:

```yaml
args: ["acp"]
```

## Values

### Core

- `image.repository`, `image.tag`, `image.pullPolicy`
- `replicaCount` — default `1`
- `args` — Hermes CLI arguments passed after the built-in entrypoint
- `persistence.*`
- `bootstrap.*`
- `config.*`
- `secrets.*`
- `env.*`
- `serviceAccount.*`
- `resources`
- `shmSize`

### Exposure

- `apiServer.enabled`
- `service.enabled`
- `service.type`
- `ingress.enabled`
- `ingress.hosts`
- `networkPolicy.enabled`

### Extensibility

- `npmPackages` — install npm packages into `/opt/data/npm-global`
- `extraEnv`, `extraEnvFrom`
- `extraInitContainers`, `extraContainers`
- `extraVolumes`, `extraVolumeMounts`

## Operational notes

- Keep `replicaCount` at `1` when persistence is enabled.
- Helm values are the source of truth for `config.yaml`.
- Use `secrets.existingSecret` if you manage credentials outside Helm.
- Enable `apiServer.enabled` only with an `API_SERVER_KEY`.
- For browser tools, keep `shmSize` at least `1Gi`.

