pipeline {
    agent any

    environment {
        TF_WORKING_DIR = 'terraform'
        APP_DIR        = 'app'
        DOCKER_IMAGE   = "yourdockerhub/nginx-demo:${BUILD_NUMBER}"
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

        stage('Terraform Init & Plan') {
            steps {
                dir("${TF_WORKING_DIR}") {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh 'terraform init'
                        sh 'terraform validate'
                        sh 'terraform plan -var="key_name=my-keypair" -out=tfplan'
                    }
                }
            }
        }

        stage('Approval') {
            when { branch 'main' }
            steps {
                input message: 'Deploy to PRODUCTION?', ok: 'Deploy'
            }
        }

        stage('Terraform Apply') {
            when { branch 'main' }
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
                script {
                    docker.withRegistry('https://registry.hub.docker.com', 'dockerhub-creds') {
                        def img = docker.build("${DOCKER_IMAGE}", "${APP_DIR}")
                        img.push()
                        img.push('latest')
                    }
                }
            }
        }

        stage('Deploy to Server') {
            when { branch 'main' }
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
            echo '✅ Pipeline succeeded!'
        }
        failure {
            echo '❌ Pipeline failed!'
        }
        always {
            cleanWs()
        }
    }
}