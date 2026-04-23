from aws_cdk import (
    Stack,
    CfnOutput,
    Tags,
    aws_ec2 as ec2,
    aws_iam as iam,
)
from constructs import Construct

CLUSTER_NAME = "eks-ai-platform"


class EksPlatformStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ── VPC ────────────────────────────────────────────────────────────────
        # Dedicated VPC — the default VPC is not suitable for EKS.
        # 2 AZs: enough for a lab cluster and keeps NAT Gateway cost to one.
        # Nodes go in private subnets; load balancers use public subnets.

        vpc = ec2.Vpc(self, "EksVpc",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
        )

        # Subnet tags required by EKS and the AWS Load Balancer Controller
        # for automatic subnet discovery.
        for subnet in vpc.public_subnets:
            Tags.of(subnet).add(f"kubernetes.io/cluster/{CLUSTER_NAME}", "shared")
            Tags.of(subnet).add("kubernetes.io/role/elb", "1")

        for subnet in vpc.private_subnets:
            Tags.of(subnet).add(f"kubernetes.io/cluster/{CLUSTER_NAME}", "shared")
            Tags.of(subnet).add("kubernetes.io/role/internal-elb", "1")

        # ── IAM: EKS Cluster Role ──────────────────────────────────────────────
        # The control plane assumes this role to manage AWS resources on your
        # behalf (VPC, EC2, ELB, etc.).

        cluster_role = iam.Role(self, "EksClusterRole",
            assumed_by=iam.ServicePrincipal("eks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSClusterPolicy"),
            ],
        )

        # ── IAM: Node Group Role ───────────────────────────────────────────────
        # EC2 nodes assume this role. Intentionally minimal — workload-level
        # AWS access (Bedrock, S3, etc.) is handled via IRSA per tutorial,
        # not granted broadly to all nodes.

        node_role = iam.Role(self, "EksNodeGroupRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKSWorkerNodePolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEKS_CNI_Policy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonEC2ContainerRegistryReadOnly"),
            ],
        )

        # ── Outputs ────────────────────────────────────────────────────────────
        # scripts/create-cluster.sh reads these to build the eksctl config.

        CfnOutput(self, "VpcId",
            value=vpc.vpc_id,
            description="VPC ID — used in cluster/cluster.yaml",
        )

        CfnOutput(self, "PrivateSubnetIds",
            value=",".join([s.subnet_id for s in vpc.private_subnets]),
            description="Private subnet IDs for EKS nodes (comma-separated)",
        )

        CfnOutput(self, "PublicSubnetIds",
            value=",".join([s.subnet_id for s in vpc.public_subnets]),
            description="Public subnet IDs for load balancers (comma-separated)",
        )

        CfnOutput(self, "ClusterRoleArn",
            value=cluster_role.role_arn,
            description="IAM role ARN for EKS control plane",
        )

        CfnOutput(self, "NodeRoleArn",
            value=node_role.role_arn,
            description="IAM role ARN for EKS node group",
        )

        CfnOutput(self, "ClusterName",
            value=CLUSTER_NAME,
            description="EKS cluster name — used in eksctl and kubectl commands",
        )
