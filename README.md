# skyl_infrastructure

Deployment infrastructure for
[skyl-gateway](https://github.com/BAGOMBEKA-JOB-DEV/skyl) — Terraform that
stands up a Kubernetes cluster on **AWS, GCP or Azure**, one Helm chart that
runs identically on all three, and CI that will not let a bad manifest through.

The gateway is one authenticated endpoint that fans out to Anthropic, OpenAI,
Gemini and any OpenAI-compatible provider. It holds the API keys so your
services do not have to.

## What is here

```
terraform/
  modules/{aws,gcp,azure}/   one cluster each, identical output contract
  modules/platform/          add-ons + the gateway, written once
  environments/dev/{aws,gcp,azure}/
charts/skyl-gateway/         the chart
policy/                      Conftest rules the chart must satisfy
docs/                        runbook, ADRs, cost
```

## How three clouds stay one codebase

Every cloud module emits the **same eleven outputs** —
[`terraform/modules/CONTRACT.md`](terraform/modules/CONTRACT.md). Everything
above them consumes only those, so `modules/platform` and
`charts/skyl-gateway` contain no provider conditionals at all.

The `module "platform"` block is byte-identical in all three environments. Diff
them:

```bash
diff terraform/environments/dev/{gcp,aws}/main.tf   # only the cluster + providers differ
```

CI enforces both halves: a job greps every cloud module for the required
outputs, and another fails if `modules/platform` mentions a cloud outside the
one place a difference is unavoidable (the External Secrets provider block).

Cross-cloud primitives:

| Concern | Chosen | Why |
|---|---|---|
| Secrets | External Secrets Operator | One CRD over Secrets Manager, Secret Manager and Key Vault. Nothing secret in git or in state |
| Identity | IRSA / Workload Identity / Entra federation | No static cloud credentials anywhere, including CI |
| Ingress | ingress-nginx + cert-manager | Behaves the same on all three. See [ADR-0002](docs/adr/0002-ingress-nginx-over-gateway-api.md) |
| Observability | kube-prometheus-stack | skyl already exports OpenTelemetry GenAI metrics |

## Getting started

You need a published image digest. skyl's `publish-image` workflow prints one
on every `gateway/v*` tag; the chart refuses to deploy a mutable tag.

```bash
cd terraform/environments/dev/gcp

terraform init -backend-config="bucket=<your-state-bucket>"
terraform apply \
  -var project_id=<your-project> \
  -var gateway_image_digest=sha256:<digest>
```

Then populate the secrets — Terraform creates the containers but never the
values, because a value in Terraform is a value in state:

```bash
echo -n "$(openssl rand -hex 32)" | \
  gcloud secrets versions add skyl-gateway-auth-token --data-file=-
echo -n "$ANTHROPIC_API_KEY" | \
  gcloud secrets versions add skyl-anthropic-api-key --data-file=-
```

`terraform output smoke_test` prints the commands to verify it.

AWS and Azure are the same three steps against
`environments/dev/{aws,azure}`. Costs differ substantially —
[docs/cost.md](docs/cost.md) has real numbers.

## Working on the chart

```bash
helm lint charts/skyl-gateway --set image.digest=sha256:$(printf '0%.0s' {1..64})
helm template gw charts/skyl-gateway --set image.digest=sha256:0000... | \
  kubeconform -strict -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
conftest test --policy policy rendered.yaml
```

`policy/fixtures/violations.yaml` is a deliberately broken manifest. CI asserts
that conftest **rejects** it — a policy suite that cannot fail is not a policy
suite, and that failure is otherwise silent.

## Things that will bite you

Each of these is encoded in the chart, and most are also a policy rule. They
come from skyl's own runbook, verified against a running binary.

- **`/healthz` stays 200 while draining. `/readyz` goes 503.** Liveness must
  point at `/healthz`. Point it at `/readyz` and the kubelet restarts the pod
  during every graceful shutdown.
- **Shutdown takes up to ~32s**, so `terminationGracePeriodSeconds` is 40.
  Lower it and live SSE streams are truncated — streams the provider has
  already billed you for.
- **The image has no shell.** Every probe is `httpGet`; an `exec` probe fails
  as "no such file or directory" and reads like a crash.
- **Starting with no provider key is fatal.** An unsynced ExternalSecret
  presents as CrashLoopBackOff. Check the ExternalSecret before the image.
- **The grace-expiry warning exits 0.** A pod that force-closed streams logs a
  WARN and exits cleanly, so restart-count alerting will never see it.

## Contributing

Commits need a `Signed-off-by` line (`git commit -s`); CI enforces it.
Apache-2.0, matching skyl.
