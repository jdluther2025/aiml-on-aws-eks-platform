#!/usr/bin/env bash
# ray-hello-world.sh — Build, push, and run the hello world RayJob.
# Proves Ray distributed processing works on the EKS cluster.
# Run after install-kuberay.sh.

set -euo pipefail

# Resolve the script's actual location regardless of how it was invoked.
_SCRIPT="${BASH_SOURCE[0]}"
case "${_SCRIPT}" in
    /*)  ;;                                              # absolute path
    */*) _SCRIPT="${PWD}/${_SCRIPT}" ;;                  # relative with dir
    *)   _SCRIPT="$(command -v "${_SCRIPT}")" ;;         # bare name — resolve from PATH
esac
REPO_ROOT="$(cd "$(dirname "${_SCRIPT}")/.." && pwd)"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')
export AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export RAY_VERSION="${RAY_VERSION:-2.44.0}"

ECR_REPO="ray-hello-world"
IMAGE_TAG="latest"
export IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"

JOB_NAME="hello-world"
NAMESPACE="default"

echo "── STEP 1: Create ECR repository ───────────────────────────────────────"
aws ecr describe-repositories \
    --repository-names "${ECR_REPO}" \
    --region "${AWS_REGION}" > /dev/null 2>&1 || \
aws ecr create-repository \
    --repository-name "${ECR_REPO}" \
    --region "${AWS_REGION}" > /dev/null
echo "ECR repo: ${IMAGE_URI}"

echo ""
echo "── STEP 2: Build Docker image ──────────────────────────────────────────"
docker build \
    --build-arg RAY_VERSION="${RAY_VERSION}" \
    -t "${ECR_REPO}:${IMAGE_TAG}" \
    "${REPO_ROOT}/ray/hello-world"

echo ""
echo "── STEP 3: Push to ECR ─────────────────────────────────────────────────"
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin \
    "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
docker tag "${ECR_REPO}:${IMAGE_TAG}" "${IMAGE_URI}"
docker push "${IMAGE_URI}"

echo ""
echo "── STEP 4: Submit RayJob ────────────────────────────────────────────────"
envsubst < "${REPO_ROOT}/ray/hello-world/rayjob.yaml.template" > /tmp/rayjob-hello-world.yaml
kubectl delete rayjob "${JOB_NAME}" -n "${NAMESPACE}" 2>/dev/null || true
kubectl apply -f /tmp/rayjob-hello-world.yaml -n "${NAMESPACE}"
echo "RayJob submitted. Waiting for Ray head pod to start (~60s)..."

echo ""
echo "── STEP 5: Wait for head pod ───────────────────────────────────────────"
HEAD_POD=""
for i in $(seq 1 24); do
    HEAD_POD=$(kubectl get pods -n "${NAMESPACE}" \
        -l ray.io/node-type=head \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "${HEAD_POD}" ]]; then
        echo "Head pod running: ${HEAD_POD}"
        break
    fi
    echo "  waiting... (${i}/24)"
    sleep 5
done

if [[ -z "${HEAD_POD}" ]]; then
    echo "ERROR: timed out waiting for head pod."
    echo "Debug: kubectl get pods -n ${NAMESPACE}"
    kubectl get pods -n "${NAMESPACE}"
    exit 1
fi

echo ""
echo "── STEP 6: Wait for job to complete ────────────────────────────────────"
JOB_STATUS=""
for i in $(seq 1 40); do
    JOB_STATUS=$(kubectl get rayjob "${JOB_NAME}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.jobStatus}' 2>/dev/null || true)
    if [[ "${JOB_STATUS}" == "SUCCEEDED" || "${JOB_STATUS}" == "FAILED" ]]; then
        echo "Job finished: ${JOB_STATUS}"
        break
    fi
    echo "  job status: ${JOB_STATUS:-pending}... (${i}/40)"
    sleep 5
done

echo ""
echo "── STEP 7: Show distributed output ─────────────────────────────────────"
echo "(Reading Ray driver log from head pod)"
echo ""
DRIVER_LOG=$(kubectl exec "${HEAD_POD}" -n "${NAMESPACE}" -- \
    sh -c 'ls -t /tmp/ray/session_latest/logs/job-driver-*.log 2>/dev/null | head -1' 2>/dev/null || true)

if [[ -n "${DRIVER_LOG}" ]]; then
    kubectl exec "${HEAD_POD}" -n "${NAMESPACE}" -- cat "${DRIVER_LOG}"
else
    echo "Driver log not found — checking worker logs:"
    kubectl exec "${HEAD_POD}" -n "${NAMESPACE}" -- \
        sh -c 'cat /tmp/ray/session_latest/logs/worker-*.log 2>/dev/null | tail -40' || true
fi

echo ""
echo "── STEP 8: Cleanup ─────────────────────────────────────────────────────"
kubectl delete rayjob "${JOB_NAME}" -n "${NAMESPACE}" 2>/dev/null || true
echo "RayJob deleted. KubeRay operator will clean up the Ray cluster pods."

echo ""
echo "── STEP 9: Final status ────────────────────────────────────────────────"
echo "Job result: ${JOB_STATUS}"
