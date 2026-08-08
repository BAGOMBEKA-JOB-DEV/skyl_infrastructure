# tflint configuration.
#
# Pinned explicitly rather than relying on whichever rules the installed tflint
# happens to default to. A linter whose rule set moves with its version turns an
# unrelated CI upgrade into a red build on untouched code.

config {
  # Modules are called with real inputs from environments/, so linting them
  # standalone (where every variable is unset) produces noise about values
  # tflint cannot know.
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  # The "recommended" preset includes naming conventions, documented variables
  # and outputs, unused declarations, and required version constraints.
  preset  = "recommended"
}

# Cloud provider rulesets are deliberately NOT enabled.
#
# They overlap heavily with Trivy and Checkov, which already run in
# security.yml and report to code scanning where findings can be triaged. Three
# tools flagging the same missing encryption block produces three tickets for
# one decision, and the tflint versions have no SARIF path — so their findings
# would only ever appear as build failures with nowhere to record a
# justification.

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# Every variable and output in this repository carries a description, and
# several are load-bearing (the digest format, the grace period). Enforced so
# that stays true.
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

# Off. The bootstrap configurations deliberately have no backend block — they
# are what creates the backend — and this rule cannot express that exception.
rule "terraform_unused_required_providers" {
  enabled = false
}
