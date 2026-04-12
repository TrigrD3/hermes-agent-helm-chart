# Hermes Agent Helm Chart

Cloud-native Helm chart for [Nous Research's Hermes Agent](https://github.com/nousresearch/hermes-agent).

This chart combines the strongest ideas from the reference repos:

- **state-safe rollout defaults** for Hermes's mutable `HERMES_HOME`
- **generic Kubernetes composition hooks** so the chart can plug into other releases
- **optional cloud-native surfaces** like Service, Ingress, Istio `VirtualService`, RBAC, PDB, and NetworkPolicy
- **Hermes-specific runtime support** for config bootstrapping, browser `/dev/shm`, and npm-based skill dependencies

## What this chart optimizes for

- Persistent Hermes state in one PVC-backed home directory
- A single-replica `Deployment` with `Recreate` strategy to avoid PVC corruption
- Gateway-first runtime (`hermes gateway run`) with optional API server / webhook exposure
- Secure-by-default pod and container security contexts
- Easy composition with arbitrary Kubernetes charts and external operators

## Install

```bash
helm install hermes .
```

Minimal example:

```yaml
secrets:
  OPENROUTER_API_KEY: sk-or-...

config:
  values:
    model:
      default: anthropic/claude-opus-4.6
```

## OpenAI-compatible API server

Enable Hermes's OpenAI-compatible server for Open WebUI / LobeChat / LibreChat style frontends:

```yaml
apiServer:
  enabled: true
  host: 0.0.0.0
  port: 8642

secrets:
  OPENROUTER_API_KEY: sk-or-...
  API_SERVER_KEY: change-me

service:
  enabled: true
```

If `service.ports` is left empty, the chart can derive default Service ports from
the enabled `apiServer`, `webhook`, and `telegramWebhook` listeners. Keep
explicit `service.ports` when you need custom mappings such as `port: 80` to
`targetPort: 8642`.

## Webhooks and Telegram webhook mode

The chart also supports Hermes's webhook adapters:

```yaml
webhook:
  enabled: true
  port: 8644

telegramWebhook:
  enabled: true
  url: https://hermes.example.com/telegram
  port: 8443

service:
  enabled: true
```

When `telegramWebhook.enabled=true`, also set a non-empty `telegramWebhook.url` and provide a Telegram bot token via `secrets.TELEGRAM_BOT_TOKEN` or `secrets.existingSecret`.

## Compose with any Kubernetes chart

This chart is intentionally open-ended so it can integrate with other Helm charts and platform operators without forking:

- `secrets.existingSecret` — consume credentials managed by External Secrets, Vault, Sealed Secrets, or another chart
- `persistence.existingClaim` — reuse storage created elsewhere
- `bootstrap.existingConfigMap` — consume externally managed `config.yaml` / `SOUL.md` content instead of a chart-managed bootstrap ConfigMap
- `extraEnvFrom` — import ConfigMaps/Secrets produced by another release
- `extraVolumes` / `extraVolumeMounts` — attach config, credentials, or shared storage from other workloads
- `extraInitContainers` / `extraContainers` — add sidecars, bootstrap jobs, or service mesh helpers
- `extraObjects` — inject arbitrary manifests such as `ExternalSecret`, `ServiceMonitor`, or policy resources
- `serviceAccount.annotations` — attach IRSA / Workload Identity / cloud IAM integration
- `bootstrap.existingConfigMap` — seed Hermes from a ConfigMap managed by another release/operator

External bootstrap example:

```yaml
bootstrap:
  enabled: true
  overwrite: false
  existingConfigMap: hermes-shared-bootstrap
```

Example: use bootstrap content managed by another chart or operator:

```yaml
bootstrap:
  existingConfigMap: hermes-shared-bootstrap

secrets:
  existingSecret: hermes-shared-secrets

apiServer:
  enabled: true

service:
  enabled: true
```

When `bootstrap.existingConfigMap` is used, the referenced ConfigMap should
contain `config.yaml` and may optionally include `SOUL.md`. Because the content
is managed outside this chart, operators should also plan how rollout/restart
should happen when that external ConfigMap changes.

## Operational notes

- Keep `replicaCount: 1` when persistence is enabled.
- Hermes state lives under `persistence.mountPath` (`/opt/data` by default).
- `bootstrap.overwrite=true` makes Helm the source of truth for `config.yaml` and `SOUL.md`.
- `values.schema.json` adds machine-readable checks for persistence safety, required secrets, ingress/virtual service prerequisites, and service exposure inputs before templates render.
- `npmPackages` installs packages into the PVC and exposes them via `PATH`/`NODE_PATH`.
- Enable `service.enabled` only when you actually want network exposure.
- Enable `rbac.create` only when Hermes needs in-cluster Kubernetes access.
- `virtualService.enabled` requires explicit `virtualService.hosts` and `virtualService.gateways`.

## Verification

This repo includes `ci/test-values.yaml` for render checks:

```bash
helm lint .
helm lint . -f ci/test-values.yaml
helm lint . -f ci/existing-claim-values.yaml
helm template hermes .
helm template hermes . -f ci/test-values.yaml
helm template hermes . -f ci/existing-claim-values.yaml

# schema-focused negative checks
! helm lint . -f ci/invalid-persistence-values.yaml
! helm lint . -f ci/invalid-service-values.yaml
! helm lint . -f ci/invalid-telegram-values.yaml
```
