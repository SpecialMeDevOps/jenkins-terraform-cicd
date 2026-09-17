pipeline {
    agent any

    environment {
        TF_WORKING_DIR = 'terraform'
        TF_VERSION     = '1.16.3'
        TF_BIN_DIR     = "${WORKSPACE}/.tools"
        APP_DIR        = 'app'
        DOCKER_REPOSITORY = 'nginx-demo'
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
    }

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
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

        stage('Terraform Init & Plan') {
            steps {
                dir("${TF_WORKING_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh 'terraform init'
                        sh 'terraform validate'
                        sh '''
                            set -eu

                            if ! command -v aws >/dev/null 2>&1; then
                                echo "Required tool 'aws' is missing from the Jenkins agent" >&2
                                exit 1
                            fi

                            export AWS_DEFAULT_REGION="${AWS_REGION}"

                            security_group_id="$(aws ec2 describe-security-groups \
                                --filters "Name=group-name,Values=prod-web-sg" \
                                --query 'SecurityGroups[0].GroupId' \
                                --output text)"
                            if [ "${security_group_id}" != "None" ] && [ -n "${security_group_id}" ]; then
                                terraform import -no-color aws_security_group.web_sg "${security_group_id}"
                            fi

                            instance_id="$(aws ec2 describe-instances \
                                --filters \
                                    "Name=tag:Name,Values=prod-web-server" \
                                    "Name=instance-state-name,Values=pending,running,stopping,stopped" \
                                --query 'Reservations[0].Instances[0].InstanceId' \
                                --output text)"
                            if [ "${instance_id}" != "None" ] && [ -n "${instance_id}" ]; then
                                terraform import -no-color aws_instance.web "${instance_id}"
                            fi
                        '''
                        sh 'terraform plan -var="aws_region=${AWS_REGION}" -var="key_name=${AWS_KEY_NAME}" -out=tfplan'
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
                        sh 'terraform apply -auto-approve tfplan'
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

                        image="${DOCKERHUB_USERNAME}/${DOCKER_REPOSITORY}:${BUILD_NUMBER}"
                        echo "${DOCKERHUB_PASSWORD}" | docker login --username "${DOCKERHUB_USERNAME}" --password-stdin
                        docker build --tag "${image}" "${APP_DIR}"
                        docker push "${image}"
                        docker tag "${image}" "${DOCKERHUB_USERNAME}/${DOCKER_REPOSITORY}:latest"
                        docker push "${DOCKERHUB_USERNAME}/${DOCKER_REPOSITORY}:latest"
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
                        env.DOCKER_IMAGE = "${DOCKERHUB_USERNAME}/${DOCKER_REPOSITORY}:${BUILD_NUMBER}"
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

                    sshagent(credentials: ['prod-server-ssh']) {
                        sh """
                            ssh -o StrictHostKeyChecking=no ubuntu@${tfOutput} '
                                docker pull ${DOCKER_IMAGE}
                                docker stop web || true
                                docker rm web || true
                                docker run -d --name web -p 80:80 ${DOCKER_IMAGE}
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
            cleanWs()
        }
    }
}