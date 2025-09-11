pipeline {
  agent any

  environment {
    GITHUB_OWNER = 'AbdullaAlmannaee'
    GITHUB_REPO  = '7.3HD'
  }

  options {
    ansiColor('xterm')
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '25'))
  }

  stages {
    stage('Checkout') {
      steps {
        // Pull code from this GitHub repo/branch
        checkout scm
        sh 'git --version'
      }
    }

    stage('Build') {
      steps {
        sh 'echo "Build step (placeholder)"; mkdir -p build && echo ok > build/artifact.txt'
        archiveArtifacts artifacts: 'build/**', fingerprint: true
      }
    }

    stage('Test') {
      steps {
        sh '''
          set -e
          echo "Running unit tests (placeholder)…"
          [ "$(expr 1 + 1)" -eq 2 ] && echo "tests passed"
        '''
      }
    }

    stage('Release') {
      steps {
        withCredentials([string(credentialsId: 'GITHUB_TOKEN', variable: 'GITHUB_TOKEN')]) {
          sh '''
            set -e

            # Identify and trust workspace
            git config --global user.email "ci@jenkins.local"
            git config --global user.name  "Jenkins CI"
            git config --global --add safe.directory "$WORKSPACE"

            # Ensure full history & tags (if shallow clone)
            if git rev-parse --is-shallow-repository >/dev/null 2>&1; then
              git fetch --unshallow || true
            fi
            git fetch origin --tags

            # Create tag and push with token
            TAG="v$BUILD_NUMBER"
            git tag -a "$TAG" -m "CI release $BUILD_NUMBER" || true
            git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git"
            git push origin "$TAG"

            # Create GitHub Release
            curl -sS -X POST \
              -H "Authorization: Bearer ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github+json" \
              "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases" \
              -d "{\"tag_name\":\"$TAG\",\"name\":\"$TAG\",\"body\":\"Automated release from Jenkins build $BUILD_NUMBER\",\"draft\":false,\"prerelease\":false,\"generate_release_notes\":true}" \
              | tee "$WORKSPACE/release.json"

            echo "Release created for $TAG"
          '''
        }
      }
    }
  }

  post {
    success { echo '✅ Pipeline succeeded' }
    failure { echo '❌ Pipeline failed — see Console Output' }
  }
}
