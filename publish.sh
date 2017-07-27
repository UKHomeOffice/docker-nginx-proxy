#!/usr/bin/env bash

REPO="artifactory-internal.digital.homeoffice.gov.uk"
BASE="/"
NAME="nginx-proxy"
FULL_NAME="${REPO}${BASE}${NAME}"
DOCKER_USERNAME="lev-web-robot"

PATCH="${DRONE_TAG}"
MINOR=`echo ${PATCH} | awk -F '.' '{print $1"."$2}'`
MAJOR=`echo ${MINOR} | awk -F '.' '{print $1}'`

docker login -u="${DOCKER_USERNAME}" -p="${DOCKER_PASSWORD}" "${REPO}"

tag_n_push() {
  echo "Publishing ${1} of ${NAME}..."
  docker tag ngx "${FULL_NAME}:${1}"
  docker push "${FULL_NAME}:${1}"
  echo "published ${1}"
}

tag_n_push "${PATCH}"
tag_n_push "${MINOR}"
tag_n_push "${MAJOR}"
tag_n_push "latest"
