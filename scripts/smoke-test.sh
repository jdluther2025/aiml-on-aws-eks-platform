#!/usr/bin/env bash
# smoke-test.sh — Verify EKS cluster is healthy and ready for workloads.
# Run after create-cluster.sh completes.

set -euo pipefail

CLUSTER_NAME="eks-ai-platform"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "── Cluster info ────────────────────────────────────────────────────────"
kubectl cluster-info

echo ""
echo "── Nodes ───────────────────────────────────────────────────────────────"
kubectl get nodes -o wide

echo ""
echo "── System pods ─────────────────────────────────────────────────────────"
kubectl get pods -n kube-system

echo ""
echo "── Smoke test: run a hello-world pod ───────────────────────────────────"
kubectl delete pod smoke-test --ignore-not-found
kubectl run smoke-test \
    --image=public.ecr.aws/docker/library/busybox:latest \
    --restart=Never \
    --command -- echo "Hello from EKS node"

kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/smoke-test --timeout=90s
kubectl logs smoke-test
kubectl delete pod smoke-test

echo ""
echo "Cluster is healthy and ready for workloads."
