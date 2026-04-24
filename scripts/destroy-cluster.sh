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
echo "── STEP 3: Verify everything is gone ───────────────────────────────────"
PASS=0
FAIL=0

check() {
    local label="$1"; local cmd="$2"; local expect_empty="$3"
    local result
    result=$(eval "${cmd}" 2>&1)
    if [[ "${expect_empty}" == "true" && -z "${result}" ]] || \
       [[ "${expect_empty}" == "false" && -n "$(echo "${result}" | grep -i 'does not exist\|not found\|NoSuchEntity\|cannot list\|error')" ]]; then
        echo "  ✓ ${label}"
        PASS=$((PASS + 1))
    else
        echo "  ✗ ${label} — may still exist"
        echo "    ${result}" | head -3
        FAIL=$((FAIL + 1))
    fi
}

# EKS cluster gone
check "EKS cluster deleted" \
    "aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} 2>&1 | grep -i 'not found\|does not exist'" \
    "false"

# eksctl CloudFormation stack gone
check "eksctl CloudFormation stack deleted" \
    "aws cloudformation describe-stacks --stack-name eksctl-${CLUSTER_NAME}-cluster --region ${REGION} 2>&1 | grep -i 'does not exist\|not found'" \
    "false"

# CDK CloudFormation stack gone
check "CDK CloudFormation stack deleted" \
    "aws cloudformation describe-stacks --stack-name EksPlatformStack --region ${REGION} 2>&1 | grep -i 'does not exist\|not found'" \
    "false"

# No EC2 instances with cluster tag still running
check "EC2 nodes terminated" \
    "aws ec2 describe-instances \
        --filters Name=tag:eks:cluster-name,Values=${CLUSTER_NAME} Name=instance-state-name,Values=running,pending,stopping \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text --region ${REGION}" \
    "true"

echo ""
if [[ "${FAIL}" -eq 0 ]]; then
    echo "All ${PASS} checks passed. No idle costs."
else
    echo "${FAIL} check(s) failed — review above. Re-run checks with:"
    echo "  aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION}"
    echo "  aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --region ${REGION}"
fi
