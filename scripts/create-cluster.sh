#!/usr/bin/env bash
# create-cluster.sh — Deploy VPC with CDK, then create EKS cluster with eksctl.
# Run from the repo root: ./scripts/create-cluster.sh

set -euo pipefail

STACK_NAME="EksPlatformStack"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "── STEP 1: Deploy VPC and IAM with CDK ────────────────────────────────"
cd "${REPO_ROOT}/infra"
python3 -m venv .venv 2>/dev/null || true
source .venv/bin/activate
pip install -q -r requirements.txt
cdk deploy --require-approval never
deactivate

echo ""
echo "── STEP 2: Read CDK outputs ────────────────────────────────────────────"

get_output() {
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='${1}'].OutputValue" \
        --output text
}

VPC_ID=$(get_output "VpcId")
PRIVATE_SUBNETS=$(get_output "PrivateSubnetIds")
PUBLIC_SUBNETS=$(get_output "PublicSubnetIds")

PRIVATE_SUBNET_1=$(echo "${PRIVATE_SUBNETS}" | cut -d',' -f1)
PRIVATE_SUBNET_2=$(echo "${PRIVATE_SUBNETS}" | cut -d',' -f2)
PUBLIC_SUBNET_1=$(echo "${PUBLIC_SUBNETS}" | cut -d',' -f1)
PUBLIC_SUBNET_2=$(echo "${PUBLIC_SUBNETS}" | cut -d',' -f2)

# Resolve AZ for each subnet
AZ_1=$(aws ec2 describe-subnets --subnet-ids "${PRIVATE_SUBNET_1}" --region "${REGION}" \
    --query "Subnets[0].AvailabilityZone" --output text)
AZ_2=$(aws ec2 describe-subnets --subnet-ids "${PRIVATE_SUBNET_2}" --region "${REGION}" \
    --query "Subnets[0].AvailabilityZone" --output text)

echo "VPC:             ${VPC_ID}"
echo "Private subnets: ${PRIVATE_SUBNET_1} (${AZ_1}), ${PRIVATE_SUBNET_2} (${AZ_2})"
echo "Public subnets:  ${PUBLIC_SUBNET_1} (${AZ_1}), ${PUBLIC_SUBNET_2} (${AZ_2})"

echo ""
echo "── STEP 3: Generate eksctl cluster config ──────────────────────────────"

export VPC_ID PRIVATE_SUBNET_1 PRIVATE_SUBNET_2 PUBLIC_SUBNET_1 PUBLIC_SUBNET_2 AZ_1 AZ_2
export AWS_REGION="${REGION}"

envsubst < "${REPO_ROOT}/cluster/cluster.yaml.template" > "${REPO_ROOT}/cluster/cluster.yaml"
echo "Written: cluster/cluster.yaml"

echo ""
echo "── STEP 4: Create EKS cluster with eksctl ──────────────────────────────"
eksctl create cluster -f "${REPO_ROOT}/cluster/cluster.yaml"

echo ""
echo "── STEP 5: Verify ──────────────────────────────────────────────────────"
kubectl get nodes
echo ""
echo "EKS cluster eks-ai-platform is ready."
