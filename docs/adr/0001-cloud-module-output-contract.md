# ADR-0001: One output contract, three cloud modules

**Status:** accepted
**Date:** 2026-08-08

## Context

The gateway must be deployable on AWS, GCP and Azure. Three obvious shapes:

1. **One module, a `cloud` variable.** Terraform cannot conditionally require a
   provider, so every plan would load all three provider schemas — slow, and it
   makes credentials for clouds you are not using a soft prerequisite. Internally
   it becomes a mass of `count = var.cloud == "aws" ? 1 : 0`.
2. **Three independent stacks.** Honest, and it triplicates the application
   layer. The chart, the add-ons and the alert rules would drift, and the drift
   would be discovered per-cloud, in production.
3. **Three cloud modules behind a shared interface.** More upfront design; the
   layer above is written once.

## Decision

Option 3. Each of `modules/{aws,gcp,azure}` exposes eleven identically named,
identically typed outputs — [CONTRACT.md](../../terraform/modules/CONTRACT.md).
Everything above consumes only those.

The hard rule: **nothing above a cloud module may branch on which cloud it is.**
A difference that reaches upward is a defect in the contract, and the fix goes
down into the cloud module.

The interesting cases are the ones where a difference nearly leaked:

- **Workload identity annotations** differ in key, not just value —
  `eks.amazonaws.com/role-arn` vs `iam.gke.io/gcp-service-account` vs
  `azure.workload.identity/client-id`. Hence `workload_identity_annotation` is a
  `map(string)` passed through verbatim, never inspected. A `string` output
  would have forced the consumer to know the key.
- **Node architecture** differs because the cheap tier does: Graviton on AWS,
  Ampere on Azure, x86 on Autopilot. Exposed as `node_architecture` and used as
  a scheduling hint. The gateway image is multi-arch, so this is a cost lever
  rather than a compatibility constraint.
- **External Secrets provider blocks** genuinely differ in structure. This is
  the one permitted exception, confined to a single `merge()` in
  `modules/platform/main.tf` keyed on `secret_store_backend`.

## Consequences

`modules/platform` and `charts/skyl-gateway` contain no provider conditionals.
Adding a fourth cloud means writing one module against the contract; nothing
above changes.

The contract is enforced mechanically, not by review. `terraform validate` only
catches a missing output when something consumes it, so a dropped output would
otherwise surface at the first environment that needed it. CI greps every cloud
module for the required names, and separately fails if `modules/platform`
mentions a cloud outside the sanctioned exception.

The cost is that a cloud-specific feature cannot be surfaced without either
extending the contract for all three or bypassing it. Extra outputs beyond the
eleven are allowed — the contract is a minimum — but nothing shared may consume
them.
