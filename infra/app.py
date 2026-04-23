#!/usr/bin/env python3
import os
import aws_cdk as cdk
from eks_platform.eks_platform_stack import EksPlatformStack

app = cdk.App()

EksPlatformStack(app, "EksPlatformStack",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION"),
    ),
)

app.synth()
