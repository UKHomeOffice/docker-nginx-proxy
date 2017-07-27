#!/usr/bin/env bash

REPO="artifactory-internal.digital.homeoffice.gov.uk"
BASE="/"
NAME="nginx-proxy"
FULL_NAME="${REPO}${BASE}${NAME}"
DOCKER_USERNAME="lev-web-robot"

docker login -u="${DOCKER_USERNAME}" -p="${DOCKER_PASSWORD}" "${REPO}"

tag_n_push() {
  echo "Publishing ${1} of ${NAME}..."
  docker tag ngx "${FULL_NAME}:${1}"
  docker push "${FULL_NAME}:${1}"
  echo "published ${1}"
}

tag_n_push "${DRONE_TAG}"
tag_n_push "latest"
