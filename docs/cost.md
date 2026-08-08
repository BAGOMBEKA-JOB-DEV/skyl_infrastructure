# Cost

List prices as of 2026-08, for the `dev` configuration in
`terraform/environments/dev/`: two nodes, one gateway with two replicas, the
Prometheus stack, and an ingress load balancer. Excludes model API spend, which
will dominate everything below once real traffic arrives.

These are estimates from published pricing, not observed bills. Record actual
figures here after a week — the gap between the two is usually the interesting
part.

## Monthly, dev

| | GCP (Autopilot) | AWS (EKS) | Azure (AKS) |
|---|---|---|---|
| Control plane | $0 first cluster | **$73** | $0 (Free tier) |
| Compute | ~$25 (per-pod billing) | ~$25 (2× t4g.medium) | ~$25 (2× D2ps_v5) |
| Load balancer | ~$18 | ~$18 (NLB) | ~$18 |
| NAT | ~$33 | ~$33 (single NAT) | included |
| Logs/metrics | ~$5 | ~$5 | ~$8 |
| **Total** | **~$81** | **~$154** | **~$51** |

Autopilot bills per pod resource *request*, which is why the chart's requests
are deliberately modest — 100m CPU and 128Mi per replica. Inflating them costs
real money on GCP and nothing on the other two.

## Why the spread

**AWS is ~$73/month more before anything runs**, purely for the EKS control
plane. That is the single largest line item and it is unavoidable on EKS.

**Azure looks cheapest but the Free tier has no uptime SLA.** For anything
anyone depends on, `sku_tier = "Standard"` adds ~$73/month, putting Azure level
with AWS. The comparison above is dev-to-dev, not prod-to-prod.

**GCP is the cheapest with a real SLA.** Autopilot's zonal SLA applies at no
control-plane cost for the first cluster in a billing account. This is why the
plan recommends building GCP first.

## Levers

| Lever | Saves | Costs you |
|---|---|---|
| `single_nat_gateway = true` (AWS, default in dev) | ~$66/mo | Degraded egress in a zonal outage |
| arm64 nodes (default on AWS and Azure) | ~20% of compute | Nothing — the image is multi-arch |
| `monitoring_enabled = false` | ~$5–8/mo + a node's worth of memory | Every alert in the runbook |
| `grafana_enabled = false` | ~$3/mo | Dashboards; Prometheus still scrapes |
| Spot/preemptible nodes | ~60% of compute | Eviction mid-stream. The PDB helps; 32s drains do not |
| Destroy between demos | everything | 15 minutes to re-apply |

That last row is worth taking seriously. Nothing here holds state — secrets
live in the cloud secret store, not the cluster — so `terraform destroy` and a
later `apply` genuinely round-trips. For a portfolio deployment this is the
difference between ~$80/month and ~$2.

## Before the first apply

Set a budget alert. The gateway proxies **paid** model APIs, so an exposed
token is a direct bill, and the infrastructure cost above is the small half of
the risk.

```bash
# GCP
gcloud billing budgets create --billing-account=<id> \
  --display-name=skyl --budget-amount=100USD \
  --threshold-rule=percent=50 --threshold-rule=percent=90

# AWS
aws budgets create-budget --account-id <id> \
  --budget '{"BudgetName":"skyl","BudgetLimit":{"Amount":"100","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}'

# Azure — Cost Management > Budgets, or:
az consumption budget create --budget-name skyl --amount 100 --time-grain Monthly
```

## Actual spend

Fill in after a week of running. Estimates above are list price and ignore
sustained-use discounts, free tiers already consumed, and egress.

| Month | Cloud | Estimated | Actual | Note |
|---|---|---|---|---|
| | | | | |
