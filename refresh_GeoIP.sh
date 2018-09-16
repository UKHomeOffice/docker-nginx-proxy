#!/usr/bin/env bash

set -e

source /defaults.sh

# The following AccountID and LicenseKey are required placeholders.
# For geoipupdate versions earlier than 2.5.0, use UserId here instead of AccountID.
#AccountID 0
#LicenseKey 000000000000

# Include one or more of the following edition IDs:
# * GeoLite2-City - GeoLite 2 City
# * GeoLite2-Country - GeoLite2 Country
# For geoipupdate versions earlier than 2.5.0, use ProductIds here instead of EditionIDs.
#EditionIDs GeoLite2-Country

while true; do
    # Now download data if we can...
    # This always reports exit code 1!
    hash=$(md5sum /usr/share/GeoIP/GeoLite2-Country.mmdb)

    geoipupdate || true

    newhash=$(md5sum /usr/share/GeoIP/GeoLite2-Country.mmdb)

    if [ "${hash}" == "${newhash}" ]; then
      msg "GeoIP database not updated."
    else
      msg "Reloading conf (GeoIP database updated)..."
      ${NGINX_BIN} -s reload
    fi

    # Check once a day...
    sleep 86400
done
