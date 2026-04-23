#!/usr/bin/env bash
# destroy-cluster.sh — Delete EKS cluster, then destroy CDK stack.
# Run from the repo root: ./scripts/destroy-cluster.sh
# Order matters: cluster must be deleted before VPC can be destroyed.

set -euo pipefail

CLUSTER_NAME="eks-ai-platform"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "── STEP 1: Delete EKS cluster with eksctl ──────────────────────────────"
eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}" --wait

echo ""
echo "── STEP 2: Destroy VPC and IAM with CDK ────────────────────────────────"
cd "${REPO_ROOT}/infra"
source .venv/bin/activate
cdk destroy --force
deactivate

echo ""
echo "All resources destroyed. No idle costs."
