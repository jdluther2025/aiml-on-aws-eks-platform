# aiml-on-aws-eks-platform

EKS platform for AI/ML experimentation. Provisions a production-ready EKS cluster using CDK (VPC + IAM) and eksctl (cluster + node groups). Designed as a launchpad — each tutorial in the AI-ML on AWS series runs on this cluster.

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity` works)
- CDK bootstrapped (`cdk bootstrap`)
- [eksctl](https://eksctl.io/installation/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- `envsubst` installed (`brew install gettext` on Mac)

See [AI-ML on AWS #1](https://medium.com/) for the full local setup guide.

## Deploy

```bash
./scripts/create-cluster.sh
```

This runs in sequence:
1. `cdk deploy` — creates VPC, subnets, IAM roles
2. Reads CDK outputs — VPC ID, subnet IDs
3. Generates `cluster/cluster.yaml` from the template
4. `eksctl create cluster` — creates EKS cluster in that VPC
5. `kubectl get nodes` — verifies the cluster is ready

## Verify

```bash
./scripts/smoke-test.sh
```

## Destroy

```bash
./scripts/destroy-cluster.sh
```

Deletes the EKS cluster first (eksctl), then destroys the VPC and IAM (CDK). Order matters — the VPC cannot be deleted while the cluster exists.

## What's in the cluster

| Component | Details |
|---|---|
| Kubernetes | 1.35 |
| Node group | `cpu-nodes` — m5.xlarge, 1–5 nodes |
| Networking | Private nodes, public subnets for load balancers |
| OIDC | Enabled — required for IRSA (pod-level IAM) |
| Add-ons | vpc-cni, coredns, kube-proxy, aws-ebs-csi-driver |

No operators pre-installed. Each tutorial adds what it needs.

## Tutorials on this cluster

- [Blog #4](https://medium.com/) — This setup
- More coming...
