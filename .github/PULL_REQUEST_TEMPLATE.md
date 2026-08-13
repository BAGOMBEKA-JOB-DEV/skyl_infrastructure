## What this changes

<!-- What is different afterwards, and why. If it fixes something, describe the
     failure rather than the fix — the failure is what a reviewer checks
     against. -->

## How it was verified

<!-- Which commands you ran and what they said. CONTRIBUTING.md lists them all.
     "CI will catch it" is not verification; CI does not run a cluster for most
     jobs, and several of these checks are the only thing standing between a
     rendering chart and a broken deployment. -->

```
```

## Checklist

- [ ] `terraform fmt -recursive -check terraform/` is clean
- [ ] `terraform validate` passes for every root I touched
- [ ] `tflint --recursive` exits 0
- [ ] `helm lint` and `helm template | kubeconform -strict` pass
- [ ] `conftest test --policy policy` passes on the rendered chart, **and still
      rejects `policy/fixtures/violations.yaml`**
- [ ] `trivy config --config trivy.yaml .` and `checkov --config-file .checkov.yaml`
      report no new findings
- [ ] `actionlint .github/workflows/*.yml` is clean
- [ ] Commits are signed off (`git commit -s`)

## If you changed the contract

- [ ] All three cloud modules still emit every output in
      [CONTRACT.md](../terraform/modules/CONTRACT.md)
- [ ] `modules/platform` still names no cloud
- [ ] The `module "platform"` block is still identical across all three
      environments — `diff terraform/environments/dev/{gcp,aws}/main.tf`

## If you suppressed a scanner finding

- [ ] The justification says what the check wants **and** why this repository
      does something else
- [ ] Trivy suppressions are inline at the resource; Checkov's are grouped in
      `.checkov.yaml` under a shared rationale

<!-- A bare suppression is worse than a finding: it looks resolved. -->

## If you changed a load-bearing value

<!-- terminationGracePeriodSeconds, maxUnavailable, probe paths, the egress
     rules, `bypass = AzureServices`. Say what breaks if it is wrong, and how
     you know it is not. Several of these have a corresponding rule in policy/
     that must change in the same PR. -->
