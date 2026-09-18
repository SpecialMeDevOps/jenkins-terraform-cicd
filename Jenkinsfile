pipeline {
    agent any

    environment {
        TF_WORKING_DIR = 'terraform'
        TF_VERSION     = '1.16.3'
        TF_BIN_DIR     = "${WORKSPACE}/.tools"
        APP_DIR        = 'app'
        DOCKER_REPOSITORY = 'workdocker-222'
        PATH           = "${WORKSPACE}/.tools:${PATH}"
    }

    parameters {
        string(
            name: 'AWS_REGION',
            defaultValue: 'ap-south-1',
            description: 'AWS region for the deployment'
        )
        string(
            name: 'AWS_KEY_NAME',
            defaultValue: 'jenkins-project',
            description: 'Existing EC2 key pair name in the selected AWS region'
        )
        string(
            name: 'DOCKERHUB_NAMESPACE',
            defaultValue: 'malikzohaib1482',
            description: 'Docker Hub username/namespace that owns workdocker-222'
        )
    }

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh 'echo "Branch: $GIT_BRANCH | Commit: $GIT_COMMIT"'
            }
        }

        stage('Lint & Validate') {
            steps {
                sh 'echo "=== Validating app ==="'
                sh "test -f ${APP_DIR}/index.html"
                sh "test -f ${APP_DIR}/Dockerfile"
            }
        }

        stage('Install Terraform') {
            steps {
                sh '''
                    set -eu

                    if command -v terraform >/dev/null 2>&1; then
                        terraform version
                        exit 0
                    fi

                    if ! command -v curl >/dev/null 2>&1; then
                        echo "Required tool 'curl' is missing from the Jenkins agent" >&2
                        exit 1
                    fi

                    os="$(uname -s)"
                    arch="$(uname -m)"
                    case "${os}:${arch}" in
                        Linux:x86_64) artifact_os="linux"; artifact_arch="amd64" ;;
                        Linux:aarch64) artifact_os="linux"; artifact_arch="arm64" ;;
                        Darwin:x86_64) artifact_os="darwin"; artifact_arch="amd64" ;;
                        Darwin:arm64) artifact_os="darwin"; artifact_arch="arm64" ;;
                        *)
                            echo "Unsupported agent platform: ${os}/${arch}" >&2
                            exit 1
                            ;;
                    esac

                    tmp_dir="$(mktemp -d)"
                    trap 'rm -rf "${tmp_dir}"' EXIT
                    mkdir -p "${TF_BIN_DIR}"
                    curl --fail --silent --show-error --location --retry 3 \
                        --output "${tmp_dir}/terraform.zip" \
                        "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_${artifact_os}_${artifact_arch}.zip"
                    if command -v unzip >/dev/null 2>&1; then
                        unzip -oq "${tmp_dir}/terraform.zip" -d "${TF_BIN_DIR}"
                    elif command -v python3 >/dev/null 2>&1; then
                        python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
                            "${tmp_dir}/terraform.zip" "${TF_BIN_DIR}"
                    elif command -v python >/dev/null 2>&1; then
                        python -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
                            "${tmp_dir}/terraform.zip" "${TF_BIN_DIR}"
                    else
                        echo "Terraform archive extraction requires 'unzip', 'python3', or 'python'" >&2
                        exit 1
                    fi
                    chmod +x "${TF_BIN_DIR}/terraform"
                    test -x "${TF_BIN_DIR}/terraform"
                    terraform version
                '''
            }
        }

        stage('Terraform Init') {
            steps {
                dir("${TF_WORKING_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            set -eu
                            echo "=== Terraform initialization ==="
                            terraform init -input=false -reconfigure
                        '''
                    }
                }
            }
        }

        stage('Reconcile Terraform State') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                dir("${TF_WORKING_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            set -eu

                            if ! command -v aws >/dev/null 2>&1; then
                                if ! command -v curl >/dev/null 2>&1; then
                                    echo "AWS CLI and curl are required to reconcile existing Terraform resources" >&2
                                    exit 1
                                fi
                                if ! command -v unzip >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
                                    echo "AWS CLI is missing and unzip or Python is required to bootstrap it" >&2
                                    exit 1
                                fi

                                cli_tmp="$(mktemp -d)"
                                trap 'rm -rf "${cli_tmp}"' EXIT
                                curl --fail --silent --show-error --location --retry 3 \
                                    --output "${cli_tmp}/awscliv2.zip" \
                                    "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
                                if command -v unzip >/dev/null 2>&1; then
                                    unzip -oq "${cli_tmp}/awscliv2.zip" -d "${cli_tmp}"
                                elif command -v python3 >/dev/null 2>&1; then
                                    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
                                        "${cli_tmp}/awscliv2.zip" "${cli_tmp}"
                                else
                                    python -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' \
                                        "${cli_tmp}/awscliv2.zip" "${cli_tmp}"
                                fi
                                chmod +x "${cli_tmp}/aws/install"
                                "${cli_tmp}/aws/install" --install-dir "${WORKSPACE}/.tools/aws" \
                                    --bin-dir "${WORKSPACE}/.tools" --update
                            fi

                            export AWS_DEFAULT_REGION="${AWS_REGION}"
                            if ! terraform state list | grep -qx 'aws_security_group.web_sg'; then
                                security_group_id="$(aws ec2 describe-security-groups \
                                    --filters 'Name=group-name,Values=prod-web-sg' \
                                    --query 'SecurityGroups[0].GroupId' \
                                    --output text)"
                                if [ -n "${security_group_id}" ] && [ "${security_group_id}" != "None" ]; then
                                    echo "Importing existing project security group ${security_group_id} into Terraform state"
                                    terraform import -no-color aws_security_group.web_sg "${security_group_id}"
                                    terraform state list | grep -qx 'aws_security_group.web_sg'
                                fi
                            fi

                            if ! terraform state list | grep -qx 'aws_instance.web'; then
                                instance_id="$(aws ec2 describe-instances \
                                    --filters \
                                        'Name=tag:Name,Values=prod-web-server' \
                                        'Name=instance-state-name,Values=pending,running,stopping,stopped' \
                                    --query 'Reservations[0].Instances[0].InstanceId' \
                                    --output text)"
                                if [ -n "${instance_id}" ] && [ "${instance_id}" != "None" ]; then
                                    echo "Importing existing project instance ${instance_id} into Terraform state"
                                    terraform import -no-color aws_instance.web "${instance_id}"
                                    terraform state list | grep -qx 'aws_instance.web'
                                fi
                            fi
                        '''
                    }
                }
            }
        }

        stage('Terraform Destroy') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                dir("${TF_WORKING_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            set -eu
                            echo "=== Terraform destroy started ==="
                            terraform destroy -input=false -auto-approve -lock-timeout=5m \
                                -var="aws_region=${AWS_REGION}" \
                                -var="key_name=${AWS_KEY_NAME}"
                            echo "=== Terraform destroy completed ==="
                        '''
                    }
                }
            }
        }

        stage('Verify Destroy') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                dir("${TF_WORKING_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            set -eu
                            export AWS_DEFAULT_REGION="${AWS_REGION}"
                            remaining="$(terraform state list)"
                            if [ -n "${remaining}" ]; then
                                echo "Terraform state still contains managed resources after destroy:" >&2
                                printf '%s\n' "${remaining}" >&2
                                exit 1
                            fi
                            security_group_id="$(aws ec2 describe-security-groups \
                                --filters 'Name=group-name,Values=prod-web-sg' \
                                --query 'SecurityGroups[0].GroupId' \
                                --output text)"
                            if [ -n "${security_group_id}" ] && [ "${security_group_id}" != "None" ]; then
                                echo "Security group prod-web-sg still exists after destroy: ${security_group_id}" >&2
                                exit 1
                            fi
                            echo "=== Terraform destroy verification completed ==="
                        '''
                    }
                }
            }
        }

        stage('Terraform Plan') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                dir("${TF_WORKING_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh 'terraform validate'
                        sh '''
                            echo "=== Terraform plan ==="
                            terraform plan -input=false -lock-timeout=5m \
                                -var="aws_region=${AWS_REGION}" \
                                -var="key_name=${AWS_KEY_NAME}" \
                                -out=tfplan
                        '''
                    }
                }
            }
        }

        stage('Approval') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                input message: 'Deploy to PRODUCTION?', ok: 'Deploy'
            }
        }

        stage('Terraform Apply') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                dir("${TF_WORKING_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh '''
                            echo "=== Terraform apply started ==="
                            terraform apply -input=false -auto-approve -lock-timeout=5m tfplan
                            echo "=== Terraform apply completed ==="
                        '''
                    }
                }
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKERHUB_USERNAME',
                        passwordVariable: 'DOCKERHUB_PASSWORD'
                    )
                ]) {
                    sh '''
                        set -eu

                        if ! command -v docker >/dev/null 2>&1; then
                            echo "Required tool 'docker' is missing from the Jenkins agent" >&2
                            exit 1
                        fi

                        docker_namespace="${DOCKERHUB_NAMESPACE:-malikzohaib1482}"
                        case "${docker_namespace}" in
                            ''|*[!a-z0-9_-]*)
                                echo "Invalid Docker Hub namespace '${docker_namespace}'. Set DOCKERHUB_NAMESPACE to the Docker Hub username." >&2
                                exit 1
                                ;;
                        esac

                        image="${docker_namespace}/${DOCKER_REPOSITORY}:${BUILD_NUMBER}"
                        echo "${DOCKERHUB_PASSWORD}" | docker login docker.io --username "${DOCKERHUB_USERNAME}" --password-stdin
                        docker build --tag "${image}" "${APP_DIR}"
                        docker push "${image}"
                        docker tag "${image}" "${docker_namespace}/${DOCKER_REPOSITORY}:latest"
                        docker push "${docker_namespace}/${DOCKER_REPOSITORY}:latest"
                        docker logout
                    '''
                }
            }
        }

        stage('Set Deployment Image') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                script {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerhub-creds',
                            usernameVariable: 'DOCKERHUB_USERNAME',
                            passwordVariable: 'DOCKERHUB_PASSWORD'
                        )
                    ]) {
                        def dockerNamespace = params.DOCKERHUB_NAMESPACE?.trim()
                        if (!dockerNamespace) {
                            dockerNamespace = 'malikzohaib1482'
                        }
                        env.DOCKER_IMAGE = "${dockerNamespace}/${DOCKER_REPOSITORY}:${BUILD_NUMBER}"
                    }
                }
            }
        }

        stage('Deploy to Server') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                script {
                    def tfOutput = sh(
                        script: "cd ${TF_WORKING_DIR} && terraform output -raw instance_public_ip",
                        returnStdout: true
                    ).trim()

                    echo "Deploying to ${tfOutput}"

                    withCredentials([
                        sshUserPrivateKey(
                            credentialsId: 'prod-server-ssh',
                            keyFileVariable: 'SSH_KEY_FILE',
                            usernameVariable: 'SSH_USERNAME'
                        )
                    ]) {
                        sh """
                            set -eu
                            case '${tfOutput}' in
                                ''|*[!0-9.]*)
                                    echo "Terraform returned an invalid instance IP: ${tfOutput}" >&2
                                    exit 1
                                    ;;
                            esac
                            chmod 600 "\${SSH_KEY_FILE}"
                            ssh -n -i "\${SSH_KEY_FILE}" \
                                -o BatchMode=yes \
                                -o StrictHostKeyChecking=no \
                                -o ConnectTimeout=15 \
                                -o ConnectionAttempts=3 \
                                -o ServerAliveInterval=10 \
                                -o ServerAliveCountMax=3 \
                                "\${SSH_USERNAME}@${tfOutput}" '
                                    for attempt in \$(seq 1 12); do
                                        if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
                                            break
                                        fi
                                        if [ "\${attempt}" -eq 12 ]; then
                                            echo "Docker is not ready on the server" >&2
                                            exit 1
                                        fi
                                        sleep 5
                                    done
                                    docker pull ${env.DOCKER_IMAGE}
                                    docker stop web || true
                                    docker rm web || true
                                    docker run -d --name web -p 80:80 ${env.DOCKER_IMAGE}
                                '
                        """
                    }
                }
            }
        }

        stage('Smoke Test') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                script {
                    def ip = sh(
                        script: "cd ${TF_WORKING_DIR} && terraform output -raw instance_public_ip",
                        returnStdout: true
                    ).trim()
                    sh "sleep 10 && curl -f http://${ip} || exit 1"
                }
            }
        }
    }

    post {
        success {
            echo 'this good Pipeline succeeded!'
        }
        failure {
            echo 'no no this is error Pipeline failed!'
        }
        always {
            echo 'Workspace preserved so local Terraform state remains available for the next build.'
        }
    }
}