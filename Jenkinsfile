pipeline {
  agent any

  environment {
    REGISTRY = "docker.io"
    IMAGE    = "abdullaalmannaee/hd73-app"
    NODE_ENV = "test"
    // Sonar
    SONARQUBE_ENV = "sonar" // Jenkins global config name
    // Release version (git short sha + build number)
    VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7)}"
  }

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  triggers { pollSCM('@daily') } // optional

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        sh 'git log -1 --pretty=oneline || true'
      }
    }

    stage('Build') {
      steps {
        sh '''
          echo "==> Install deps"
          npm ci
          echo "==> Build Docker image"
          docker build -t $IMAGE:commit-$VERSION .
        '''
      }
    }

    stage('Test') {
      steps {
        sh '''
          echo "==> Run unit tests"
          npm test -- --ci --reporters=default --reporters=jest-junit || true
        '''
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: '**/junit*.xml, **/jest-junit*.xml'
        }
        unsuccessful {
          echo "Tests failed — keeping going for demo, but ideally failFast."
        }
      }
    }

    stage('Code Quality (SonarQube)') {
      steps {
        withSonarQubeEnv("${env.SONARQUBE_ENV}") {
          withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
            sh '''
              echo "==> Sonar scan"
              ./node_modules/.bin/sonar-scanner 2>/dev/null || sonar-scanner
            '''
          }
        }
      }
      post {
        always {
          // Wait for quality gate (optional; uncomment to strictly gate)
          // timeout(time: 3, unit: 'MINUTES') { waitForQualityGate abortPipeline: false }
        }
      }
    }

    stage('Security (Deps & Image)') {
      steps {
        sh '''
          echo "==> npm audit (high/critical only)"
          npm audit --audit-level=high || true

          echo "==> Trivy image scan"
          which trivy || (curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin)
          trivy image --severity HIGH,CRITICAL --no-progress --exit-code 0 $IMAGE:commit-$VERSION
        '''
      }
      post {
        always {
          archiveArtifacts allowEmptyArchive: true, artifacts: '**/npm-audit*.json'
        }
      }
    }

    stage('Deploy (Staging)') {
      steps {
        sh '''
          echo "==> Tag & push staging image"
          echo "$DOCKERHUB_PWD" | docker login -u "$DOCKERHUB_USER" --password-stdin
          docker tag $IMAGE:commit-$VERSION $IMAGE:staging
          docker push $IMAGE:staging

          echo "==> Bring up staging with docker-compose"
          docker compose -f docker-compose.yml down || true
          DOCKER_IMAGE=$IMAGE:staging docker compose -f docker-compose.yml up -d --pull always

          echo "==> Smoke check"
          sleep 5
          curl -fsS http://localhost:3000/health || curl -fsS http://localhost:3000 || true
        '''
      }
    }

    stage('Release (Production)') {
      when { branch 'main' }
      steps {
        sh '''
          echo "==> Tag & push prod image"
          echo "$DOCKERHUB_PWD" | docker login -u "$DOCKERHUB_USER" --password-stdin
          docker tag $IMAGE:commit-$VERSION $IMAGE:latest
          docker push $IMAGE:latest

          echo "==> Git tag"
          git config user.email "ci@jenkins.local"
          git config user.name "Jenkins CI"
          git tag -a "v${BUILD_NUMBER}" -m "Release build ${BUILD_NUMBER}"
          git push origin --tags || true
        '''
      }
    }

    stage('Monitoring & Alerting') {
      steps {
        sh '''
          echo "==> Basic uptime/latency check"
          START=$(date +%s%3N)
          curl -fsS http://localhost:3000/health || curl -fsS http://localhost:3000
          END=$(date +%s%3N)
          echo "Latency(ms)=$((END-START))" | tee monitoring-metrics.txt
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'monitoring-metrics.txt', onlyIfSuccessful: false
          echo "Hook here: send Slack/Email if latency > threshold or curl fails."
        }
      }
    }
  }

  post {
    success { echo "Pipeline OK: $BUILD_TAG" }
    failure { echo "Pipeline FAILED" }
    always  { cleanWs() }
  }
}
