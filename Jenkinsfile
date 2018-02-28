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
          buildApp{
            app = "docker-nginx-proxy"
          }
        }
      }
    }
    stage('Docker Tag') {
      steps {
        script {
          dockerTag {
            app = "docker-nginx-proxy"
          }
        }
      }
    }
  }
}
