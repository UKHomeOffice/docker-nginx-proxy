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
    /usr/local/bin/geoipupdate -d /usr/share/GeoIP || true
    sleep 86400
done
