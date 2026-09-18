# Jenkins + Terraform + AWS SSM deployment

This project provisions an Ubuntu EC2 web server with Terraform, builds and
pushes the Docker image to Docker Hub, and deploys it through AWS Systems
Manager (SSM). The pipeline does not use SSH, port 22, a `.pem` file, or an
SSH credential.

## Required Jenkins credentials

The pipeline currently obtains AWS credentials from Jenkins credentials with
these IDs:

- `aws-access-key-id`: AWS access key ID
- `aws-secret-access-key`: AWS secret access key
- `dockerhub-creds`: Docker Hub username and a read/write access token

For production, prefer assigning the Jenkins agent an AWS IAM instance profile
or configuring Jenkins OIDC/web-identity federation. In that case, remove the
two AWS `withCredentials` bindings from the Jenkinsfile and let the AWS CLI and
Terraform use the agent role. Never put AWS keys in the Jenkinsfile, Terraform
files, Git, or build parameters.

## AWS permissions

The Jenkins AWS identity needs the Terraform permissions for the resources in
this project, plus these SSM deployment permissions:

- `ssm:DescribeInstanceInformation`
- `ssm:SendCommand`
- `ssm:GetCommandInvocation`
- `ec2:DescribeInstances`
- `ec2:DescribeSecurityGroups`
- `iam:GetRole`
- `iam:GetInstanceProfile`
- `iam:ListAttachedRolePolicies`

The Terraform identity also needs to create and destroy the EC2, security
group, IAM role, IAM policy attachment, and IAM instance profile resources.
Use a least-privilege policy scoped to the project resources in production.

## Terraform and networking

The EC2 instance receives the AWS-managed
`AmazonSSMManagedInstanceCore` policy through an IAM role and instance profile.
Cloud-init installs Docker, installs the Ubuntu SSM Agent through snap, enables
both services, and waits for the agent to start.

The security group allows HTTP on port 80 and unrestricted outbound traffic so
the instance can reach the regional SSM endpoints through its existing public
network path. Port 22 is not opened. For a private-subnet production design,
replace the public path with VPC interface endpoints for `ssm`, `ssmmessages`,
and `ec2messages`, plus the required private subnet routing and endpoint
security group.

Terraform outputs `instance_id`, `instance_public_ip`, and `application_url`.
The Jenkins pipeline always obtains the current instance ID from
`terraform output -raw instance_id`, so an EC2 replacement does not leave a
stale IP or SSH key reference.

## Pipeline flow

```text
GitHub Push
  -> Checkout and validation
  -> Terraform init
  -> Reconcile known project resources
  -> Terraform destroy and verification
  -> Terraform plan and approval
  -> Terraform apply
  -> Get current EC2 instance ID
  -> Wait for EC2 and SSM Online
  -> Send Docker deployment through SSM
  -> Verify SSM target
  -> Smoke test the application URL
```

The SSM command verifies Docker, pulls
`malikzohaib1482/workdocker-222:<build-number>`, replaces the `web` container,
and verifies that the new container is running. Failed SSM commands fail the
Jenkins build.

## Jenkins parameters

- `AWS_REGION`: AWS region, default `ap-south-1`
- `DOCKERHUB_NAMESPACE`: default `malikzohaib1482`

There is no AWS key-pair parameter and no SSH credential parameter. Terraform
does not store a private SSH key or require one to create the instance.
