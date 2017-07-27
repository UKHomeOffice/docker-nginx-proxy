#!/usr/bin/env bash

REPO="artifactory-internal.digital.homeoffice.gov.uk"
BASE="/"
NAME="nginx-proxy"
FULL_NAME="${REPO}${BASE}${NAME}"
DOCKER_USERNAME="lev-web-robot"
docker login -u="${DOCKER_USERNAME}" -p="${DOCKER_PASSWORD}" "${REPO}"
docker tag ngx "${FULL_NAME}:${DRONE_TAG}"
docker tag ngx "${FULL_NAME}:latest"
docker push "${FULL_NAME}:${DRONE_TAG}"
docker push "${FULL_NAME}:latest"
