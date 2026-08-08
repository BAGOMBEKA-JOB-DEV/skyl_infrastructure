# Runbook

Operating skyl-gateway on Kubernetes. This extends
[skyl's own runbook](https://github.com/BAGOMBEKA-JOB-DEV/skyl/blob/main/docs/gateway.md#runbook),
which documents the binary's behaviour; this one covers what the cluster adds.

Every alert in `charts/skyl-gateway/templates/prometheusrule.yaml` links to a
heading here.

## Deploy

```bash
cd terraform/environments/<env>/<cloud>
terraform apply -var gateway_image_digest=sha256:<digest>
```

The digest comes from skyl's `publish-image` workflow summary, or:

```bash
crane digest ghcr.io/bagombeka-job-dev/skyl-gateway:0.1.0
```

Verify the signature before deploying anything you did not build:

```bash
cosign verify ghcr.io/bagombeka-job-dev/skyl-gateway@sha256:<digest> \
  --certificate-identity-regexp '^https://github.com/BAGOMBEKA-JOB-DEV/skyl/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Rollback

Re-apply with the previous digest. This is the entire reason the chart refuses
mutable tags: `:0.1.0` today and `:0.1.0` last week are not necessarily the
same bytes, so a tag-based rollback is a guess.

```bash
terraform apply -var gateway_image_digest=sha256:<previous>
```

Faster, if Terraform is not to hand:

```bash
kubectl -n skyl rollout undo deploy/skyl-gateway-skyl-gateway
```

Then reconcile Terraform, or the next apply silently rolls forward again.

## Rotate the gateway token without downtime

`SKYL_AUTH_TOKEN` is a single value, so replacing it invalidates every client
at once. `SKYL_AUTH_TOKENS` accepts several labelled tokens simultaneously, and
that overlap is what makes rotation safe:

1. Add the new token alongside the old:

   ```bash
   # value: "current:<old>,next:<new>"
   gcloud secrets versions add skyl-gateway-auth-tokens --data-file=-
   ```

2. Roll the pods. The gateway reads its environment once at startup, so a
   refreshed Secret alone changes nothing:

   ```bash
   kubectl -n skyl rollout restart deploy/skyl-gateway-skyl-gateway
   ```

3. Move clients to the new token. The **label** appears in logs and metrics and
   the token never does, so you can watch `current` fall to zero use before
   removing it.

4. Drop the old token and roll again.

Never name a token after its own value — the label is logged.

## Alerts

### SkylGatewayAbsent

No instance has been scraped for 5 minutes.

```bash
kubectl -n skyl get pods
kubectl -n skyl get servicemonitor -o yaml | grep -A5 selector
```

Either every replica is gone, or the ServiceMonitor selector stopped matching.
The second is more common after a chart change — the monitor selects
`app.kubernetes.io/component: metrics`, which only the headless metrics Service
carries.

### SkylGatewayNotReady

Ready replicas below desired for 10 minutes. A rollout takes far less.

```bash
kubectl -n skyl describe pod -l app.kubernetes.io/name=skyl-gateway
kubectl -n skyl get externalsecret
```

**Check the ExternalSecret first.** Starting with no provider key is a fatal
error in the gateway, so an unsynced secret presents as CrashLoopBackOff and
looks like a broken image. `SecretSyncedError` in the ExternalSecret's status
means the workload identity binding is wrong, not the deployment.

### SkylGatewayCrashLooping

Exit 1 is the gateway's only non-zero code: startup validation failed, or the
listener could not bind.

```bash
kubectl -n skyl logs -l app.kubernetes.io/name=skyl-gateway --previous --tail=50
```

A malformed value always names the variable before exiting. If the logs are
empty, the container never started — check the image digest and pull secrets.

### SkylGatewayHighLatency

p95 above 30s for one provider over 15 minutes. Generous on purpose: these are
model calls.

The gateway deliberately does **not** fail readiness on provider health. There
is nothing to fail over to, and flapping readiness on a provider blip would
drain the fleet. So this is informational — the action is to shift traffic:

```bash
kubectl -n skyl set env deploy/skyl-gateway-skyl-gateway SKYL_DEFAULT_PROVIDER=anthropic
```

Reconcile that into Terraform afterwards.

### SkylGatewaySaturated

In-flight requests above 80% of `SKYL_MAX_CONCURRENT`. Past the limit the
gateway rejects work.

Either raise `autoscaling.maxReplicas` or raise `config.maxConcurrent`. Prefer
more replicas: concurrency per pod is bounded by memory, and a single saturated
pod has a long tail.

Note this is derived by Little's Law rather than from a gauge — see
[observability.md](observability.md).

### SkylGatewayGracePeriodExpired

The one that matters most, and the one that is invisible by default.

A stream still generating when the 30s grace expires is force-closed. The
client sees a truncated SSE stream with no terminal `done` event, and the
upstream call was already paid for. The process logs a WARN and **exits 0** —
so restart counts, exit codes and pod status all look perfectly healthy.

```
{"level":"WARN","msg":"grace period expired with requests still in flight; closing anyway","grace":30000000000}
```

This requires log-derived metrics. With Loki:

```yaml
- record: skyl_gateway_grace_period_expired_total
  expr: |
    sum(count_over_time(
      {namespace="skyl", app="skyl-gateway"}
        |= "grace period expired with requests still in flight" [5m]
    ))
```

Without a log pipeline the alert is inert rather than wrong — no series, no
firing. Wire one up; this is the failure mode most worth knowing about.

If it fires on every rollout, generations in use are longer than the 30s grace.
Raise `terminationGracePeriodSeconds` **and** the gateway's own shutdown grace
together — raising only the Kubernetes side does nothing, since the process
closes on its own timer.

## Incident checklist

Record with any incident:

- The deployed digest: `terraform output gateway_image_digest`
- `kubectl -n skyl get pods -o wide`
- `kubectl -n skyl logs -l app.kubernetes.io/name=skyl-gateway --tail=200`
- Whether the ExternalSecret was synced at the time

The digest is the part people forget, and without it the logs cannot be tied to
a build.

## Teardown

```bash
terraform destroy
```

Then confirm nothing was orphaned — a second plan must come back empty:

```bash
terraform plan   # expect: No changes
```

Cloud-specific residue that survives a destroy:

- **AWS** — Secrets Manager secrets keep a recovery window in non-dev, so the
  names stay reserved.
- **Azure** — Key Vault soft-delete reserves the vault name. With
  `purge_protection_enabled` (prod) it cannot be purged early.
- **GCP** — the cluster has `deletion_protection` on outside dev; disable it
  before destroying.
