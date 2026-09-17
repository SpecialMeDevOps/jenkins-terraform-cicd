# jenkins-terraform-cicd

Jenkins + GitHub Webhook integration, Jenkins credentials, Terraform AWS
infrastructure, and a complete CI/CD pipeline.

The pipeline bootstraps Terraform `1.9.8` into the workspace when the Jenkins
agent does not already provide Terraform. The agent must have outbound HTTPS access to `releases.hashicorp.com` and
provide `curl` plus either `unzip` or Python.

Terraform uses local state by default so a fresh Jenkins installation does not
depend on a pre-created placeholder S3 bucket. For shared or production
workspaces, configure a real S3 backend in `terraform/provider.tf` before
running concurrent deployments.
