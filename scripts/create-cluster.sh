#!/usr/bin/env bash
# create-cluster.sh — Deploy VPC with CDK, then create EKS cluster with eksctl.
# Run from the repo root: ./scripts/create-cluster.sh
#
# Override defaults with environment variables before running:
#   INSTANCE_TYPE=t3.medium ./scripts/create-cluster.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STACK_NAME="EksPlatformStack"

# ── Cluster parameters (override via env vars) ─────────────────────────────

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')
export AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export EKS_CLUSTER_NAME="eks-ai-platform"
export K8S_VERSION="${K8S_VERSION:-1.35}"
export EKS_DEFAULT_MNG_NAME="${EKS_DEFAULT_MNG_NAME:-cpu-nodes}"
export EKS_DEFAULT_MNG_MIN="${EKS_DEFAULT_MNG_MIN:-1}"
export EKS_DEFAULT_MNG_MAX="${EKS_DEFAULT_MNG_MAX:-5}"
export EKS_DEFAULT_MNG_DESIRED="${EKS_DEFAULT_MNG_DESIRED:-2}"

# ── Instance type selection ────────────────────────────────────────────────
# Override with: INSTANCE_TYPE=t3.medium ./scripts/create-cluster.sh

if [[ -z "${INSTANCE_TYPE:-}" ]]; then
    echo "── Select node instance type ───────────────────────────────────────────"
    echo "  1) t3.medium   — 2 vCPU,  4GB   (general testing, lowest cost)"
    echo "  2) t3.xlarge   — 4 vCPU, 16GB   (moderate workloads)"
    echo "  3) m5.xlarge   — 4 vCPU, 16GB   (production-like, AI/ML default)"
    echo "  4) m5.2xlarge  — 8 vCPU, 32GB   (heavier AI/ML workloads)"
    echo ""
    read -r -p "Choice (1-4) [default: 3]: " type_choice
    case "${type_choice:-3}" in
        1) INSTANCE_TYPE="t3.medium" ;;
        2) INSTANCE_TYPE="t3.xlarge" ;;
        3) INSTANCE_TYPE="m5.xlarge" ;;
        4) INSTANCE_TYPE="m5.2xlarge" ;;
        *) echo "Invalid choice. Using m5.xlarge."; INSTANCE_TYPE="m5.xlarge" ;;
    esac
fi
export INSTANCE_TYPE

echo ""
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
        --region "${AWS_REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='${1}'].OutputValue" \
        --output text
}

export VPC_ID=$(get_output "VpcId")
export CLUSTER_ROLE_ARN=$(get_output "ClusterRoleArn")
export NODE_ROLE_ARN=$(get_output "NodeRoleArn")
PRIVATE_SUBNETS=$(get_output "PrivateSubnetIds")
PUBLIC_SUBNETS=$(get_output "PublicSubnetIds")

export PRIVATE_SUBNET_1=$(echo "${PRIVATE_SUBNETS}" | cut -d',' -f1)
export PRIVATE_SUBNET_2=$(echo "${PRIVATE_SUBNETS}" | cut -d',' -f2)
export PUBLIC_SUBNET_1=$(echo "${PUBLIC_SUBNETS}" | cut -d',' -f1)
export PUBLIC_SUBNET_2=$(echo "${PUBLIC_SUBNETS}" | cut -d',' -f2)

export AZ_1=$(aws ec2 describe-subnets --subnet-ids "${PRIVATE_SUBNET_1}" --region "${AWS_REGION}" \
    --query "Subnets[0].AvailabilityZone" --output text)
export AZ_2=$(aws ec2 describe-subnets --subnet-ids "${PRIVATE_SUBNET_2}" --region "${AWS_REGION}" \
    --query "Subnets[0].AvailabilityZone" --output text)

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║               EKS Cluster — Architecture Summary                    ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  Cluster name   : ${EKS_CLUSTER_NAME}"
echo "║  AWS account    : ${AWS_ACCOUNT_ID}"
echo "║  Region         : ${AWS_REGION}"
echo "║  Kubernetes     : ${K8S_VERSION}"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  VPC            : ${VPC_ID}"
echo "║  Private subnet : ${PRIVATE_SUBNET_1} (${AZ_1})"
echo "║  Private subnet : ${PRIVATE_SUBNET_2} (${AZ_2})"
echo "║  Public subnet  : ${PUBLIC_SUBNET_1} (${AZ_1})"
echo "║  Public subnet  : ${PUBLIC_SUBNET_2} (${AZ_2})"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  Node group     : ${EKS_DEFAULT_MNG_NAME}"
echo "║  Instance type  : ${INSTANCE_TYPE}"
echo "║  Min / Max      : ${EKS_DEFAULT_MNG_MIN} / ${EKS_DEFAULT_MNG_MAX}"
echo "║  Desired nodes  : ${EKS_DEFAULT_MNG_DESIRED}"
echo "║  Networking     : Private subnets (nodes), Public subnets (LBs)"
echo "╠══════════════════════════════════════════════════════════════════════╣"
echo "║  OIDC / IRSA    : Enabled"
echo "║  Add-ons        : vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver  ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

read -r -p "Proceed with cluster creation? (y/n): " confirm
if [[ "${confirm}" != "y" ]]; then
    echo "Aborted. VPC and IAM remain deployed (run cdk destroy to remove)."
    exit 0
fi

echo ""
echo "── STEP 3: Generate eksctl cluster config ──────────────────────────────"
envsubst < "${REPO_ROOT}/cluster/cluster.yaml.template" > "${REPO_ROOT}/cluster/cluster.yaml"
echo "Written: cluster/cluster.yaml"

echo ""
echo "── STEP 4: Create EKS cluster with eksctl ──────────────────────────────"
eksctl create cluster -f "${REPO_ROOT}/cluster/cluster.yaml"

echo ""
echo "── STEP 5: Verify ──────────────────────────────────────────────────────"
kubectl get nodes
echo ""
echo "EKS cluster ${EKS_CLUSTER_NAME} is ready."
