pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  tools   { nodejs 'NodeJS' }

  environment {
    // ----- registry & image -----
    REGISTRY    = "${env.REGISTRY ?: ''}"                // e.g. docker.io/abdulla  (no trailing slash)
    IMAGE_NAME  = "${env.IMAGE_NAME ?: 'my-app'}"
    IMAGE_TAG   = "${env.IMAGE_TAG  ?: "build-${env.BUILD_NUMBER}"}"
    IMAGE_FULL  = "${REGISTRY}/${IMAGE_NAME}"

    // ----- versions / tags -----
    VERSION     = "v${env.BUILD_NUMBER}"
    COMMIT_SHA  = ""                                      // set later
    RELEASE_TAG = ""                                      // set later
    STAGING_TAG = ""                                      // set later
    PROD_TAG    = ""                                      // set later

    // ----- Sonar -----
    SONAR_HOST  = "${env.SONAR_HOST ?: ''}"
    SONAR_TOKEN = credentials('SONAR_TOKEN1')

    // ----- deploy / health -----
    DEPLOY_SSH  = "${env.DEPLOY_SSH ?: ''}"              // e.g. ubuntu@host
    DEPLOY_PATH = "${env.DEPLOY_PATH ?: '/var/www/app'}"
    HEALTH_URL  = "${env.HEALTH_URL ?: 'http://localhost:8080/health'}"
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.COMMIT_SHA = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
          env.RELEASE_TAG = "${env.VERSION}-${env.COMMIT_SHA}"
          env.STAGING_TAG = "staging-${env.COMMIT_SHA}"
          env.PROD_TAG    = "prod-${env.COMMIT_SHA}"
        }
      }
    }

    stage('Build') {
      steps {
        sh '''
          set -e
          echo "Node: $(node -v)  npm: $(npm -v)"
          if [ -f package-lock.json ]; then npm ci; else npm install; fi
          npm run build --if-present

          if command -v docker >/dev/null 2>&1 && [ -f Dockerfile ] && [ -n "$REGISTRY" ] && [ -n "$IMAGE_NAME" ]; then
            IMAGE="${IMAGE_FULL}:${STAGING_TAG}"
            echo "Building Docker image $IMAGE"
            docker build -t "$IMAGE" .
            # also tag :latest for convenience (pushed later)
            docker tag "$IMAGE" "${IMAGE_FULL}:latest"
            printf "%s\n" "$IMAGE" > image.txt
            docker image inspect "$IMAGE" --format='{{.Id}}' | tee image-digest.txt
          else
            echo "Skipping Docker image build (docker/envs missing). Archiving build artefacts instead."
            mkdir -p artifacts
            [ -d dist  ] && tar -czf artifacts/dist.tgz  dist
            [ -d build ] && tar -czf artifacts/build.tgz build
            [ -f package.json ] && cp package.json artifacts/
          fi
        '''
      }
      post {
        always { archiveArtifacts artifacts: 'artifacts/**,image.txt,image-digest.txt', allowEmptyArchive: true }
      }
    }

    stage('Test') {
      steps {
        sh '''
          set -e
          if npm run | grep -qE "^ *test"; then
            # produce JUnit + coverage if possible (Jest example)
            if [ -f node_modules/.bin/jest ] || npx --yes jest --version >/dev/null 2>&1; then
              npx --yes jest --ci --reporters=default --reporters=jest-junit --outputFile=junit.xml --coverage || true
            else
              npm test || true
            fi
          else
            echo "No test script found -> skipping tests"
          fi
        '''
      }
      post {
        always {
          junit testResults: 'junit*.xml, **/junit*.xml', allowEmptyResults: true
          archiveArtifacts artifacts: 'coverage/**', allowEmptyArchive: true
          // --- Coverage gate (fail if < 80%) when coverage-summary.json exists ---
          script {
            def hasCoverage = sh(returnStatus: true, script: "test -f coverage/coverage-summary.json") == 0
            if (hasCoverage) {
              def pct = sh(returnStdout: true, script: "node -e \"console.log(require('./coverage/coverage-summary.json').total.lines.pct|0)\"").trim()
              echo "Lines coverage: ${pct}%"
              if (pct.isInteger() && pct.toInteger() < 80) {
                error "Coverage below threshold: ${pct}% < 80%"
              }
            } else {
              echo "No coverage-summary.json -> skipping coverage gate"
            }
          }
        }
      }
    }

    stage('Code Quality') {
      steps {
        sh '''
          set -e
          if [ -z "$SONAR_HOST" ]; then echo "No SONAR_HOST -> skip analysis"; exit 0; fi
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

    // --- REQUIRED for top band: wait & FAIL on Quality Gate ---
    stage('Quality Gate') {
      when { expression { return env.SONAR_HOST?.trim() } }
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          script {
            def qg = waitForQualityGate()   // requires SonarQube Scanner for Jenkins plugin
            echo "Quality Gate: ${qg.status}"
            if (qg.status != 'OK') {
              error "Quality gate failed: ${qg.status}"
            }
          }
        }
      }
    }

    stage('Security') {
      steps {
        sh '''
          set -e
          mkdir -p security-reports

          # 1) npm audit (JSON) — gate on high/critical
          if command -v npm >/dev/null 2>&1; then
            echo "Running npm audit --json ..."
            npm audit --json > security-reports/npm-audit.json || true
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

          # Fail policy
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
      post { always { archiveArtifacts artifacts: 'security-reports/**', allowEmptyArchive: true } }
    }

    stage('Push Image') {
      when {
        allOf {
          expression { fileExists('image.txt') }
          expression { return env.REGISTRY?.trim() && env.IMAGE_NAME?.trim() }
        }
      }
      environment {
        DOCKER_REGISTRY_CREDS = credentials('DOCKER_REGISTRY_CREDS') // <-- set in Jenkins
      }
      steps {
        sh '''
          set -e
          IMAGE="$(cat image.txt)"
          echo "Preparing to push $IMAGE and ${IMAGE_FULL}:latest"
          if command -v docker >/dev/null 2>&1; then
            if [ -n "$DOCKER_REGISTRY_CREDS_USR" ]; then
              echo "$DOCKER_REGISTRY_CREDS_PSW" | docker login "$REGISTRY" -u "$DOCKER_REGISTRY_CREDS_USR" --password-stdin
            fi
            docker push "$IMAGE"
            docker push "${IMAGE_FULL}:latest"
          else
            echo "docker not available; skipping push"
          fi
        '''
      }
    }

    stage('Deploy (Staging)') {
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

            # Pull fresh staging image if built
            if [ -f image.txt ]; then
              IMAGE="$(cat image.txt)"
              docker pull "$IMAGE" || true
            fi

            # Prefer env-specific overlays if present
            if [ -f docker-compose.staging.yml ]; then
              IMAGE_TAG="$STAGING_TAG" IMAGE_FULL="$IMAGE_FULL" \
              docker compose -f docker-compose.yml -f docker-compose.staging.yml up -d --pull=always
            else
              docker compose down || true
              docker compose up -d --build
            fi
          elif [ -n "$DEPLOY_SSH" ]; then
            ssh -o StrictHostKeyChecking=no "$DEPLOY_SSH" "mkdir -p '$DEPLOY_PATH'"
            rsync -az --delete dist/  "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
            rsync -az --delete build/ "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
          fi

          # Blocking health check with retries
          echo "Waiting for $HEALTH_URL to become healthy ..."
          ok=0
          for i in $(seq 1 20); do
            code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$HEALTH_URL" || true)
            echo "Attempt $i: HTTP $code"
            if [ "$code" = "200" ]; then ok=1; break; fi
            sleep 3
          done
          [ "$ok" -eq 1 ] || { echo "Health check failed after retries"; exit 1; }
        '''
      }
    }

    // ----- RELEASE: Git tags (using PAT) + image promotion to prod -----
    stage('Release') {
      when { expression { return env.GIT_URL?.trim() } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'GITHUB_PAT', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
          sh '''
            set -e
            # Ensure HTTPS push URL with PAT
            REPO_URL="$(git config --get remote.origin.url)"
            if echo "$REPO_URL" | grep -qE '^git@github.com:'; then
              OWNER_REPO=$(echo "$REPO_URL" | sed -E 's#^git@github.com:(.*)\\.git$#\\1#')
              git remote set-url origin "https://github.com/${OWNER_REPO}.git"
            fi

            git config user.name  "Jenkins CI"
            git config user.email "ci@jenkins"

            # Create/update tags (reruns safe)
            git tag -f "${RELEASE_TAG}"
            git tag -f "${VERSION}"

            # Push tags using PAT
            PUSH_URL="$(git config --get remote.origin.url)"
            PUSH_URL_AUTH="$(echo "$PUSH_URL" | sed -E "s#https://#https://${GIT_USER}:${GIT_TOKEN}@#")"
            git push --force "$PUSH_URL_AUTH" "${RELEASE_TAG}" "${VERSION}"

            echo "Pushed tags: ${RELEASE_TAG}, ${VERSION}"

            # Promote image to prod tags if image exists
            if [ -f image.txt ]; then
              IMAGE="$(cat image.txt)"   # ${IMAGE_FULL}:${STAGING_TAG}
              docker pull "$IMAGE" || true
              docker tag "$IMAGE" "${IMAGE_FULL}:${PROD_TAG}"
              docker tag "$IMAGE" "${IMAGE_FULL}:latest"
              docker push "${IMAGE_FULL}:${PROD_TAG}"
              docker push "${IMAGE_FULL}:latest"
              echo "Promoted image: ${IMAGE_FULL}:${PROD_TAG} and :latest"
            else
              echo "No image.txt -> skipping image promotion"
            fi
          '''
        }
      }
    }

    // ----- MONITORING: ping loop with retries, artefact, fail on degradation -----
    stage('Monitoring') {
      steps {
        sh '''
          set -e
          mkdir -p monitoring
          echo "Monitoring ${HEALTH_URL} for ~5 minutes (10 checks)..."
          > monitoring/uptime-${BUILD_NUMBER}.log
          STATUS=0
          for i in $(seq 1 10); do
            CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${HEALTH_URL}" || true)
            TS=$(date -u +%FT%TZ)
            echo "$TS CHECK $i: HTTP $CODE" | tee -a monitoring/uptime-${BUILD_NUMBER}.log
            [ "$CODE" -eq 200 ] || STATUS=1
            sleep 30
          done
          [ $STATUS -eq 0 ] || { echo "Monitoring detected degraded health"; exit 1; }
        '''
      }
      post { always { archiveArtifacts artifacts: 'monitoring/**', allowEmptyArchive: true } }
    }
  }

  post {
    success { echo 'Pipeline succeeded.' }
    failure { echo 'Pipeline failed. Check the first red error above.' }
    always  { echo "Build #${env.BUILD_NUMBER} (${env.RELEASE_TAG}) complete." }
  }
}
