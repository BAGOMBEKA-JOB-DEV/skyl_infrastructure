# Security policy

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report it privately through
[GitHub Security Advisories](https://github.com/BAGOMBEKA-JOB-DEV/skyl_infrastructure/security/advisories/new)
on this repository.

Please include what is affected, the impact, and how to reproduce it. We will
credit you in the advisory unless you would rather we didn't.

### What to expect, and the honest limit

- **Acknowledgement within 3 working days.**
- **An assessment within 10 working days** — whether it is accepted, and if so
  the severity and a target for the fix.
- **Disclosure once a fix is released**, or after 90 days, whichever comes first.

There is **one maintainer**. Those windows are what one person can commit to,
not what a funded security team would offer, and there is no rota covering
illness or holiday. If a report goes unanswered past 10 working days, treat that
as the process having failed rather than the report being dismissed, and
disclose on whatever timeline you judge right — you are not bound by an embargo
nobody is upholding.

## What belongs here, and what belongs in skyl

This repository contains **no application code**. It is Terraform, a Helm chart,
policy and CI. A vulnerability in the gateway itself — request handling, auth,
the provider adapters — belongs in
[skyl's security policy](https://github.com/BAGOMBEKA-JOB-DEV/skyl/security/policy).

Report **here** anything about how the gateway is deployed:

- a configuration that exposes credentials, or weakens the isolation described
  in [ADR-0004](docs/adr/0004-egress-restriction.md)
- an IAM binding wider than its comment claims
- a chart default that is unsafe in a real cluster
- a CI workflow that could leak a token or be made to run untrusted code
- a scanner suppression in `trivy.yaml`, `.checkov.yaml`, or an inline
  `#trivy:ignore:` whose stated justification does not hold

That last one is a real category. Every suppression here records a reason; if
the reason is wrong, the finding is live and the comment is hiding it.

## What this repository is designed to protect

The gateway holds provider API keys and can reach arbitrary HTTPS endpoints.
That combination is the whole threat model, and the controls are:

| Control | Where | What it stops |
|---|---|---|
| Secrets never in git or Terraform state | [ADR-0003](docs/adr/0003-external-secrets-over-alternatives.md) | State files are copied to laptops and attached to tickets |
| Workload identity, no static cloud credentials | all three cloud modules | A leaked key that outlives its rotation |
| Egress restricted to 443, metadata endpoint blocked | [ADR-0004](docs/adr/0004-egress-restriction.md) | Credential exfiltration and container escape via node metadata |
| Images pinned by digest, cosign-verified | `charts/skyl-gateway` | Deploying bytes nobody signed |
| Least-privilege IAM, scoped by name prefix | cloud modules | A compromised operator reading every secret in the account |

### Known limits, stated rather than implied

- **Egress restriction is partial.** NetworkPolicy cannot express hostnames, so
  a compromised gateway can still POST to an attacker-controlled HTTPS endpoint.
  Closing that needs Cilium FQDN policy or an egress proxy —
  [ADR-0004](docs/adr/0004-egress-restriction.md) says so explicitly.
- **NetworkPolicy is only as real as the CNI.** Every cloud module configures a
  policy-capable one, because on a cluster without it the policy is accepted and
  silently ignored — a control that reports success while doing nothing.
- **Nothing here has been applied to a real cloud.** Everything is statically
  verified. A misconfiguration that only appears at apply time has not been
  ruled out.

## Supported versions

The `main` branch. This repository is not released or versioned; deploy from a
commit you have read.

## Credentials

No credential belongs in this repository, in any form, including a test fixture
that looks like one. `gitleaks` runs on every push and on a weekly schedule.

If you believe a credential has been committed here, report it privately using
the advisory link above and **do not** open a PR removing it — a PR is public
and points straight at the secret.
