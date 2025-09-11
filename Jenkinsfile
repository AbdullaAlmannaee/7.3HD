pipeline {
  agent any

  environment {
    NODEJS     = 'Node 18'
    IMAGE_NAME = 'sit223-demo'
    IMAGE_TAG  = "build-${env.BUILD_NUMBER}"
  }

  options {
    ansiColor('xterm')
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build') {
      tools { nodejs "${env.NODEJS}" }
      steps {
        sh 'node -v && npm -v'
        sh 'npm ci --no-audit --no-fund'
        sh 'npm run build || echo "no build step defined"'
        archiveArtifacts artifacts: '**/*', fingerprint: true
      }
    }

    stage('Test') {
      steps {
        sh 'npm test > test.out 2>&1 || (cat test.out; exit 1)'
      }
    }

    stage('Docker Build') {
      steps {
        sh "docker build -t ${env.IMAGE_NAME}:${env.IMAGE_TAG} ."
      }
    }

    stage('Deploy (staging)') {
      steps {
        withEnv(["IMAGE_NAME=${env.IMAGE_NAME}", "IMAGE_TAG=${env.IMAGE_TAG}"]) {
          sh 'docker compose down || true'
          sh 'docker compose up -d --build'
          // quick health probe
          sh 'for i in 1 2 3 4 5; do curl -fsS http://localhost:8088 && break || sleep 3; done'
        }
      }
    }

    stage('Monitoring') {
      steps {
        sh 'echo "HTTP: $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8088)" || true'
        sh 'docker ps --filter name=app || true'
      }
    }
  }

  post {
    success { echo '✅ Pipeline OK' }
    failure { echo '❌ Pipeline failed — see console' }
    always  { cleanWs() }
  }
}
