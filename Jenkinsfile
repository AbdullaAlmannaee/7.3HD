pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  tools   { nodejs 'NodeJS' }

  environment {
    REGISTRY    = "${env.REGISTRY ?: ''}"                 // e.g. docker.io/abdulla (no trailing slash)
    IMAGE_NAME  = "${env.IMAGE_NAME ?: 'my-app'}"         // repo/name only
    IMAGE_TAG   = "${env.IMAGE_TAG ?: "build-${env.BUILD_NUMBER}"}"
    SONAR_HOST  = "${env.SONAR_HOST ?: ''}"
    SONAR_TOKEN = credentials('SONAR_TOKEN1')
    DEPLOY_SSH  = "${env.DEPLOY_SSH ?: ''}"               // e.g. ubuntu@host
    DEPLOY_PATH = "${env.DEPLOY_PATH ?: '/var/www/app'}"
    HEALTH_URL  = "${env.HEALTH_URL ?: ''}"
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
            # also tag 'latest' for convenience (pushed later)
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
          if [ ! -f sonar-project.properties ] || [ -z "$SONAR_HOST" ]; then
            echo "Sonar not configured -> skipping"
            exit 0
          fi

          echo "Running SonarQube scan against $SONAR_HOST ..."
          if ! command -v sonar-scanner >/dev/null 2>&1; then
            npm i -D sonar-scanner
            npx sonar-scanner -Dsonar.host.url="$SONAR_HOST" -Dsonar.login="$SONAR_TOKEN"
          else
            sonar-scanner -Dsonar.host.url="$SONAR_HOST" -Dsonar.login="$SONAR_TOKEN"
          fi

          # Optional lightweight wait (no plugin): try 3x to fetch Quality Gate status via API if SONAR_PROJECT_KEY exists
          if grep -q '^sonar.projectKey=' sonar-project.properties; then
            KEY="$(grep '^sonar.projectKey=' sonar-project.properties | cut -d= -f2-)"
            for i in 1 2 3; do
              sleep 5
              STATUS=$(curl -sf -u "$SONAR_TOKEN:" "$SONAR_HOST/api/qualitygates/project_status?projectKey=$KEY" | sed -n 's/.*"status":"\\([^"]*\\)".*/\\1/p' || true)
              echo "Quality Gate status: ${STATUS:-unknown}"
              [ "$STATUS" = "OK" ] && exit 0
            done
            echo "Quality Gate not OK (or unknown) after retries -> failing"
            exit 1
          else
            echo "No sonar.projectKey -> cannot check gate; continuing"
          fi
        '''
      }
    }

    stage('Security') {
      steps {
        sh '''
          set -e
          mkdir -p security-reports

          # 1) npm audit (JSON) — fail on high+
          if command -v npm >/dev/null 2>&1; then
            echo "Running npm audit --json ..."
            npm audit --json > security-reports/npm-audit.json || true
            # Decide fail policy on highs/criticals:
            HIGH_COUNT=$(jq '[.vulnerabilities | to_entries[] | select(.value.severity=="high" or .value.severity=="critical") ] | length' security-reports/npm-audit.json 2>/dev/null || echo 0)
            echo "High/Critical findings (npm): ${HIGH_COUNT}"
          fi

          # 2) Trivy FS + Image (if installed and image exists)
          if command -v trivy >/dev/null 2>&1; then
            echo "Running trivy fs ..."
            trivy fs --exit-code 0 --severity HIGH,CRITICAL --format json -o security-reports/trivy-fs.json .
            if [ -f image.txt ]; then
              IMAGE="$(cat image.txt)"
              echo "Running trivy image on $IMAGE ..."
              trivy image --exit-code 0 --severity HIGH,CRITICAL --format json -o security-reports/trivy-image.json "$IMAGE"
            fi
          else
            echo "Trivy not found -> skipping Trivy scans"
          fi

          # Fail policy: if either npm high/critical > 0 OR trivy finds high/critical, fail
          FAIL=0
          if [ -f security-reports/npm-audit.json ]; then
            [ "${HIGH_COUNT:-0}" -gt 0 ] && FAIL=1
          fi
          if [ -f security-reports/trivy-fs.json ]; then
            TFS=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL")] | length' security-reports/trivy-fs.json 2>/dev/null || echo 0)
            [ "${TFS:-0}" -gt 0 ] && FAIL=1
          fi
          if [ -f security-reports/trivy-image.json ]; then
            TIM=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH" or .Severity=="CRITICAL")] | length' security-reports/trivy-image.json 2>/dev/null || echo 0)
            [ "${TIM:-0}" -gt 0 ] && FAIL=1
          fi

          [ "$FAIL" -eq 1 ] && { echo "High/Critical vulnerabilities found -> failing Security stage"; exit 1; }
          echo "Security checks passed (or tools unavailable)."
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'security-reports/**', allowEmptyArchive: true
        }
      }
    }

    stage('Push Image') {
      when { allOf {
        expression { fileExists('image.txt') }
        expression { return env.REGISTRY?.trim() && env.IMAGE_NAME?.trim() }
      } }
      environment {
        // optional registry creds (username/password)
        DOCKER_REGISTRY_CREDS = credentials('DOCKER_REGISTRY_CREDS')
      }
      steps {
        sh '''
          set -e
          IMAGE="$(cat image.txt)"
          echo "Preparing to push $IMAGE and :latest"
          if command -v docker >/dev/null 2>&1; then
            if [ -n "$DOCKER_REGISTRY_CREDS_USR" ]; then
              echo "$DOCKER_REGISTRY_CREDS_PSW" | docker login "$REGISTRY" -u "$DOCKER_REGISTRY_CREDS_USR" --password-stdin
            fi
            docker push "$IMAGE"
            docker push "$REGISTRY/$IMAGE_NAME:latest"
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
          if [ -f docker-compose.yml ]; then
            command -v docker >/dev/null 2>&1 || { echo "docker not found; skipping compose"; exit 0; }
            # Pull fresh image if tagged
            if [ -f image.txt ]; then
              IMAGE="$(cat image.txt)"
              docker pull "$IMAGE" || true
            fi
            docker compose down || true
            docker compose up -d --build
          elif [ -n "$DEPLOY_SSH" ]; then
            ssh -o StrictHostKeyChecking=no "$DEPLOY_SSH" "mkdir -p '$DEPLOY_PATH'"
            rsync -az --delete dist/  "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
            rsync -az --delete build/ "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
          fi

          # Blocking health check with retries (if HEALTH_URL provided)
          if [ -n "$HEALTH_URL" ]; then
            echo "Waiting for $HEALTH_URL to become healthy ..."
            ok=0
            for i in 1 2 3 4 5; do
              code=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || true)
              echo "Attempt $i: HTTP $code"
              if [ "$code" = "200" ]; then ok=1; break; fi
              sleep 5
            done
            [ "$ok" -eq 1 ] || { echo "Health check failed after retries"; exit 1; }
          else
            echo "HEALTH_URL not set -> skipping deploy verification"
          fi
        '''
      }
    }

    stage('Release') {
      when { expression { return env.GIT_URL?.trim() } }
      steps {
        sh '''
          set -e
          TAG="release-${BUILD_NUMBER}"
          git config user.name "jenkins"
          git config user.email "jenkins@local"
          # include short changelog in annotated tag
          CHANGELOG=$(git log --pretty=format:"* %s" -n 10 || true)
          git tag -fa "$TAG" -m "CI release ${BUILD_NUMBER}\n\n${CHANGELOG}"
          git push --force origin "$TAG" || true
          echo "Created git tag $TAG"
        '''
      }
    }

    stage('Monitoring') {
      steps {
        sh '''
          set -e
          mkdir -p monitoring
          if [ -z "$HEALTH_URL" ]; then
            echo "Monitoring: HEALTH_URL not set -> skipping"
            exit 0
          fi

          echo "Pinging $HEALTH_URL ..."
          TS=$(date -u +%FT%TZ)
          HTTP_CODE=$(curl -fsS -o monitoring/health-${BUILD_NUMBER}.json -w "%{http_code}" "$HEALTH_URL" || echo "000")
          echo "$TS $HEALTH_URL -> $HTTP_CODE" | tee monitoring/ping-${BUILD_NUMBER}.txt
          # Non-blocking by design; deploy already blocked earlier
          exit 0
        '''
      }
      post {
        always { archiveArtifacts artifacts: 'monitoring/**', allowEmptyArchive: true }
      }
    }
  }

  post {
    success { echo '✅ Pipeline succeeded.' }
    failure { echo '❌ Pipeline failed. Check the first red error above.' }
    always  { echo "Build #${env.BUILD_NUMBER} complete." }
  }
}
