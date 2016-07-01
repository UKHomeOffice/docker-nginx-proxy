#!/usr/bin/env bash

set -e

source /defaults.sh

while true; do
    # Now download data if we can...
    # This always reports exit code 1!
    hash=$(md5sum /usr/share/GeoIP/GeoLiteCountry.dat)

    geoipupdate || true

    newhash=$(md5sum /usr/share/GeoIP/GeoLiteCountry.dat)

    if [ "${hash}" == "${newhash}" ]; then
      msg "GeoIP database not updated."
    else
      msg "Reloading conf (GeoIP database updated)..."
      ${NGINX_BIN} -s reload
    fi

    # Check once a day...
    sleep 86400
done