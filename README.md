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

Terraform state is stored in an existing S3 bucket configured through the
Jenkins `TF_STATE_BUCKET` and `TF_STATE_KEY` parameters, with S3-native state
locking enabled. The pipeline destroys
only resources recorded in that Terraform state, verifies that the state is
empty, and then plans and applies the fresh infrastructure. The S3 bucket must
be created and protected separately; it is not destroyed by this pipeline.

The security group has a stable name (`prod-web-sg`). Do not add build numbers
to Terraform resource names, because changing names on every build creates
duplicates instead of allowing Terraform to manage one predictable resource.

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

This project requires the shared S3 backend above for Jenkins runs. If
resources were created by an older local-state build, migrate or import only
those known project resources into the remote state once before enabling
destroy-before-apply.
