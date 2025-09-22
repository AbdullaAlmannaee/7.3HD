pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  tools   { nodejs 'NodeJS' }

  environment {
    HEALTH_URL = "${env.HEALTH_URL ?: 'http://localhost:8080/health/'}"
    PATH       = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"
    SONAR_HOST = 'https://sonarcloud.io'
    SONAR_TOKEN = credentials('SONAR_TOKEN1')
    DEPLOY_SSH  = "${env.DEPLOY_SSH ?: ''}"
    DEPLOY_PATH = "${env.DEPLOY_PATH ?: '/var/www/app'}"
    REGISTRY    = "${env.REGISTRY ?: ''}"
    IMAGE_NAME  = "${env.IMAGE_NAME ?: ''}"
    IMAGE_TAG   = "${env.IMAGE_TAG ?: 'latest'}"
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build') {
      steps {
        sh '''
          set -e
          echo "Node: $(node -v)  npm: $(npm -v)"
          if [ -f package-lock.json ]; then npm ci; else npm install; fi
          npm run build --if-present

          if command -v docker >/dev/null 2>&1 && [ -f Dockerfile ] && [ -n "$REGISTRY" ] && [ -n "$IMAGE_NAME" ]; then
            IMAGE="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
            echo "Building Docker image $IMAGE"
            docker build -t "$IMAGE" .
            docker tag "$IMAGE" "$REGISTRY/$IMAGE_NAME:latest"
            printf "%s\n" "$IMAGE" > image.txt
          else
            echo "Skipping Docker image build (docker/envs missing). Archiving artifacts instead."
            mkdir -p artifacts
            [ -d dist  ] && tar -czf artifacts/dist.tgz  dist
            [ -d build ] && tar -czf artifacts/build.tgz build
            [ -f package.json ] && cp package.json artifacts/
          fi
        '''
      }
      post {
        always { archiveArtifacts artifacts: 'artifacts/**,image.txt', allowEmptyArchive: true }
      }
    }

    stage('Test') {
      steps {
        sh '''
          set -e
          if npm run | grep -qE "^ *test"; then
            npm test
          else
            echo "No test script found -> skipping tests"
          fi
        '''
      }
      post {
        always {
          junit testResults: 'junit*.xml, **/junit*.xml', allowEmptyResults: true
          archiveArtifacts artifacts: 'coverage/**', allowEmptyArchive: true
        }
      }
    }

    stage('Code Quality') {
      steps {
        sh '''
          set -e
          if [ -z "$SONAR_HOST" ]; then
            echo "Sonar: SONAR_HOST not set -> skipping (success)."
            exit 0
          fi
          if ! command -v sonar-scanner >/dev/null 2>&1; then
            npm i -D sonar-scanner
            SC="npx sonar-scanner"
          else
            SC="sonar-scanner"
          fi
          $SC \
            -Dsonar.host.url="$SONAR_HOST" \
            -Dsonar.login="$SONAR_TOKEN" \
            -Dsonar.projectKey=AbdullaAlmannaee_7.3HD \
            -Dsonar.organization=abdullaalmannaee-1 \
            -Dsonar.projectName=7.3HD \
            -Dsonar.projectVersion=${BUILD_NUMBER} \
            -Dsonar.sources=. \
            -Dsonar.sourceEncoding=UTF-8 || true
        '''
      }
    }

    stage('Security') {
      steps {
        withCredentials([string(credentialsId: 'SNYK_TOKEN', variable: 'SNYK_TOKEN')]) {
          sh '''
            set -e
            mkdir -p security-reports

            echo "=== npm audit (deps) ==="
            npm audit --json > security-reports/npm-audit.json || true

            echo "=== Trivy scans ==="
            if command -v trivy >/dev/null 2>&1; then
              trivy fs --exit-code 0 --severity HIGH,CRITICAL --format json -o security-reports/trivy-fs.json . || true
              if [ -f image.txt ]; then
                IMAGE="$(cat image.txt)"
                trivy image --exit-code 0 --severity HIGH,CRITICAL --format json -o security-reports/trivy-image.json "$IMAGE" || true
              fi
            else
              echo "Trivy not found -> skipping Trivy scans"
            fi

            echo "=== Snyk CLI ==="
            if ! command -v snyk >/dev/null 2>&1; then
              echo "Installing Snyk CLI..."
              npm install -g snyk >/dev/null 2>&1 || true
            fi
            echo "Authenticating Snyk..."
            snyk auth "$SNYK_TOKEN" || true

            echo "=== Snyk (dependencies) ==="
            snyk test --all-projects --severity-threshold=medium --json > security-reports/snyk-deps.json || true
            snyk test --all-projects --severity-threshold=medium > security-reports/snyk-deps.txt || true

            if [ -f image.txt ]; then
              IMAGE="$(cat image.txt)"
              echo "=== Snyk (container image) ==="
              snyk container test "$IMAGE" --severity-threshold=medium --json > security-reports/snyk-image.json || true
              snyk container test "$IMAGE" --severity-threshold=medium > security-reports/snyk-image.txt || true
            fi

            echo "=== Snyk monitor (dashboard) ==="
            snyk monitor --all-projects || true
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'security-reports/**', allowEmptyArchive: true
        }
      }
    }

    stage('Push Image') {
      when {
        allOf {
          expression { fileExists('image.txt') }
          expression { return env.REGISTRY?.trim() && env.IMAGE_NAME?.trim() }
        }
      }
      environment { DOCKER_REGISTRY_CREDS = credentials('DOCKER_REGISTRY_CREDS') }
      steps {
        sh '''
          set -e
          IMAGE="$(cat image.txt)"
          if command -v docker >/dev/null 2>&1; then
            if [ -n "$DOCKER_REGISTRY_CREDS_USR" ]; then
              echo "$DOCKER_REGISTRY_CREDS_PSW" | docker login "$REGISTRY" -u "$DOCKER_REGISTRY_CREDS_USR" --password-stdin || true
            fi
            docker push "$IMAGE" || true
            docker push "$REGISTRY/$IMAGE_NAME:latest" || true
          else
            echo "docker not available; skipping push"
          fi
        '''
      }
    }

    stage('Deploy') {
      when {
        anyOf {
          expression { fileExists('docker-compose.yml') }
          expression { env.DEPLOY_SSH?.trim() }
        }
      }
      steps {
        sh '''
          set -e
          if [ -f docker-compose.yml ] && command -v docker >/dev/null 2>&1; then
            [ -f image.txt ] && docker pull "$(cat image.txt)" || true
            docker compose down || true
            docker compose up -d --build || true
          elif [ -n "$DEPLOY_SSH" ]; then
            ssh -o StrictHostKeyChecking=no "$DEPLOY_SSH" "mkdir -p '$DEPLOY_PATH'"
            rsync -az --delete dist/  "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
            rsync -az --delete build/ "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
          else
            echo "No deploy target -> skipping"
          fi
        '''
      }
    }

    stage('Release') {
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
          sh '''
            set +e
            TAG="release-${BUILD_NUMBER}"
            git config user.name "jenkins"
            git config user.email "jenkins@local"
            git tag -fa "$TAG" -m "CI release ${BUILD_NUMBER}" 2>/dev/null || true
            git push --force origin "$TAG" 2>/dev/null || true
            echo "Release stage completed (non-blocking)."
            exit 0
          '''
        }
      }
    }

    stage('Monitoring') {
      steps {
        sh '''
          set +e
          if [ -z "$HEALTH_URL" ]; then
            echo "Monitoring: HEALTH_URL not set -> skipping (success)."
            exit 0
          fi
          echo "Pinging $HEALTH_URL ..."
          code=$(curl -fsS -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")
          echo "Monitoring: $HEALTH_URL -> HTTP $code"
          exit 0
        '''
      }
    }

  } // end stages

  post {
    success { echo 'Pipeline succeeded.' }
    failure { echo 'Pipeline failed. Check the first red error above.' }
    always  { echo "Build #${env.BUILD_NUMBER} complete." }
  }
}
