# Observability

## What the gateway actually exports

Two instruments. Not a large surface, and worth knowing exactly, because
several plausible-looking metric names do not exist.

The gateway records through `skyl/otel` rather than counting requests itself,
so the numbers follow the OpenTelemetry GenAI conventions and mean the same
thing whether they came from the gateway or from a Go service importing skyl
directly.

| Instrument | Type |
|---|---|
| `gen_ai.client.token.usage` | Int64 histogram |
| `gen_ai.client.operation.duration` | Float64 histogram, seconds |

The Prometheus exporter renames these. The exported series — taken from a
running exporter, not inferred from the spec:

```
gen_ai_client_token_usage_bucket{...,le="..."}
gen_ai_client_token_usage_sum
gen_ai_client_token_usage_count

gen_ai_client_operation_duration_seconds_bucket{...,le="..."}
gen_ai_client_operation_duration_seconds_sum
gen_ai_client_operation_duration_seconds_count
```

Two details that cost time if you guess:

- **No `_total` suffix.** These are histograms, not counters.
- **Token usage carries no unit suffix**, because its unit is `{token}`.
  Duration gets `_seconds` because its unit is `s`.

Labels include `gen_ai_provider_name`, `gen_ai_request_model`,
`gen_ai_response_model`, `gen_ai_token_type`, plus `otel_scope_name`.

## There is no in-flight gauge

This is the important gap. The gateway exports nothing like
`skyl_gateway_inflight_requests` — a metric name that appears in early drafts
of dashboards because it is the obvious thing to want.

Average concurrency is recoverable from the duration histogram by Little's Law.
The sum of request durations accruing per second **is** the mean number of
requests in flight:

```promql
sum by (pod) (rate(gen_ai_client_operation_duration_seconds_sum[1m]))
```

If ten requests each take one second, one second of duration accrues per
second per concurrent request: the rate is 10, and ten were in flight. No
gauge needed.

### Exposing it to the HPA

`autoscaling.targetConcurrency` scales on this, which is the better signal for
an I/O-bound service — a pod can sit at `SKYL_MAX_CONCURRENT` while barely
registering on CPU.

It needs prometheus-adapter. **Without the adapter the HPA reports
`FailedGetPodsMetric` and stops scaling on CPU as well**, which is why the
value defaults to 0.

```yaml
# prometheus-adapter values
rules:
  custom:
    - seriesQuery: 'gen_ai_client_operation_duration_seconds_sum{namespace!="",pod!=""}'
      resources:
        overrides:
          namespace: {resource: namespace}
          pod: {resource: pod}
      name:
        matches: "gen_ai_client_operation_duration_seconds_sum"
        as: "skyl_gateway_inflight"
      metricsQuery: 'sum by (<<.GroupBy>>) (rate(<<.Series>>{<<.LabelMatchers>>}[1m]))'
```

Confirm it resolved before enabling the target:

```bash
kubectl get --raw \
  "/apis/custom.metrics.k8s.io/v1beta1/namespaces/skyl/pods/*/skyl_gateway_inflight" | jq
```

Then set `autoscaling.targetConcurrency` below `config.maxConcurrent`. The
chart refuses to render if it is not.

## Useful queries

Requests per second by provider:

```promql
sum by (gen_ai_provider_name) (rate(gen_ai_client_operation_duration_seconds_count[5m]))
```

p95 latency by provider:

```promql
histogram_quantile(0.95, sum by (le, gen_ai_provider_name) (
  rate(gen_ai_client_operation_duration_seconds_bucket[10m])
))
```

Token burn per minute, split input/output — the one that maps to money:

```promql
sum by (gen_ai_provider_name, gen_ai_token_type) (
  rate(gen_ai_client_token_usage_sum[1m])
) * 60
```

Mean tokens per request, a good early signal that prompts have grown:

```promql
sum(rate(gen_ai_client_token_usage_sum[10m]))
  / sum(rate(gen_ai_client_token_usage_count[10m]))
```

## Traces

Deliberately absent. A gateway sees every model call in the estate, and one
span per call is the expensive half of instrumentation. `NewTelemetry` sets
`WithoutSpans()`.

To add them, leave `config.metrics` off and register `skylotel.Hook` with your
own tracer provider — see skyl's `gateway/telemetry.go`.

## Logs

JSON to stdout. The ingress controller is configured to match, so both parse
the same way.

Worth alerting on, and not visible in metrics:

```
grace period expired with requests still in flight
```

See [runbook.md](runbook.md#skylgatewaygraceperiodexpired). The process exits 0
after logging this, so nothing else will tell you it happened.
