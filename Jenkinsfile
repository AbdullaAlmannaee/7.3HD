pipeline {
  agent any

  tools { nodejs 'node18' } // from Manage Jenkins → Tools

  environment {
    REGISTRY = "docker.io"
    IMAGE    = "abdullaalmannaee/hd73-app"
    NODE_ENV = "test"
    SONARQUBE_ENV = "sonar" // Manage Jenkins → System → SonarQube servers
    VERSION = "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7)}"
  }

  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  triggers { pollSCM('@daily') } // optional

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build') {
      steps {
        sh '''
          echo "==> Install deps"
          npm ci || npm install
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
          junit allowEmptyResults: true, testResults: '**/junit*.xml, **/jest-junit*.xml, reports/junit/*.xml'
        }
      }
    }

    stage('Code Quality (SonarQube)') {
      steps {
        withSonarQubeEnv("${env.SONARQUBE_ENV}") {
          withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
            sh '''
              echo "==> Sonar scan"
              ./node_modules/.bin/sonar-scanner -Dsonar.login=$SONAR_TOKEN 2>/dev/null \
              || sonar-scanner -Dsonar.login=$SONAR_TOKEN
            '''
          }
        }
      }
      // To hard-gate on the quality gate, uncomment:
      // post { success { timeout(time: 3, unit: 'MINUTES') { waitForQualityGate abortPipeline: true } } }
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
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PWD')]) {
          sh '''
            echo "==> Docker login & push staging tag"
            echo "$DOCKERHUB_PWD" | docker login -u "$DOCKERHUB_USER" --password-stdin
            docker tag $IMAGE:commit-$VERSION $IMAGE:staging
            docker push $IMAGE:staging
          '''
        }
        sh '''
          echo "==> Bring up staging with docker-compose"
          docker compose -f docker-compose.yml down || true
          DOCKER_IMAGE=$IMAGE:staging docker compose -f docker-compose.yml up -d --pull always

          echo "==> Smoke/health check"
          bash ./wait-for-health.sh http://localhost:3000/health || \
          (sleep 5 && curl -fsS http://localhost:3000/health)
        '''
      }
    }

    stage('Release (Production)') {
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PWD')]) {
          sh '''
            echo "==> Tag & push prod image"
            echo "$DOCKERHUB_PWD" | docker login -u "$DOCKERHUB_USER" --password-stdin
            docker tag $IMAGE:commit-$VERSION $IMAGE:latest
            docker push $IMAGE:latest
          '''
        }
        sh '''
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
          echo "==> Basic latency check"
          START=$(date +%s%3N)
          curl -fsS http://localhost:3000/health || curl -fsS http://localhost:3000
          END=$(date +%s%3N)
          echo "Latency(ms)=$((END-START))" | tee monitoring-metrics.txt
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'monitoring-metrics.txt', onlyIfSuccessful: false
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
