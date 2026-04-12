#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass() {
  echo "PASS: $*"
  "$@"
}

expect_fail() {
  local label="$1"
  local expected="$2"
  shift 2

  local log_file="$TMP_DIR/${label//[^A-Za-z0-9_.-]/_}.log"
  if "$@" >"$log_file" 2>&1; then
    echo "FAIL: ${label} unexpectedly succeeded"
    cat "$log_file"
    return 1
  fi

  if ! grep -Fq "$expected" "$log_file"; then
    echo "FAIL: ${label} did not contain expected error: $expected"
    cat "$log_file"
    return 1
  fi

  echo "PASS: ${label}"
}

cd "$ROOT_DIR"

pass python3 -m json.tool values.schema.json >/dev/null
pass bash -n ci/verify.sh
pass helm lint .
pass helm lint . -f ci/test-values.yaml
pass helm lint . -f ci/existing-claim-values.yaml
pass helm lint . -f ci/external-bootstrap-values.yaml
pass helm lint . -f ci/default-service-ports-values.yaml
pass helm template hermes . >"$TMP_DIR/default.yaml"
pass helm template hermes . -f ci/test-values.yaml >"$TMP_DIR/test-values.yaml"
pass helm template hermes . -f ci/existing-claim-values.yaml >"$TMP_DIR/existing-claim.yaml"
pass helm template hermes . -f ci/external-bootstrap-values.yaml >"$TMP_DIR/external-bootstrap.yaml"
pass helm template hermes . -f ci/default-service-ports-values.yaml >"$TMP_DIR/default-service-ports.yaml"

grep -q 'name: hermes-shared-bootstrap' "$TMP_DIR/external-bootstrap.yaml"
if grep -q '^kind: ConfigMap$' "$TMP_DIR/external-bootstrap.yaml"; then
  echo "FAIL: external bootstrap fixture should not render a chart-managed ConfigMap"
  exit 1
fi
echo "PASS: external bootstrap fixture reuses an existing ConfigMap"

grep -q 'name: api-server' "$TMP_DIR/default-service-ports.yaml"
grep -q 'name: webhook' "$TMP_DIR/default-service-ports.yaml"
grep -q 'name: telegram-webhook' "$TMP_DIR/default-service-ports.yaml"
echo "PASS: default service-port fixture auto-derives common Hermes listener ports"

expect_fail \
  "telegram webhook URL required" \
  "telegramWebhook.url: String length must be greater than or equal to 1" \
  helm lint . --set telegramWebhook.enabled=true

expect_fail \
  "service exposure requires ports or enabled endpoints" \
  "Must validate one and only one schema (oneOf)" \
  helm lint . -f ci/negative-service-values.yaml

expect_fail \
  "persistent replicas limited to one" \
  "replicaCount: replicaCount must be one of the following: 1" \
  helm lint . -f ci/negative-persistent-replicas-values.yaml

expect_fail \
  "virtual service gateways required" \
  "virtualService.enabled=true requires at least one entry in virtualService.gateways" \
  helm lint . --set service.enabled=true --set apiServer.enabled=true --set virtualService.enabled=true
