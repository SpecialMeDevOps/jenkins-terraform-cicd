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

Terraform state is kept in the Jenkins workspace because this installation
does not have an S3 state bucket configured. Concurrent builds are disabled and
the workspace is preserved so the next build can use the same state. The
pipeline destroys only resources recorded in that Terraform state, verifies
that the state is empty, and then plans and applies the fresh infrastructure.

The security group has a stable name (`prod-web-sg`). Do not add build numbers
to Terraform resource names, because changing names on every build creates
duplicates instead of allowing Terraform to manage one predictable resource.

Before destroy, the production pipeline bootstraps the AWS CLI when needed and
imports only an existing security group named `prod-web-sg` into Terraform
state. It does not scan or import unrelated security groups. The subsequent
Terraform destroy then removes that imported project resource normally.

Set the Jenkins `DOCKERHUB_NAMESPACE` parameter to the Docker Hub username
that owns the `nginx-demo` repository, or leave it blank to derive the
namespace from the credential username. Do not use the login email address;
Docker image namespaces cannot contain `@`.

Configure `dockerhub-creds` as a username/password credential where the
username is the Docker Hub username (or email) and the password is a Docker
Hub access token with `Read & Write` permission for the `nginx-demo`
repository. The repository must exist under that namespace.

The EC2 AMI is selected dynamically from the latest available official
Canonical Ubuntu 22.04 x86_64 HVM image in the configured AWS region, so the
deployment is not tied to a region-specific AMI ID.

For multiple Jenkins agents or high-availability production use, configure a
real shared S3 backend later. Resources created by older local-state builds
must be imported into this workspace state once, or removed through a reviewed
one-time migration; the pipeline never scans or deletes unrelated AWS
resources.
