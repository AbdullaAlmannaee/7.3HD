pipeline {
  agent any

  environment {
    NODEJS = 'Node 18'              // name you added in Jenkins > Tools
    IMAGE_NAME = 'sit223-demo'
    IMAGE_TAG  = "build-${env.BUILD_NUMBER}"
    SONAR_ENV  = 'sonar'            // Jenkins Sonar server config name
  }

  options {
    ansiColor('xterm')
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  triggers { pollSCM('@daily') }    // or a webhook

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
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
        sh """
          set -e
          npm test > test.out 2>&1 || (cat test.out; exit 1)
        """
      }
      post {
        always {
          // If you output JUnit XML, publish here:
          // junit 'reports/junit/*.xml'
        }
      }
    }

    stage('Code Quality (Sonar)') {
      environment { SONAR_TOKEN = credentials('SONAR_TOKEN') }
      steps {
        withSonarQubeEnv("${env.SONAR_ENV}") {
          sh """
            if ! command -v sonar-scanner >/dev/null 2>&1; then
              curl -sSLo ss.zip \
                https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-5.0.1.3006-macosx.zip || true
              unzip -qo ss.zip -d $WORKSPACE/ss
              export PATH="$WORKSPACE/ss/*/bin:$PATH"
            fi
            export SONAR_SCANNER_OPTS="-Dsonar.login=$SONAR_TOKEN"
            sonar-scanner
          """
        }
      }
    }

    stage('Security (deps + image)') {
      steps {
        sh """
          # Node dependency scan (quick baseline)
          npm audit --audit-level=moderate || true

          # Build image for Trivy scan
          docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
          # Trivy (one-shot via Docker) – no plugin required
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL \
            ${IMAGE_NAME}:${IMAGE_TAG} || true
        """
      }
    }

    stage('Deploy (staging)') {
      steps {
        sh """
          export IMAGE_NAME=${IMAGE_NAME}
          export IMAGE_TAG=${IMAGE_TAG}
          docker compose down || true
          docker compose up -d --build
          # quick health probe
          for i in {1..10}; do
            curl -fsS http://localhost:8088 && break || sleep 3
          done
        """
      }
    }

    stage('Release (tag)') {
      when { expression { return env.GIT_URL } }
      environment { GITHUB_TOKEN = credentials('GITHUB_TOKEN') }
      steps {
        sh """
          git config user.email "ci@jenkins.local"
          git config user.name "Jenkins CI"
          git tag -a "v${BUILD_NUMBER}" -m "CI release ${BUILD_NUMBER}" || true
          # Push only if we have a token/permission
          git push origin "v${BUILD_NUMBER}" || true
        """
      }
    }

    stage('Monitoring (basic health & logs)') {
      steps {
        sh """
          set -e
          echo "Checking / every 10s for 1 minute..."
          for i in {1..6}; do
            code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8088)
            echo "probe #$i: HTTP $code"
            [ "$code" = "200" ] || echo "Non-200 detected (will recheck)"
            sleep 10
          done
          echo "Recent logs:"
          docker logs --tail=50 $(docker ps --filter name=app -q) || true
        """
      }
    }
  }

  post {
    success { echo "Pipeline succeeded 🎉" }
    failure { echo "Pipeline failed. Check stage logs." }
    always  { cleanWs() }
  }
}
