#!/usr/bin/env bash
# install-kuberay.sh — Install the KubeRay operator on the EKS cluster.
# Run after create-cluster.sh completes.
# KubeRay manages Ray cluster lifecycle as Kubernetes custom resources.

set -euo pipefail

KUBERAY_VERSION="${KUBERAY_VERSION:-1.3.2}"
NAMESPACE="ray-system"

echo "── STEP 1: Add KubeRay Helm repo ───────────────────────────────────────"
helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update

echo ""
echo "── STEP 2: Install KubeRay operator ────────────────────────────────────"
helm install kuberay-operator kuberay/kuberay-operator \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --version "${KUBERAY_VERSION}" \
    --wait

echo ""
echo "── STEP 3: Verify operator is running ──────────────────────────────────"
kubectl get pods -n "${NAMESPACE}"

echo ""
echo "── STEP 4: Verify CRDs are registered ─────────────────────────────────"
kubectl get crd | grep ray

echo ""
echo "KubeRay operator is ready. CRDs available: RayCluster, RayJob, RayService."
echo "Next: submit a RayJob with ./scripts/ray-hello-world.sh"
