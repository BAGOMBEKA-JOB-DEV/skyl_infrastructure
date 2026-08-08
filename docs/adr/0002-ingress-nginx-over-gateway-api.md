# ADR-0002: ingress-nginx rather than Gateway API or cloud-native ingress

**Status:** accepted
**Date:** 2026-08-08

## Context

Three options for getting traffic to the gateway.

**Cloud-native ingress** — ALB on AWS, GCE ingress on GCP, Application Gateway
on Azure. Best integration, and three different annotation vocabularies for the
same behaviour. Server-Sent Events alone would need three distinct
configurations for read timeouts and response buffering, which puts a provider
conditional straight into the chart — precisely what
[ADR-0001](0001-cloud-module-output-contract.md) exists to prevent.

**Gateway API** — the successor to Ingress, and the right long-term answer. But
implementation maturity differs sharply across the three clouds, and the SSE
requirements here need `BackendTrafficPolicy` or an implementation-specific
extension, which is where portability currently breaks down. Adopting it today
would mean writing per-implementation policy objects: the same problem as
cloud-native ingress, in newer syntax.

**ingress-nginx** — one controller, installed by us, behaving identically
everywhere.

## Decision

ingress-nginx, installed by `modules/platform`, with cert-manager for TLS.

The deciding factor is SSE. `/v1/chat/stream` is a long-lived streaming
response, and three defaults break it in ways that present as "the stream just
stops" rather than as an error:

| Default | Effect on SSE |
|---|---|
| `proxy-read-timeout: 60s` | A generation longer than 60s is cut off |
| `proxy-buffering: on` | The whole response is buffered; nothing streams |
| `proxy-http-version: 1.0` | Cannot chunk |

Encoding that once, in `charts/skyl-gateway/templates/ingress.yaml`, is worth
more than the cloud integration given up.

`externalTrafficPolicy: Local` preserves the client source IP, which the
gateway logs and which any future rate limiting depends on.

## Consequences

An extra component to run and upgrade, and a load balancer that is a plain L4
passthrough rather than a managed L7 — so no WAF, and no cloud-native
integrations that hang off the ingress object.

The `ingress_class` contract output already exists, so a deployment that wants
a cloud-native controller can supply one without touching the chart. The SSE
annotations would need translating; that is the cost being deferred.

**Revisit when** all three clouds ship a conformant Gateway API implementation
supporting response-buffering and timeout configuration through portable types.
At that point `ingress_class` becomes a `gatewayClassName` and the annotations
become policy objects. The contract absorbs the change; the chart barely moves.
