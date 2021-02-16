#!/usr/bin/env groovy

pipeline {
  agent any

  options {
    ansiColor('xterm')
    timestamps()
  }

  libraries {
    lib("pay-jenkins-library@master")
  }

  stages {
    stage('Test') {
      steps {
        sh './ci-build.sh'
      }
    }

    stage('Docker Build') {
      steps {
        script {
          buildAppWithMetrics { 
            app = "docker-nginx-proxy"
          }
        }
      }
    }
    stage('Docker Tag') {
      steps {
        script {
          dockerTagWithMetrics {
            app = "docker-nginx-proxy"
          }
        }
      }
    }
    stage('Tag Build') {
      when {
        branch 'master'
      }
      steps {
        tagDeployment("nginx-proxy")
      }
    }
  }
}
