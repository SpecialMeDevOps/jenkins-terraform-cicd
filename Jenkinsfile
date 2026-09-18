pipeline {
    agent any
// heloo 
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

                            aws_cli="${WORKSPACE}/.tools/aws/v2/current/bin/aws"
                            if command -v aws >/dev/null 2>&1; then
                                aws_cli="$(command -v aws)"
                            elif [ ! -x "${aws_cli}" ]; then
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

                            if [ ! -x "${aws_cli}" ]; then
                                echo "AWS CLI installation did not provide an executable at ${aws_cli}" >&2
                                exit 1
                            fi
                            chmod +x "${aws_cli}"
                            "${aws_cli}" --version
                            export AWS_DEFAULT_REGION="${AWS_REGION}"
                            state_resources="$(terraform state list 2>/dev/null || true)"
                            if ! printf '%s\n' "${state_resources}" | grep -qx 'aws_security_group.web_sg'; then
                                security_group_id="$("${aws_cli}" ec2 describe-security-groups \
                                    --filters 'Name=group-name,Values=prod-web-sg' \
                                    --query 'SecurityGroups[0].GroupId' \
                                    --output text)"
                                if [ -n "${security_group_id}" ] && [ "${security_group_id}" != "None" ]; then
                                    echo "Importing existing project security group ${security_group_id} into Terraform state"
                                    terraform import -no-color aws_security_group.web_sg "${security_group_id}"
                                    terraform state list | grep -qx 'aws_security_group.web_sg'
                                fi
                            fi

                            state_resources="$(terraform state list 2>/dev/null || true)"
                            if ! printf '%s\n' "${state_resources}" | grep -qx 'aws_iam_role.web_ssm'; then
                                if "${aws_cli}" iam get-role --role-name "prod-web-ssm-role" >/dev/null 2>&1; then
                                    echo "Importing existing project SSM role"
                                    terraform import -no-color aws_iam_role.web_ssm "prod-web-ssm-role"
                                fi
                            fi

                            state_resources="$(terraform state list 2>/dev/null || true)"
                            if ! printf '%s\n' "${state_resources}" | grep -qx 'aws_iam_instance_profile.web'; then
                                if "${aws_cli}" iam get-instance-profile --instance-profile-name "prod-web-instance-profile" >/dev/null 2>&1; then
                                    echo "Importing existing project SSM instance profile"
                                    terraform import -no-color aws_iam_instance_profile.web "prod-web-instance-profile"
                                fi
                            fi

                            state_resources="$(terraform state list 2>/dev/null || true)"
                            if ! printf '%s\n' "${state_resources}" | grep -qx 'aws_iam_role_policy_attachment.web_ssm'; then
                                role_policy_id="prod-web-ssm-role/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
                                if "${aws_cli}" iam list-attached-role-policies --role-name "prod-web-ssm-role" \
                                    --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore'].PolicyArn" \
                                    --output text | grep -qx 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore'; then
                                    echo "Importing existing SSM managed policy attachment"
                                    terraform import -no-color aws_iam_role_policy_attachment.web_ssm "${role_policy_id}"
                                fi
                            fi

                            state_resources="$(terraform state list 2>/dev/null || true)"
                            if ! printf '%s\n' "${state_resources}" | grep -qx 'aws_instance.web'; then
                                instance_id="$("${aws_cli}" ec2 describe-instances \
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
                            state_resources="$(terraform state list 2>/dev/null || true)"
                            if [ -z "${state_resources}" ]; then
                                echo "=== No Terraform-managed resources found; destroy skipped ==="
                            else
                                echo "=== Terraform destroy started ==="
                                terraform destroy -input=false -auto-approve -lock-timeout=5m \
                                    -var="aws_region=${AWS_REGION}"
                            fi
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
                            aws_cli="${WORKSPACE}/.tools/aws/v2/current/bin/aws"
                            if command -v aws >/dev/null 2>&1; then
                                aws_cli="$(command -v aws)"
                            elif [ ! -x "${aws_cli}" ]; then
                                echo "AWS CLI executable is unavailable for destroy verification" >&2
                                exit 1
                            fi
                            export AWS_DEFAULT_REGION="${AWS_REGION}"
                            remaining="$(terraform state list 2>/dev/null || true)"
                            if [ -n "${remaining}" ]; then
                                echo "Terraform state still contains managed resources after destroy:" >&2
                                printf '%s\n' "${remaining}" >&2
                                exit 1
                            fi
                            security_group_id="$("${aws_cli}" ec2 describe-security-groups \
                                --filters 'Name=group-name,Values=prod-web-sg' \
                                --query 'SecurityGroups[0].GroupId' \
                                --output text)"
                            if [ -n "${security_group_id}" ] && [ "${security_group_id}" != "None" ]; then
                                echo "Security group prod-web-sg still exists after destroy: ${security_group_id}" >&2
                                exit 1
                            fi
                            if "${aws_cli}" iam get-role --role-name "prod-web-ssm-role" >/dev/null 2>&1; then
                                echo "SSM IAM role prod-web-ssm-role still exists after destroy" >&2
                                exit 1
                            fi
                            if "${aws_cli}" iam get-instance-profile --instance-profile-name "prod-web-instance-profile" >/dev/null 2>&1; then
                                echo "SSM instance profile prod-web-instance-profile still exists after destroy" >&2
                                exit 1
                            fi
                            instance_id="$("${aws_cli}" ec2 describe-instances \
                                --filters \
                                    'Name=tag:Name,Values=prod-web-server' \
                                    'Name=instance-state-name,Values=pending,running,stopping,stopped' \
                                --query 'Reservations[0].Instances[0].InstanceId' \
                                --output text)"
                            if [ -n "${instance_id}" ] && [ "${instance_id}" != "None" ]; then
                                echo "Project instance ${instance_id} still exists after destroy" >&2
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

        stage('Get EC2 Instance ID') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                script {
                    env.EC2_INSTANCE_ID = sh(
                        script: "cd ${TF_WORKING_DIR} && terraform output -raw instance_id",
                        returnStdout: true
                    ).trim()
                    if (!(env.EC2_INSTANCE_ID ==~ /^i-[0-9a-f]+$/)) {
                        error("Terraform returned an invalid EC2 instance ID: ${env.EC2_INSTANCE_ID}")
                    }
                    echo "Target EC2 instance: ${env.EC2_INSTANCE_ID}"
                }
            }
        }

        stage('Wait for SSM') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    sh '''
                        set -eu
                        aws_cli="${WORKSPACE}/.tools/aws/v2/current/bin/aws"
                        if command -v aws >/dev/null 2>&1; then aws_cli="$(command -v aws)"; fi
                        test -x "${aws_cli}"
                        export AWS_DEFAULT_REGION="${AWS_REGION}"
                        echo "=== Waiting for EC2 and SSM readiness ==="
                        for attempt in $(seq 1 18); do
                            instance_state="$("${aws_cli}" ec2 describe-instances --instance-ids "${EC2_INSTANCE_ID}" --query 'Reservations[0].Instances[0].State.Name' --output text)"
                            ssm_status="$("${aws_cli}" ssm describe-instance-information --filters "Key=InstanceIds,Values=${EC2_INSTANCE_ID}" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)"
                            if [ "${instance_state}" = "running" ] && [ "${ssm_status}" = "Online" ]; then
                                echo "EC2 ${EC2_INSTANCE_ID} is running and online in SSM"
                                exit 0
                            fi
                            echo "Waiting for EC2/SSM (attempt ${attempt}/18; state=${instance_state}; ssm=${ssm_status})"
                            sleep 10
                        done
                        echo "EC2 instance did not register with SSM after 3 minutes" >&2
                        exit 1
                    '''
                }
            }
        }

        stage('Deploy with SSM') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                script {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        env.SSM_COMMAND_ID = sh(
                            script: '''
                                set -eu
                                aws_cli="${WORKSPACE}/.tools/aws/v2/current/bin/aws"
                                if command -v aws >/dev/null 2>&1; then aws_cli="$(command -v aws)"; fi
                                test -x "${aws_cli}"
                                if command -v python3 >/dev/null 2>&1; then python_bin=python3
                                elif command -v python >/dev/null 2>&1; then python_bin=python
                                else echo "Python is required to create the SSM parameters file" >&2; exit 1
                                fi
                                export AWS_DEFAULT_REGION="${AWS_REGION}"
                                echo "=== Deploying Docker application through SSM ===" >&2
                                params_file="/tmp/ssm-params.json"
                                "${python_bin}" - "${params_file}" "${DOCKER_IMAGE}" <<'PY'
import json
import sys
path, image = sys.argv[1], sys.argv[2]
script = """set -eu
command -v docker
systemctl enable --now docker
docker pull IMAGE
docker stop web 2>/dev/null || true
docker rm web 2>/dev/null || true
docker run -d --name web -p 80:80 IMAGE
docker ps --filter name=^/web$ --filter status=running --format '{{.Names}}' | grep -qx web
""".replace("IMAGE", image)
with open(path, "w", encoding="utf-8") as handle:
    json.dump({"commands": [script]}, handle)
PY
                                command_id="$("${aws_cli}" ssm send-command \
                                    --document-name "AWS-RunShellScript" \
                                    --instance-ids "${EC2_INSTANCE_ID}" \
                                    --parameters "file://${params_file}" \
                                    --query 'Command.CommandId' --output text)"
                                test -n "${command_id}"
                                test "${command_id}" != "None"
                                printf '%s\n' "${command_id}"
                            ''',
                            returnStdout: true
                        ).trim()
                        if (!(env.SSM_COMMAND_ID ==~ /^[a-f0-9-]+$/)) {
                            error("AWS SSM returned an invalid command ID: ${env.SSM_COMMAND_ID}")
                        }
                        echo "SSM command submitted: ${env.SSM_COMMAND_ID}"
                    }
                }
            }
        }

        stage('Verify SSM deployment') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'origin/main' }
                }
            }
            steps {
                script {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh """
                            set -eu
                            aws_cli="${WORKSPACE}/.tools/aws/v2/current/bin/aws"
                            if command -v aws >/dev/null 2>&1; then aws_cli="\$(command -v aws)"; fi
                            test -x "\${aws_cli}"
                            export AWS_DEFAULT_REGION="${AWS_REGION}"
                            test -n "${SSM_COMMAND_ID}"
                            for attempt in \$(seq 1 30); do
                                status="\$("\${aws_cli}" ssm get-command-invocation \
                                    --command-id "${SSM_COMMAND_ID}" \
                                    --instance-id "${EC2_INSTANCE_ID}" \
                                    --query 'Status' --output text 2>/dev/null || true)"
                                case "\${status}" in
                                    Success|Failed|Cancelled|TimedOut|Cancelling)
                                        break
                                        ;;
                                    *)
                                        echo "Waiting for SSM command ${SSM_COMMAND_ID} (attempt \${attempt}/30; status=\${status})"
                                        sleep 10
                                        ;;
                                esac
                            done
                            stdout="\$("\${aws_cli}" ssm get-command-invocation \
                                --command-id "${SSM_COMMAND_ID}" \
                                --instance-id "${EC2_INSTANCE_ID}" \
                                --query 'StandardOutputContent' --output text)"
                            stderr="\$("\${aws_cli}" ssm get-command-invocation \
                                --command-id "${SSM_COMMAND_ID}" \
                                --instance-id "${EC2_INSTANCE_ID}" \
                                --query 'StandardErrorContent' --output text)"
                            echo "=== SSM stdout ==="
                            printf '%s\n' "\${stdout}"
                            echo "=== SSM stderr ==="
                            printf '%s\n' "\${stderr}" >&2
                            case "\${status}" in
                                Success)
                                    echo "=== SSM Docker deployment completed ==="
                                    ;;
                                *)
                                    echo "SSM Docker deployment failed with status \${status}" >&2
                                    exit 1
                                    ;;
                            esac
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
                    sh """
                        set -eu
                        for attempt in \$(seq 1 12); do
                            if curl --fail --silent --show-error --connect-timeout 5 http://${ip}; then
                                exit 0
                            fi
                            echo "Waiting for application HTTP endpoint (attempt \${attempt}/12)"
                            sleep 5
                        done
                        echo "Application smoke test failed" >&2
                        exit 1
                    """
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