---
name: Bug report
about: Terraform, the Helm chart, or CI behaves differently from what the docs say
labels: bug
---

**Redact before pasting.** Terraform output, `kubectl describe` and Helm values
can all carry account IDs, subscription IDs, cluster endpoints and — if
something has gone wrong — secret values. Scrub them.

## What happened

## What you expected

## Which layer

<!-- Tick one. The three fail in different ways and the useful evidence differs. -->

- [ ] Terraform — a module, an environment, or the output contract
- [ ] Helm chart — rendering, or the running deployment
- [ ] CI — a workflow, a policy rule, or a scanner suppression

## Which cloud, and which environment

<!-- aws / gcp / azure, and dev / your own. If it reproduces on more than one
     cloud, say so — that usually means the fault is above the contract
     boundary, in modules/platform or the chart, rather than in a cloud module.
     See terraform/modules/CONTRACT.md. -->

## Reproducing it

<!-- The exact commands. For Terraform, include the version and whether it
     failed at plan or apply — those are very different bugs. -->

```
```

## Output

<!-- The error, redacted. For a chart problem, `helm template` output for the
     object involved is usually more useful than the error itself. -->

```
```

## What you already checked

<!-- Optional but saves a round trip. Common causes, in the order they occur:

     - pods CrashLoopBackOff → check the ExternalSecret first. The gateway
       treats "no provider key" as fatal, so an unsynced secret looks exactly
       like a broken image.
     - rollout seems to hang → a drain legitimately takes ~32s per pod.
     - NetworkPolicy has no effect → the cluster's CNI may not enforce it. -->
