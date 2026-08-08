# The cloud module contract

Three clouds, one application layer. That only holds if the clouds are hidden
behind a boundary, and this file is the boundary.

Every module under `modules/{aws,gcp,azure}` **must** expose exactly the outputs
below, with exactly these types. Everything above them — `modules/platform`, the
Helm release, the environments — consumes only these. Nothing above a cloud
module may branch on which cloud it is.

That single rule is what keeps `charts/skyl-gateway` free of provider
conditionals. The moment something upstream writes `if aws`, the abstraction has
failed and the chart starts accumulating three code paths.

## Required outputs

```hcl
output "cluster_name"            { type = string }
output "cluster_endpoint"        { type = string }  # API server URL
output "cluster_ca_certificate"  { type = string }  # base64 PEM
output "cluster_version"         { type = string }

# Workload identity federation. The issuer the cloud publishes for the cluster.
output "oidc_issuer_url"         { type = string }

# The annotation External Secrets' ServiceAccount needs so it can read the
# cloud's secret store. The KEY differs per cloud, which is the entire reason
# this is a map rather than a string:
#
#   AWS    eks.amazonaws.com/role-arn        = arn:aws:iam::...
#   GCP    iam.gke.io/gcp-service-account    = ...@....iam.gserviceaccount.com
#   Azure  azure.workload.identity/client-id = <uuid>
#
# Consumers pass it through verbatim and never inspect the key.
output "workload_identity_annotation" { type = map(string) }

# Which External Secrets provider block to generate: "aws" | "gcpsm" | "azurekv"
output "secret_store_backend"    { type = string }

# Provider-specific settings for that block — region, projectID, vaultUrl.
# Shape varies; the platform module templates it and does not read individual
# keys beyond what secret_store_backend implies.
output "secret_store_config"     { type = map(string) }

# "nginx" unless a cloud-native controller is deliberately chosen.
output "ingress_class"           { type = string }

# Node architecture, so the platform module can set nodeSelectors. The gateway
# image is multi-arch, so this is a cost lever, not a compatibility one.
output "node_architecture"       { type = string }  # "amd64" | "arm64"

output "region"                  { type = string }
```

## Required inputs

Every cloud module accepts at least:

```hcl
variable "name"        { type = string }              # cluster name prefix
variable "environment" { type = string }              # dev | prod
variable "region"      { type = string }
variable "node_count"  { type = number }
variable "tags"        { type = map(string) }
```

## Why a contract rather than a wrapper module

A single `module "cluster"` taking `provider = "aws"` would need every
provider's schema loaded on every plan, and Terraform cannot conditionally
require a provider. Three sibling modules with one shared interface keeps each
plan loading only what it needs, and keeps the failure mode honest: a module
that cannot satisfy the contract fails at `terraform validate`, not at apply.

## Checking compliance

`terraform validate` catches a missing output only when something consumes it.
`.github/workflows/terraform.yml` runs a stricter check — every module is
grepped for the required output names — so a module that quietly drops one
fails CI rather than at the first environment that needs it.
