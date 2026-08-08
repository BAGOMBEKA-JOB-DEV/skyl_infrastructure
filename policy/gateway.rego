# Invariants that a future edit must not quietly regress.
#
# The Helm chart already refuses to render several of these. That is not
# duplication: a `fail` in a template protects the chart's own defaults, while
# these run over rendered YAML and so also cover an environment overlay, a
# `--set` on the command line, or a hand-written manifest that bypasses the
# chart entirely.
#
# Each rule states the consequence, not just the requirement, because the
# reason is the part that stops someone "fixing" the failure by loosening the
# rule.
package main

import rego.v1

deployments contains input if {
	input.kind == "Deployment"
}

# --- shutdown ----------------------------------------------------------------

# The gateway's documented worst case is ~32s: a 2s drain delay so the load
# balancer observes /readyz going 503, then up to 30s of grace for in-flight
# streams. Below 40 the kubelet SIGKILLs it mid-drain.
deny contains msg if {
	some d in deployments
	grace := object.get(d.spec.template.spec, "terminationGracePeriodSeconds", 30)
	grace < 40
	msg := sprintf(
		"%s/%s: terminationGracePeriodSeconds is %v, must be >= 40. The gateway needs ~32s to drain; a shorter period SIGKILLs it mid-shutdown and truncates live SSE streams the provider has already billed for.",
		[d.kind, d.metadata.name, grace],
	)
}

# --- probes ------------------------------------------------------------------

# /healthz stays 200 throughout the drain, deliberately. /readyz goes 503
# immediately. Wiring liveness to /readyz therefore restarts the pod during
# every graceful shutdown — the exact opposite of the intent.
deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	c.livenessProbe.httpGet.path == "/readyz"
	msg := sprintf(
		"%s/%s container %q: livenessProbe points at /readyz. It must be /healthz. /readyz returns 503 while draining, so this restarts the pod during every graceful shutdown.",
		[d.kind, d.metadata.name, c.name],
	)
}

deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	c.readinessProbe.httpGet.path == "/healthz"
	msg := sprintf(
		"%s/%s container %q: readinessProbe points at /healthz, which stays 200 while draining. Traffic keeps arriving at a pod that is shutting down. Use /readyz.",
		[d.kind, d.metadata.name, c.name],
	)
}

# The image is distroless with no shell. An exec probe fails with "no such file
# or directory", which surfaces as a crash rather than as a config error.
deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	some probe in ["livenessProbe", "readinessProbe", "startupProbe"]
	object.get(c, [probe, "exec"], null) != null
	msg := sprintf(
		"%s/%s container %q: %s uses exec. The image is distroless/static and has no shell, so this always fails. Use httpGet.",
		[d.kind, d.metadata.name, c.name, probe],
	)
}

deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	not c.livenessProbe
	msg := sprintf("%s/%s container %q: no livenessProbe.", [d.kind, d.metadata.name, c.name])
}

deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	not c.readinessProbe
	msg := sprintf("%s/%s container %q: no readinessProbe.", [d.kind, d.metadata.name, c.name])
}

# --- image provenance --------------------------------------------------------

# A tag is a mutable pointer: the same upgrade run twice can deploy different
# bytes, so a rollback becomes a guess and the cosign signature covers a digest
# nobody recorded.
deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	not contains(c.image, "@sha256:")
	msg := sprintf(
		"%s/%s container %q: image %q is not pinned by digest. Take the digest from skyl's publish-image workflow summary; a mutable tag makes rollbacks unreproducible.",
		[d.kind, d.metadata.name, c.name, c.image],
	)
}

# --- container hardening -----------------------------------------------------

deny contains msg if {
	some d in deployments
	not d.spec.template.spec.securityContext.runAsNonRoot
	msg := sprintf("%s/%s: pod securityContext.runAsNonRoot must be true.", [d.kind, d.metadata.name])
}

deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	not c.securityContext.readOnlyRootFilesystem
	msg := sprintf(
		"%s/%s container %q: readOnlyRootFilesystem must be true. The gateway writes nothing but temporary files; mount an emptyDir at /tmp instead.",
		[d.kind, d.metadata.name, c.name],
	)
}

deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	c.securityContext.allowPrivilegeEscalation
	msg := sprintf("%s/%s container %q: allowPrivilegeEscalation must be false.", [d.kind, d.metadata.name, c.name])
}

deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	not "ALL" in object.get(c, ["securityContext", "capabilities", "drop"], [])
	msg := sprintf("%s/%s container %q: must drop ALL capabilities.", [d.kind, d.metadata.name, c.name])
}

# --- resources ---------------------------------------------------------------

deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	not c.resources.requests.memory
	msg := sprintf(
		"%s/%s container %q: no memory request. Without one the pod is BestEffort and is evicted first under node pressure.",
		[d.kind, d.metadata.name, c.name],
	)
}

deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	not c.resources.limits.memory
	msg := sprintf("%s/%s container %q: no memory limit. A leak should be killed, not allowed to take the node.", [d.kind, d.metadata.name, c.name])
}

# A CPU limit is deliberately absent, not forgotten: the gateway is I/O-bound
# and throttling adds latency for no isolation the request does not already
# give. Warn rather than deny, so an operator who genuinely wants one can.
warn contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	c.resources.limits.cpu
	msg := sprintf(
		"%s/%s container %q: a CPU limit is set. The gateway spends nearly all of a request waiting on a provider, so throttling adds latency without improving isolation. Intentional?",
		[d.kind, d.metadata.name, c.name],
	)
}

# --- availability ------------------------------------------------------------

# Note the explicit `d.spec.replicas`, not a defaulted lookup. When an HPA owns
# the deployment the chart omits `replicas` entirely — that is correct, and
# defaulting the absent field to 1 here reported a violation against the
# chart's own defaults. Absent means "the HPA decides", and the rule below
# covers that case instead.
deny contains msg if {
	some d in deployments
	d.spec.replicas == 1
	not d.spec.template.metadata.annotations["skyl.dev/single-replica-acknowledged"]
	msg := sprintf(
		"%s/%s: one replica means every rollout and node drain is an outage, and a PodDisruptionBudget cannot protect it. Set replicaCount >= 2, or annotate skyl.dev/single-replica-acknowledged if this is a scratch environment.",
		[d.kind, d.metadata.name],
	)
}

deny contains msg if {
	input.kind == "HorizontalPodAutoscaler"
	input.spec.minReplicas < 2
	msg := sprintf(
		"HorizontalPodAutoscaler/%s: minReplicas is %v. Scaling to a single pod reintroduces the outage the PodDisruptionBudget exists to prevent, during exactly the quiet periods when a node drain is most likely.",
		[input.metadata.name, input.spec.minReplicas],
	)
}

# maxUnavailable > 0 lets a rollout remove capacity while old pods are still
# retiring 30s-long streams.
deny contains msg if {
	some d in deployments
	mu := object.get(d.spec, ["strategy", "rollingUpdate", "maxUnavailable"], 0)
	mu != 0
	msg := sprintf(
		"%s/%s: strategy.rollingUpdate.maxUnavailable is %v, must be 0. An old pod can take 32s to retire its streams; surge first so capacity never dips.",
		[d.kind, d.metadata.name, mu],
	)
}

# --- secrets -----------------------------------------------------------------

# Provider keys and the bearer token must come from the cloud secret store.
deny contains msg if {
	some d in deployments
	some c in d.spec.template.spec.containers
	some e in object.get(c, "env", [])
	e.name in {"SKYL_AUTH_TOKEN", "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "SKYL_COMPAT_API_KEY"}
	e.value
	msg := sprintf(
		"%s/%s container %q: %s is set as a literal value. Credentials must arrive via envFrom/secretRef from External Secrets, never inline where they land in git and in `kubectl get deploy -o yaml`.",
		[d.kind, d.metadata.name, c.name, e.name],
	)
}

# --- service accounts --------------------------------------------------------

deny contains msg if {
	input.kind == "ServiceAccount"
	input.metadata.annotations["iam.gke.io/gcp-service-account"]
	input.automountServiceAccountToken == false
	msg := sprintf(
		"ServiceAccount/%s: carries a GKE workload-identity annotation but automountServiceAccountToken is false, so federation cannot work. Either drop the annotation or set serviceAccount.automountToken=true.",
		[input.metadata.name],
	)
}
