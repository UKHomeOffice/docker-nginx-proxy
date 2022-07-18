#!/bin/sh

usage() {
    cat <<EOL
USAGE: ${0} SRC DEST VERSION

  SRC:     The name of the local image to be published
      e.g. my-image:my-tag

  DEST:    The name to publish as minus the tag
      e.g. quay.io/you/my-image

  VERSION: The full version (to patch level) to publish as
      e.g. v0.1.0
EOL
}

SRC="${1}"
DEST="${2}"
VERSION="${3}"

check_arg() {
    if [ -z "${1}" ]; then
        echo "Error: Missing ${2} in arguments";
        echo
        usage
        exit 1;
    fi
}

check_arg "${SRC}" "SRC"
check_arg "${DEST}" "DEST"
check_arg "${VERSION}" "VERSION"

PATCH="${VERSION}"
MINOR=`echo ${PATCH} | awk -F '.' '{print $1"."$2}'`
MAJOR=`echo ${MINOR} | awk -F '.' '{print $1}'`

tag_n_push() {
    FULL_NAME="${DEST}:${1}"
    echo -n "Publishing '${SRC}' as '${FULL_NAME}'..."
    docker tag "${SRC}" "${FULL_NAME}"
    docker push "${FULL_NAME}"
    echo " done."
}

tag_n_push "${PATCH}"
tag_n_push "${MINOR}"
tag_n_push "${MAJOR}"
#tag_n_push "latest"
tag_n_push "test"
