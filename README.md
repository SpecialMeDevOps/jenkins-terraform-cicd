# jenkins-terraform-cicd

Jenkins + GitHub Webhook integration, Jenkins credentials, Terraform AWS
infrastructure, and a complete CI/CD pipeline.

The pipeline bootstraps Terraform `1.16.3` into the workspace when the Jenkins
agent does not already provide Terraform. The agent must have outbound HTTPS access to `releases.hashicorp.com` and
provide `curl` plus either `unzip` or Python.

Before running a production build, create an EC2 key pair named
`jenkins-project` in AWS `us-east-1`, or enter an existing key pair name in the
Jenkins `AWS_KEY_NAME` build parameter. The key pair must already exist;
Terraform cannot create an EC2 key pair without importing its public key.

The EC2 AMI is selected dynamically from the latest available official
Canonical Ubuntu 22.04 x86_64 HVM image in the configured AWS region, so the
deployment is not tied to a region-specific AMI ID.

Terraform uses local state by default so a fresh Jenkins installation does not
depend on a pre-created placeholder S3 bucket. For shared or production
workspaces, configure a real S3 backend in `terraform/provider.tf` before
running concurrent deployments.
