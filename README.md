# Jenkins + Terraform + AWS Docker deployment

This project provisions an Ubuntu EC2 web server with Terraform, builds and
pushes the Docker image to Docker Hub, and deploys it from EC2 cloud-init.
There is no SSH, port 22, `.pem` file, SSM agent, or SSH credential.

## Required Jenkins credentials

The pipeline currently obtains AWS credentials from Jenkins credentials with
these IDs:

- `aws-access-key-id`: AWS access key ID
- `aws-secret-access-key`: AWS secret access key
- `dockerhub-creds`: Docker Hub username and a read/write access token

For production, prefer assigning the Jenkins agent an AWS IAM instance profile
or configuring OIDC/web-identity federation. In that case, remove the AWS
`withCredentials` bindings from the Jenkinsfile and let Terraform/AWS CLI use
the agent role. Never put AWS keys in the Jenkinsfile, Terraform files, Git, or
build parameters.

## AWS permissions

The Jenkins AWS identity needs the Terraform permissions for the resources in
this project, including EC2 and security-group read/create/update/delete
permissions. It also needs the IAM permissions required to create and destroy
the Terraform-managed resources. Use a least-privilege policy scoped to the
project resources in production.

The EC2 instance does not need an IAM role because deployment is performed by
its startup script and the Docker image is public.

## Terraform and deployment

The EC2 security group allows HTTP on port 80 and unrestricted outbound
traffic. Port 22 is not opened. Cloud-init installs Docker, waits for the
Docker daemon, pulls the image passed through Terraform, replaces the `web`
container, and verifies that it is running. Bootstrap output is written to
`/var/log/jenkins-terraform-bootstrap.log` and
`/var/log/cloud-init-output.log`.

Terraform outputs `instance_id`, `instance_public_ip`, and `application_url`.
`user_data_replace_on_change` ensures that changing the image tag causes the
instance to be replaced and the new image to be deployed. The pipeline always
builds and pushes the image before `terraform plan`, then passes the exact
build image as `deployment_image`.

The Docker Hub repository must be publicly readable. If it is private, Docker
Hub credentials must be provided to cloud-init through a separate secret
mechanism; do not put them in Terraform state or user data.

## Pipeline flow

```text
GitHub Push
  -> Checkout and validation
  -> Build and push Docker image
  -> Terraform init
  -> Reconcile known project resources
  -> Terraform destroy and verification
  -> Terraform plan with deployment_image
  -> Approval
  -> Terraform apply
  -> EC2 cloud-init installs Docker and starts the image
  -> HTTP smoke test
```

Terraform destroys and recreates the project instance on each deployment. The
new instance receives the current image from Terraform, so no old IP address,
instance ID, SSH key, or SSM registration is reused.

## Jenkins parameters

- `AWS_REGION`: AWS region, default `ap-south-1`
- `DOCKERHUB_NAMESPACE`: default `malikzohaib1482`

## Manual setup

1. Create the three Jenkins credentials listed above, or configure an AWS IAM
   role/OIDC for the Jenkins agent.
2. Ensure Docker is installed and usable by the Jenkins agent.
3. Ensure the Docker Hub repository is public and the Docker credential can
   push to it.
4. Push to the repository and approve the production input when prompted.

After approval, the Jenkins build waits for Terraform apply and then tests the
current `application_url`. No SSH or SSM action is required.
