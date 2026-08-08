# Bootstrap

The chicken-and-egg step: a remote backend cannot be stored in the state it
stores. These configurations create the state bucket for each cloud, and are
themselves applied with **local state** exactly once.

Run before the first apply in `environments/`.

## GCP

```bash
cd gcp
terraform init          # local state, no backend block
terraform apply -var project_id=<project>
```

Then use the bucket it prints:

```bash
cd ../../environments/dev/gcp
terraform init -backend-config="bucket=$(cd ../../../bootstrap/gcp && terraform output -raw bucket)"
```

## AWS

```bash
cd aws
terraform init
terraform apply

cd ../../environments/dev/aws
terraform init \
  -backend-config="bucket=$(cd ../../../bootstrap/aws && terraform output -raw bucket)" \
  -backend-config="dynamodb_table=$(cd ../../../bootstrap/aws && terraform output -raw lock_table)"
```

## Azure

```bash
cd azure
terraform apply -var subscription_id=<sub>

cd ../../environments/dev/azure
terraform init \
  -backend-config="resource_group_name=$(cd ../../../bootstrap/azure && terraform output -raw resource_group)" \
  -backend-config="storage_account_name=$(cd ../../../bootstrap/azure && terraform output -raw storage_account)" \
  -backend-config="container_name=tfstate"
```

## The local state file

Each bootstrap directory produces a `terraform.tfstate` that is **not**
committed — `.gitignore` covers it. Losing it is survivable: the resources are
named deterministically, so a re-apply either succeeds or reports "already
exists", and `terraform import` recovers the rest. Nothing here holds anything
that cannot be recreated.

Do not be tempted to migrate bootstrap state into the bucket it created.
Destroying the environment then requires the bucket that holds the state
describing the bucket, and that knot is worse than an untracked local file.

## Why versioning is on

Every backend below has object versioning enabled and deletion protection
where the provider offers it. State corruption is rare; recovering from it
without a previous version is not something you want to attempt during an
incident.
