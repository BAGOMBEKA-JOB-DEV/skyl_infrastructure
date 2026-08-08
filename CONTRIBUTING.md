# Contributing

## Sign off your commits

```bash
git commit -s
```

CI rejects any commit without a `Signed-off-by` line. It is the
[Developer Certificate of Origin](https://developercertificate.org/) — an
affirmation that you wrote the change and may contribute it under Apache-2.0.
No paperwork, no signature, no CLA.

## Run the checks locally

Everything CI runs, you can run first. This is worth doing: several of these
catch things that are invisible in review.

```bash
# Terraform
terraform fmt -recursive -check terraform/
(cd terraform/modules/gcp && terraform init -backend=false && terraform validate)
tflint --recursive

# Chart
DIGEST=sha256:$(printf '0%.0s' {1..64})
helm lint charts/skyl-gateway --set image.digest=$DIGEST
helm template gw charts/skyl-gateway --set image.digest=$DIGEST > /tmp/rendered.yaml

kubeconform -strict -kubernetes-version 1.31.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  /tmp/rendered.yaml

# Policy — the first must PASS, the second must FAIL
conftest test --policy policy /tmp/rendered.yaml
conftest test --policy policy policy/fixtures/violations.yaml

# Security. Both read their config from the repo root, so local and CI agree.
trivy config --config trivy.yaml .
checkov --config-file .checkov.yaml --directory . --soft-fail

# Workflows
actionlint .github/workflows/*.yml
```

`policy/fixtures/violations.yaml` is deliberately broken and CI asserts that
Conftest **rejects** it. A policy suite that cannot fail is indistinguishable
from no policy suite, and that failure mode is silent — every rule could be
misspelled and the build would stay green.

## The rules that are not negotiable

Each is enforced by `policy/` or by a `fail` in the chart, and each exists
because getting it wrong produces a silent failure rather than an error.

| Rule | What breaks without it |
|---|---|
| Liveness probes `/healthz`, readiness probes `/readyz` | `/readyz` returns 503 while draining, so liveness on it restarts the pod during every graceful shutdown |
| `terminationGracePeriodSeconds` ≥ 40 | The gateway needs ~32s to drain; less and live SSE streams are truncated mid-generation |
| Images pinned by digest | A tag is mutable, so a rollback can land on different bytes than the ones cosign signed |
| No credential literals in manifests | They belong in the cloud secret store, reached by External Secrets |
| `modules/platform` never names a cloud | The moment it does, the multi-cloud contract has leaked and the chart starts growing three code paths |

To change one, change the policy in the same PR and say why in the commit
message. They are meant to be arguable, not immovable — but they should not be
loosened by accident to make a build go green.

## Suppressing a scanner finding

Two scanners run, and their suppressions live in different places on purpose.

- **Trivy** — inline `#trivy:ignore:<ID>` directly above the resource, with the
  reason on the same line. Trivy's gate must stay green, so its justifications
  belong where the reader is already looking.
- **Checkov** — grouped in `.checkov.yaml` under the rationale they share.
  Thirty-eight per-resource comments would bury the code they annotate.

Either way, say what the check wants and why this repository does something
else. A bare suppression is worse than a finding, because it looks resolved.

## Adding a cloud

1. Create `terraform/modules/<cloud>/` implementing every output in
   [CONTRACT.md](terraform/modules/CONTRACT.md).
2. Add it to the `validate` matrix and the `contract` check in
   `.github/workflows/terraform.yml`.
3. Copy an existing `terraform/environments/dev/<cloud>/`. The `module
   "platform"` block must come out **byte-identical** to the other three — if it
   cannot, extend the contract rather than special-casing the environment.

## Changing the chart

The chart encodes operational facts taken from
[skyl's gateway runbook](https://github.com/BAGOMBEKA-JOB-DEV/skyl/blob/main/docs/gateway.md#runbook),
which was written against a running binary. If a value here disagrees with that
document, that document is right.

Diagrams in this repository are mermaid in markdown, which GitHub renders
natively. Note that the docs site uses a different convention — inline SVG React
components, because they inherit the page theme — so a diagram does not move
between the two repositories unchanged.

## Comment style

Comments explain *why*, and especially why not the obvious alternative. A
comment restating the code is noise; a comment recording the afternoon somebody
lost is the most valuable line in the file.

Where a value is load-bearing — the 40-second grace period, `maxUnavailable: 0`,
`bypass = AzureServices` on the Key Vault ACL — say what breaks if it changes.
