#!/bin/bash -e

# get the directory of this script
# snippet from https://stackoverflow.com/a/246128/10102404
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

# load the utils
# shellcheck source=/dev/null
source "$SCRIPT_DIR/utils.sh"

DEFAULT_TEST_CHANNEL=${DEFAULT_TEST_CHANNEL:-beta}


# FIXME: The Ireland release no longer initializes an EdgeX CA used to
# sign the TLS certificates for Kong or Vault. As of Ireland, TLS is no
# longer used for connections to Vault per:
#
# https://github.com/edgexfoundry/edgex-docs/blob/master/docs_src/design/adr/security/0015-in-cluster-tls.md
#
# As for Kong, EdgeX now by default relies on a self-signed certificates
# generated by Kong on install for TLS. Production TLS certs can be
# configured using the EdgeX security-config command or via the configure
# hook. Finally, the Kong Admin API has also been locked down so this test
# as written will not work unless the Kong Admin API token is used. In
# theory, it should be possible to just copy this token from $SNAP_DATA for
# use by this script. So this test requires the following changes before it
# can be enabled:
#
# - If Kong Admin API is still used, copy or reference the appropriate token
#   from w/in SNAP_DATA. Another option would be to change this script to use
#   the non-Admin API, however the best solution would be to test both.
#
# - Change this test to ensure that by default a self-signed cert is being
#   used for TLS (i.e. use -k or --insecure to disable verification of peer),
#   again for one or both APIs (i.e. Admin & non-Admin).
#
# - Add test logic to configure a non-self-signed TLS cert for one or both
#   APIs and validate that the correct cert is configured using the same
#   approach as used in Hanoi and earlier versions of this test.
#
echo "skipping test until updated Kong TLS verification is implemented."
exit 0

snap_remove

# install the snap to make sure it installs
if [ -n "$REVISION_TO_TEST" ]; then
    snap_install "$REVISION_TO_TEST" "$REVISION_TO_TEST_CHANNEL" "$REVISION_TO_TEST_CONFINEMENT"
else
    snap_install edgexfoundry "$DEFAULT_TEST_CHANNEL" 
fi

# wait for services to come online
# NOTE: this may have to be significantly increased on arm64 or low RAM platforms
# to accomodate time for everything to come online
sleep 240

# copy the root certificate to confirm that can be used to authenticate the
# kong server
#cp /var/snap/edgexfoundry/current/secrets/ca/ca.pem /var/snap/edgexfoundry/current/ca.pem

# use curl to talk to the kong admin endpoint with the cert
edgexfoundry.curl --cacert /var/snap/edgexfoundry/current/kong/ssl/admin-kong-default.crt https://localhost:8443/command > /dev/null

# restart all of EdgeX (including the security-services) and make sure the 
# same certificate still works
snap disable edgexfoundry > /dev/null
snap enable edgexfoundry > /dev/null

sleep 240
edgexfoundry.curl --cacert /var/snap/edgexfoundry/current/kong/ssl/admin-kong-default.crt https://localhost:8443/command > /dev/null

# remove the snap to run the next test
snap_remove
