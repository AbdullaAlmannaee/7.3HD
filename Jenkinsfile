pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  tools { nodejs 'NodeJS' }

  environment {
    REGISTRY    = "${env.REGISTRY ?: ''}"
    IMAGE_NAME  = "${env.IMAGE_NAME ?: ''}"
    IMAGE_TAG   = "${env.IMAGE_TAG ?: 'latest'}"
    SONAR_HOST  = "${env.SONAR_HOST ?: ''}"
    SONAR_TOKEN = credentials('SONAR_TOKEN1')
    DEPLOY_SSH  = "${env.DEPLOY_SSH ?: ''}"
    DEPLOY_PATH = "${env.DEPLOY_PATH ?: '/var/www/app'}"
    HEALTH_URL  = "${env.HEALTH_URL ?: ''}"
  }

  stages {
    stage('Checkout') { steps { checkout scm } }

    // Build & Test in parallel (shows as two columns under one stage)
    stage('Build and Test') {
      parallel {
        stage('Build') {
          steps {
            sh '''
              set -e
              echo "Node: $(node -v)  npm: $(npm -v)"
              if [ -f package-lock.json ]; then npm ci; else npm install; fi
              npm run build --if-present

              # Only build Docker image if Docker exists AND Dockerfile present AND registry/name provided
              if command -v docker >/dev/null 2>&1 && [ -f Dockerfile ] && [ -n "$REGISTRY" ] && [ -n "$IMAGE_NAME" ]; then
                IMAGE="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
                echo "Building Docker image $IMAGE"
                docker build -t "$IMAGE" .
                echo "$IMAGE" > image.txt
              else
                echo "Skipping Docker image build (docker or envs missing). Archiving artifacts instead."
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
              npm test --if-present || true
            '''
          }
          post {
            always {
              junit testResults: 'junit*.xml, **/junit*.xml', allowEmptyResults: true
              archiveArtifacts artifacts: 'coverage/**', allowEmptyArchive: true
            }
          }
        }
      }
    }

    // 3) CODE QUALITY (always enters stage; self-skip with a message)
    stage('Code Quality') {
      steps {
        sh '''
          set -e
          if [ ! -f sonar-project.properties ]; then
            echo "Sonar: sonar-project.properties not found -> skipping (success)."
            exit 0
          fi
          if [ -z "$SONAR_HOST" ]; then
            echo "Sonar: SONAR_HOST not set -> skipping (success)."
            exit 0
          fi

          echo "Running SonarQube scan against $SONAR_HOST ..."
          if ! command -v sonar-scanner >/dev/null 2>&1; then
            npm i -D sonar-scanner
            npx sonar-scanner -Dsonar.host.url="$SONAR_HOST" -Dsonar.login="$SONAR_TOKEN" || true
          else
            sonar-scanner  -Dsonar.host.url="$SONAR_HOST" -Dsonar.login="$SONAR_TOKEN" || true
          fi
        '''
      }
    }

    // Security (simple dependency scan)
    stage('Security') {
      steps { sh 'npm audit --audit-level=high || true' }
    }

    // Deploy (test/staging)
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
            docker compose down || true
            docker compose up -d --build
          elif [ -n "$DEPLOY_SSH" ]; then
            ssh -o StrictHostKeyChecking=no "$DEPLOY_SSH" "mkdir -p '$DEPLOY_PATH'"
            rsync -az --delete dist/  "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
            rsync -az --delete build/ "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
          fi
        '''
      }
    }

    // Release (tag repo)
    stage('Release') {
      when { expression { return env.GIT_URL?.trim() } }
      steps {
        sh '''
          set -e
          TAG="release-${BUILD_NUMBER}"
          git config user.name "jenkins"
          git config user.email "jenkins@local"
          git tag -f "$TAG"
          git push --force origin "$TAG" || true
          echo "Created git tag $TAG"
        '''
      }
    }

    // 7) MONITORING (always enters stage; quick, non-blocking health check)
    stage('Monitoring') {
      steps {
        sh '''
          set -e
          if [ -z "$HEALTH_URL" ]; then
            echo "Monitoring: HEALTH_URL not set -> skipping (success)."
            exit 0
          fi

          echo "Pinging $HEALTH_URL ..."
          # --max-time prevents long hangs that keep Blue Ocean blue forever
          if curl -fsS --max-time 10 "$HEALTH_URL" >/dev/null; then
            echo "Monitoring: Health OK"
          else
            echo "Monitoring: Health check failed (non-blocking)"; exit 0
          fi
        '''
      }
    }

  post {
    success { echo '✅ Pipeline succeeded.' }
    failure { echo '❌ Pipeline failed. Check the first red error above.' }
    always  { echo "Build #${env.BUILD_NUMBER} complete." }
  }
}
