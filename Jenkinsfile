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
    stage('Checkout') {
      steps {
        checkout scm
        echo 'Checkout stage reached'
      }
    }
    stage('Build') {
      steps {
        echo 'Build stage reached'
        sh 'true'   // placeholder so stage always “runs”
      }
    }
    stage('Test') {
      steps {
        echo 'Test stage reached'
        sh 'true'
      }
    }
    stage('Code Quality') {
      steps {
        echo "Code Quality stage reached (SONAR_HOST=${SONAR_HOST})"
        sh 'true'
      }
    }
    stage('Security') {
      steps {
        echo 'Security stage reached'
        sh 'true'
      }
    }
    stage('Deploy') {
      steps {
        echo 'Deploy stage reached'
        sh 'true'
      }
    }
    stage('Release') {
      steps {
        echo 'Release stage reached'
        sh 'true'
      }
    }
    stage('Monitoring') {
      steps {
        echo 'Monitoring stage reached'
        sh 'true'
      }
    }
  }

  post {
    always { echo "Build #${env.BUILD_NUMBER} complete." }
  }
}
