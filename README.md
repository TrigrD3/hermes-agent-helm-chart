# Unofficial Hermes Agent Helm Chart

> [!IMPORTANT]
> This is an **unofficial community Helm chart** for [Nous Research's Hermes Agent](https://github.com/nousresearch/hermes-agent). It is maintained independently from the upstream Hermes project.

This chart packages Hermes Agent for Kubernetes with cloud-native defaults, explicit state-safety guardrails, and flexible composition points for platform teams.

## What this chart is optimized for

- **State-safe Hermes deployments**: `replicaCount: 1` plus `strategy.type: Recreate` are enforced when persistence is enabled so `HERMES_HOME` is not shared unsafely.
- **Gateway-first runtime**: the default command is `hermes gateway run`, with optional API server, webhook, and Telegram webhook listeners.
- **Cloud-native integration**: optional Service, Ingress, Istio `VirtualService`, RBAC, NetworkPolicy, PDB, and arbitrary `extraObjects`.
- **Composable secrets and bootstrap**: use chart-managed Secret/ConfigMap resources, or reuse externally managed ones with `secrets.existingSecret` and `bootstrap.existingConfigMap`.
- **Tenant-scoped operation**: the chart is best run as one Helm release per tenant, with per-tenant namespaces, PVCs, service accounts, secrets, and traffic policy.

## Quick start

```bash
helm install hermes . \
  --namespace hermes \
  --create-namespace
```

Minimal values:

```yaml
secrets:
  OPENROUTER_API_KEY: sk-or-...

config:
  values:
    model:
      default: anthropic/claude-opus-4.6
```

## Core chart behavior

### Hermes state safety

Hermes stores mutable data under `HERMES_HOME`, so this chart treats persistent storage as a **single-writer** workload:

- `persistence.enabled=true` defaults to a PVC mounted at `/opt/data`
- `replicaCount` must remain `1` when persistence is enabled
- `strategy.type` must remain `Recreate` when persistence is enabled
- `persistence.existingClaim` lets you bind to pre-provisioned storage without changing the single-replica rule

If you need multiple Hermes instances, create **multiple releases** instead of scaling a single release horizontally.

### Configuration model

The chart exposes four main configuration layers:

- `config.values`: structured YAML merged into a rendered `config.yaml`
- `config.raw`: raw templated YAML that takes precedence over `config.values`
- `env`, `extraEnv`, and `extraEnvFrom`: environment-level tuning and secrets/config injection
- `command` / `args`: runtime entrypoint overrides when you need something other than the default gateway mode

### Runtime and bootstrap

- `bootstrap.enabled=true` seeds `config.yaml` and optional `SOUL.md` into `HERMES_HOME`
- `bootstrap.overwrite=true` makes Helm the source of truth for bootstrap files
- `bootstrap.existingConfigMap` reuses externally managed bootstrap content instead of rendering a chart-owned ConfigMap
- `npmPackages` installs extra Node packages into the persistent volume and exposes them through `PATH` / `NODE_PATH`

## Multi-tenant isolation pattern

This chart does not model multi-tenancy inside a single Hermes pod. Instead, the safe pattern is **one release per tenant**.

Recommended per-tenant isolation boundaries:

1. **Namespace per tenant** (or equivalent namespace boundary)
2. **Dedicated PVC** per tenant release
3. **Dedicated Secret** or `secrets.existingSecret` per tenant
4. **Dedicated ServiceAccount/RBAC** rules per tenant when Kubernetes API access is needed
5. **Dedicated ingress host / Istio host** per tenant
6. **Tenant-specific NetworkPolicy** to limit ingress and egress

Example tenant-scoped values:

```yaml
fullnameOverride: hermes-tenant-a

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/hermes-tenant-a

rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["configmaps", "secrets"]
      verbs: ["get", "list", "watch"]

persistence:
  enabled: true
  existingClaim: hermes-tenant-a-data

secrets:
  existingSecret: hermes-tenant-a-secrets

networkPolicy:
  enabled: true
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8642
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

## Secrets and External Secrets Operator patterns

The chart supports two secret-management modes:

1. **Chart-managed Secret** via `secrets.*`
2. **Externally managed Secret** via `secrets.existingSecret`

For External Secrets Operator, the usual pattern is:

- create an `ExternalSecret` that materializes a Kubernetes Secret
- point `secrets.existingSecret` at that Secret
- optionally render the `ExternalSecret` from this chart via `extraObjects`

Example using a pre-created Secret:

```yaml
secrets:
  existingSecret: hermes-tenant-a-secrets
```

Example rendering an `ExternalSecret` through `extraObjects`:

```yaml
secrets:
  existingSecret: hermes-tenant-a-secrets

extraObjects:
  - apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: hermes-tenant-a-secrets
    spec:
      refreshInterval: 1h
      secretStoreRef:
        kind: ClusterSecretStore
        name: platform-secrets
      target:
        name: hermes-tenant-a-secrets
      data:
        - secretKey: OPENROUTER_API_KEY
          remoteRef:
            key: tenants/tenant-a/hermes
            property: OPENROUTER_API_KEY
```

This keeps secret delivery under your platform's preferred operator while letting the chart consume a normal Kubernetes Secret.

## Service exposure, ingress, and Istio

### OpenAI-compatible API server

Enable Hermes's OpenAI-compatible API server for Open WebUI, LobeChat, LibreChat, or other compatible clients:

```yaml
apiServer:
  enabled: true
  host: 0.0.0.0
  port: 8642

secrets:
  existingSecret: hermes-api-secrets

service:
  enabled: true
```

If `service.ports` is empty, the chart automatically derives Service ports from enabled listeners (`apiServer`, `webhook`, and `telegramWebhook`). Keep explicit `service.ports` only when you need custom front-door mappings.

### Ingress controller pattern

Use `ingress.enabled=true` when you want Kubernetes Ingress resources:

```yaml
service:
  enabled: true

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  hosts:
    - host: hermes.tenant-a.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - hosts:
        - hermes.tenant-a.example.com
      secretName: hermes-tenant-a-tls
```

Key notes:

- `ingress.enabled=true` requires `service.enabled=true`
- Ingress can target a derived default service port or `ingress.servicePortNumber`
- `service.annotations` can be used for controller- or cloud-specific integration on `LoadBalancer` services

### Istio VirtualService pattern

Use `virtualService.enabled=true` when the cluster is fronted by Istio:

```yaml
service:
  enabled: true

virtualService:
  enabled: true
  gateways:
    - istio-system/public-gateway
  hosts:
    - hermes.tenant-a.example.com
  timeout: 3600s
  servicePortNumber: 8642
```

Validation requires at least one gateway and one host, which keeps broken Istio configs from rendering silently.

## Compose with other platform resources

This chart is intentionally composable instead of prescriptive. Useful integration points include:

- `secrets.existingSecret` for External Secrets, Vault sync, Sealed Secrets, or another chart
- `bootstrap.existingConfigMap` for shared or operator-managed bootstrap content
- `extraEnvFrom` for ConfigMaps/Secrets from another release
- `extraVolumes` and `extraVolumeMounts` for projected credentials or shared storage
- `extraInitContainers` and `extraContainers` for service mesh helpers, bootstrap jobs, or sidecars
- `extraObjects` for `ExternalSecret`, `ServiceMonitor`, policy resources, or tenant-specific control-plane objects
- `serviceAccount.annotations` for IRSA, GKE Workload Identity, or similar cloud IAM bindings

Example external bootstrap reuse:

```yaml
bootstrap:
  enabled: true
  overwrite: false
  existingConfigMap: hermes-shared-bootstrap

secrets:
  existingSecret: hermes-shared-secrets
```

When `bootstrap.existingConfigMap` is set, the referenced ConfigMap must contain `config.yaml` and may optionally include `SOUL.md`.

## Security and operational notes

- Enable `networkPolicy.enabled` to add tenant-scoped ingress and egress controls
- Enable `rbac.create` only when Hermes needs Kubernetes API access
- `serviceAccount.automountServiceAccountToken` defaults to `false`
- Pod and container security contexts default to non-root execution, dropped Linux capabilities, and `RuntimeDefault` seccomp
- Enable `service.enabled` only when you actually need network exposure
- `values.schema.json` validates persistence safety, ingress/service prerequisites, Telegram webhook requirements, and Istio host/gateway inputs before templates render

## Verification

Behavior is locked by Helm lint/template checks plus the regression script in `ci/verify.sh`:

```bash
helm lint .
helm lint . -f ci/test-values.yaml
helm lint . -f ci/existing-claim-values.yaml
helm lint . -f ci/external-bootstrap-values.yaml
helm lint . -f ci/default-service-ports-values.yaml
helm template hermes .
helm template hermes . -f ci/test-values.yaml
helm template hermes . -f ci/existing-claim-values.yaml
helm template hermes . -f ci/external-bootstrap-values.yaml
helm template hermes . -f ci/default-service-ports-values.yaml
bash ci/verify.sh
```
