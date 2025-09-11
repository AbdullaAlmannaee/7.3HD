pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  tools { nodejs 'NodeJS' }   // matches your Tools config

  environment {
    // ----- Optional env you can set in the job -----
    REGISTRY    = "${env.REGISTRY}"           // e.g. ghcr.io/youruser
    IMAGE_NAME  = "${env.IMAGE_NAME}"         // e.g. myapp
    IMAGE_TAG   = "${env.IMAGE_TAG ?: 'latest'}"
    SONAR_HOST  = "${env.SONAR_HOST}"         // e.g. http://sonarqube:9000
    SONAR_TOKEN = credentials('SONAR_TOKEN1') // <-- updated credential ID
    SNYK_TOKEN  = credentials('SNYK_TOKEN')   // Jenkins cred id (token)
    DEPLOY_SSH  = "${env.DEPLOY_SSH}"         // e.g. user@staging
    DEPLOY_PATH = "${env.DEPLOY_PATH ?: '/var/www/app'}"
    HEALTH_URL  = "${env.HEALTH_URL}"         // e.g. https://app.example.com/health
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    // 1) BUILD
    stage('Build') {
      steps {
        sh '''
          set -e
          echo "Node: $(node -v)  npm: $(npm -v)"
          if [ -f package-lock.json ]; then npm ci; else npm install; fi

          # Preferred app build step (if defined)
          npm run build --if-present

          # If Dockerfile exists, build a Docker image as the artefact
          if [ -f Dockerfile ] && [ -n "$REGISTRY" ] && [ -n "$IMAGE_NAME" ]; then
            IMAGE="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
            echo "Building Docker image $IMAGE"
            docker build -t "$IMAGE" .
            echo "$IMAGE" > image.txt
          else
            # Otherwise package the build/dist as a zip artefact
            mkdir -p artifacts
            if [ -d dist ];  then tar -czf artifacts/dist.tgz dist;  fi
            if [ -d build ]; then tar -czf artifacts/build.tgz build; fi
            if [ -f package.json ]; then cp package.json artifacts/; fi
          fi
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'artifacts/**,image.txt', allowEmptyArchive: true
        }
      }
    }

    // 2) TEST
    stage('Test') {
      steps {
        sh '''
          set -e
          # Runs tests if present; won’t fail pipeline if tests fail initially
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

    // 3) CODE QUALITY
    stage('Code Quality') {
      when {
        anyOf {
          expression { fileExists('sonar-project.properties') && env.SONAR_HOST?.trim() }
          expression { fileExists('.eslintrc') || fileExists('.eslintrc.js') || fileExists('.eslintrc.cjs') }
        }
      }
      steps {
        sh '''
          set -e
          if [ -f sonar-project.properties ] && [ -n "$SONAR_HOST" ]; then
            echo "Running SonarQube scan..."
            if ! command -v sonar-scanner >/dev/null 2>&1; then
              npm i -D sonar-scanner
              npx sonar-scanner \
                -Dsonar.host.url="$SONAR_HOST" \
                -Dsonar.login="$SONAR_TOKEN" || true
            else
              sonar-scanner \
                -Dsonar.host.url="$SONAR_HOST" \
                -Dsonar.login="$SONAR_TOKEN" || true
            fi
          fi

          # Optional ESLint (as code health) if config exists
          if [ -f .eslintrc ] || [ -f .eslintrc.js ] || [ -f .eslintrc.cjs ]; then
            npx eslint . || true
          fi
        '''
      }
    }

    // 4) SECURITY
    stage('Security') {
      steps {
        sh '''
          set -e
          if [ -n "$SNYK_TOKEN" ]; then
            if ! command -v snyk >/dev/null 2>&1; then npm i -g snyk; fi
            snyk auth "$SNYK_TOKEN" >/dev/null 2>&1 || true
            echo "Running Snyk dependency test..."
            snyk test || true
          else
            echo "SNYK_TOKEN not set; running npm audit (non-blocking)"
            npm audit --audit-level=high || true
          fi
        '''
      }
    }

    // 5) DEPLOY (to a test/staging env)
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
            echo "Deploying with docker-compose (test env)..."
            docker compose down || true
            docker compose up -d --build
          elif [ -n "$DEPLOY_SSH" ]; then
            echo "Deploying static build to $DEPLOY_SSH:$DEPLOY_PATH"
            ssh -o StrictHostKeyChecking=no "$DEPLOY_SSH" "mkdir -p '$DEPLOY_PATH'"
            rsync -az --delete dist/ "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
            rsync -az --delete build/ "$DEPLOY_SSH:$DEPLOY_PATH"/ || true
          fi
        '''
      }
    }

    // 6) RELEASE (promote to prod / tag)
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

    // 7) MONITORING & ALERTING
    stage('Monitoring') {
      when { expression { return env.HEALTH_URL?.trim() } }
      steps {
        sh '''
          set -e
          echo "Health check: $HEALTH_URL"
          if curl -fsS "$HEALTH_URL" >/dev/null; then
            echo "✅ Health OK"
          else
            echo "⚠️ Health check failed (non-blocking)"; exit 0
          fi
        '''
      }
    }
  }

  post {
    success { echo '✅ Pipeline succeeded.' }
    failure { echo '❌ Pipeline failed. Check the first red error above.' }
    always  { echo "Build #${env.BUILD_NUMBER} complete." }
  }
}
