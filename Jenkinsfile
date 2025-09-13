pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  tools   { nodejs 'NodeJS' }

  environment {
    // Make Homebrew tools visible to Jenkins (Apple Silicon & Intel)
    PATH        = "/opt/homebrew/bin:/usr/local/bin:${env.PATH}"

    REGISTRY    = "${env.REGISTRY ?: ''}"                 // e.g. docker.io/abdulla
    IMAGE_NAME  = "${env.IMAGE_NAME ?: 'my-app'}"
    IMAGE_TAG   = "${env.IMAGE_TAG ?: ('build-' + env.BUILD_NUMBER)}"

    SONAR_HOST  = "${env.SONAR_HOST ?: ''}"
    SONAR_TOKEN = credentials('SONAR_TOKEN1')

    // Optional deploy/env
    DEPLOY_SSH  = "${env.DEPLOY_SSH ?: ''}"               // e.g. ubuntu@host
    DEPLOY_PATH = "${env.DEPLOY_PATH ?: '/var/www/app'}"
    HEALTH_URL  = "${env.HEALTH_URL ?: ''}"

    // Optional Snyk (SAFE: won’t fail if not set)
    SNYK_TOKEN  = "${env.SNYK_TOKEN ?: ''}"               // set in Job → Configure (or add Jenkins credential and export it here)
    SNYK_ORG    = "${env.SNYK_ORG   ?: ''}"
  }

  stages {

    stage('Checkout') { steps { checkout scm } }

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
      post { always { archiveArtifacts artifacts: 'artifacts/**,image.txt', allowEmptyArchive: true } }
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
          if [ -z "$SONAR_HOST" ]; then echo "No SONAR_HOST -> skip"; exit 0; fi
          if ! command -v sonar-scanner >/dev/null 2>&1; then npm i -D sonar-scanner; SC="npx sonar-scanner"; else SC="sonar-scanner"; fi
          $SC \
            -Dsonar.host.url="$SONAR_HOST" \
            -Dsonar.login="$SONAR_TOKEN" \
            -Dsonar.projectKey=AbdullaAlmannaee_7.3HD \
            -Dsonar.organization=abdullaalmannaee-1 \
            -Dsonar.projectName=7.3HD \
            -Dsonar.projectVersion=${BUILD_NUMBER} \
            -Dsonar.sources=. \
            -Dsonar.sourceEncoding=UTF-8
        '''
      }
    }

    stage('Security') {
      steps {
        sh '''
          set -e
          mkdir -p security-reports
          echo "PATH=$PATH"
          which trivy || true; trivy -v || true
          which jq || true; jq --version || true

          # 1) npm audit (JSON)
          if command -v npm >/dev/null 2>&1; then
            echo "Running npm audit --json ..."
            npm audit --json > security-reports/npm-audit.json || true
          fi

          # 2) Trivy FS + Image 
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
            # OPTIONAL Docker fallback (uncomment if Docker is available on the agent):
            # if command -v docker >/dev/null 2>&1; then
            #   docker run --rm -v "$PWD":/src aquasec/trivy:latest fs --exit-code 0 --severity HIGH,CRITICAL --format json /src > security-reports/trivy-fs.json
            #   if [ -f image.txt ]; then
            #     IMAGE="$(cat image.txt)"
            #     docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --exit-code 0 --severity HIGH,CRITICAL --format json "$IMAGE" > security-reports/trivy-image.json
            #   fi
            # fi
          fi

          # 3) Snyk (optional; runs only if SNYK_TOKEN is set)
          SNYK_OSS_EXIT=0; SNYK_IMG_EXIT=0
          if [ -n "$SNYK_TOKEN" ]; then
            echo "Snyk token detected -> running Snyk scans"
            if ! command -v snyk >/dev/null 2>&1; then npm i -g snyk; fi
            snyk auth "$SNYK_TOKEN" || true

            set +e
            snyk test --severity-threshold=high ${SNYK_ORG:+--org="$SNYK_ORG"} \
              --json | tee security-reports/snyk-open-source.json
            SNYK_OSS_EXIT=$?
            if [ -f image.txt ]; then
              IMAGE="$(cat image.txt)"
              snyk container test "$IMAGE" --severity-threshold=high ${SNYK_ORG:+--org="$SNYK_ORG"} \
                --json | tee security-reports/snyk-container.json
              SNYK_IMG_EXIT=$?
            fi
            snyk monitor ${SNYK_ORG:+--org="$SNYK_ORG"} --project-name="7.3HD" || true
            set -e
          else
            echo "SNYK_TOKEN not set -> skipping Snyk"
          fi

          # 4) Fail policy (High/Critical anywhere)
          FAIL=0

          if command -v jq >/dev/null 2>&1; then
            if [ -f security-reports/npm-audit.json ]; then
              HIGH_COUNT=$(jq '[.vulnerabilities|to_entries[]|select(.value.severity=="high" or .value.severity=="critical")]|length' security-reports/npm-audit.json 2>/dev/null || echo 0)
              echo "High/Critical (npm): ${HIGH_COUNT}"
              [ "${HIGH_COUNT:-0}" -gt 0 ] && FAIL=1
            fi
            if [ -f security-reports/trivy-fs.json ]; then
              TFS=$(jq '[.Results[]?.Vulnerabilities[]?|select(.Severity=="HIGH" or .Severity=="CRITICAL")]|length' security-reports/trivy-fs.json 2>/dev/null || echo 0)
              echo "High/Critical (Trivy FS): ${TFS}"
              [ "${TFS:-0}" -gt 0 ] && FAIL=1
            fi
            if [ -f security-reports/trivy-image.json ]; then
              TIM=$(jq '[.Results[]?.Vulnerabilities[]?|select(.Severity=="HIGH" or .Severity=="CRITICAL")]|length' security-reports/trivy-image.json 2>/dev/null || echo 0)
              echo "High/Critical (Trivy Image): ${TIM}"
              [ "${TIM:-0}" -gt 0 ] && FAIL=1
            fi
          else
            echo "jq not found -> skipping JSON severity counting"
          fi

          # Snyk exits non-zero when >= threshold issues are found
          [ "${SNYK_OSS_EXIT:-0}" -ne 0 ] && FAIL=1
          [ "${SNYK_IMG_EXIT:-0}" -ne 0 ] && FAIL=1

          [ "$FAIL" -eq 1 ] && { echo "High/Critical vulnerabilities found -> failing Security stage"; exit 1; }
          echo "Security checks passed (or tools unavailable)."
        '''
      }
      post { always { archiveArtifacts artifacts: 'security-reports/**', allowEmptyArchive: true } }
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
            if [ -f image.txt ]; then IMAGE="$(cat image.txt)"; docker pull "$IMAGE" || true; fi
            docker compose down || true
            docker compose up -d --build
          elif [ -n "$DEPLOY_SSH" ]; then
            ssh -o StrictHostKeyChecking=no "$DEPLOY_SSH" "mkdir -p '$DEPLOY_PATH'"
            rsync -az --delete dist/  "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
            rsync -az --delete build/ "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
          fi

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
          exit 0
        '''
      }
      post { always { archiveArtifacts artifacts: 'monitoring/**', allowEmptyArchive: true } }
    }
  }

  post {
    success { echo '✅ Pipeline succeeded.' }
    failure { echo '❌ Pipeline failed. Check the first red error above.' }
    always  { echo "Build #${env.BUILD_NUMBER} complete." }
  }
}
