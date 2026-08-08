# ADR-0004: Egress restricted by port, not by destination

**Status:** accepted
**Date:** 2026-08-08

## Context

The gateway pod holds provider API keys and, by design, makes outbound HTTPS
calls to arbitrary internet hosts. That is its function. It is also the ideal
position from which to exfiltrate those keys.

Ideally egress would be limited to the provider endpoints — `api.anthropic.com`,
`api.openai.com`, `generativelanguage.googleapis.com`. Kubernetes
`NetworkPolicy` cannot express that. Its `ipBlock` selector takes CIDRs, and
provider IP ranges are neither published nor stable; they sit behind CDNs whose
addresses change without notice.

## Decision

Restrict what can be expressed, and be explicit about what cannot.

```yaml
egress:
  - to: [namespaceSelector: kube-system]      # DNS
    ports: [53/UDP, 53/TCP]
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
          except:
            - 169.254.0.0/16      # cloud metadata
            - 10.0.0.0/8          # cluster-internal
            - 172.16.0.0/12
            - 192.168.0.0/16
    ports: [443/TCP]
```

Three real properties, despite the `0.0.0.0/0`:

- **Port 443 only.** No plaintext exfiltration, no DNS tunnelling to a
  non-cluster resolver, no arbitrary outbound protocol.
- **No cloud metadata.** `169.254.169.254` is the instance metadata service on
  all three clouds. Reaching it from a pod is a direct route to node
  credentials, and it is a standard step in container escape. On AWS this is
  defended twice — IMDSv2 with `http_put_response_hop_limit = 1` in the node
  group makes it unreachable from a pod regardless of NetworkPolicy.
- **No lateral movement.** RFC1918 ranges are excluded, so a compromised gateway
  cannot scan the VPC or reach other services.

## Consequences

A compromised gateway can still POST the keys to an attacker-controlled HTTPS
endpoint. This ADR does not prevent that, and it would be dishonest to imply
otherwise — the control is real but partial.

Detection compensates where prevention cannot: VPC flow logs are on, and
`gen_ai_client_operation_duration_seconds_count` by provider makes unusual
traffic visible.

Enforcement depends on the CNI. Every cloud module configures a policy-capable
one — Autopilot enables NetworkPolicy unconditionally, the AWS module sets
`enableNetworkPolicy` on the VPC CNI add-on, and Azure uses Cilium. Without one,
the policy is accepted by the API server and silently ignored, which is worse
than having none: it reports a control that is not there.

**To close the gap properly**, either:

- **Cilium with FQDN policy** (`toFQDNs`), giving true hostname-based egress. It
  is the default on the Azure module already; the others would need Cilium
  installed in place of their default CNI.
- **An egress proxy** with an allowlist, forcing all outbound traffic through
  one auditable hop.

Both were judged disproportionate for the current scale. Revisit when the
gateway holds credentials for more than one organisation, at which point the
blast radius changes character.
