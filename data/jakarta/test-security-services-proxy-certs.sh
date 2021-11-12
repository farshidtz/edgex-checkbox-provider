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

snap_remove

# remove keys if exist
rm -rf private.pem public.pem localhost.cert localhost.key csrfile csrkeyfile

# install the snap to make sure it installs
if [ -n "$REVISION_TO_TEST" ]; then
    snap_install "$REVISION_TO_TEST" "$REVISION_TO_TEST_CHANNEL" "$REVISION_TO_TEST_CONFINEMENT"
else
    snap_install edgexfoundry "$DEFAULT_TEST_CHANNEL" 
fi

# wait for services to come online
# NOTE: this may have to be significantly increased on arm64 or low RAM platforms
# to accomodate time for everything to come online
sleep 120

# generate JWT Token
openssl ecparam -genkey -name prime256v1 -noout -out private.pem
openssl ec -in private.pem -pubout -out public.pem
snap set edgexfoundry env.security-proxy.user=user01,USER_ID,ES256
snap set edgexfoundry env.security-proxy.public-key="$(cat public.pem)"
TOKEN=`edgexfoundry.secrets-config proxy jwt --algorithm ES256 --private_key private.pem --id USER_ID --expiration=1h`

# verify self-signed TLS certificate
code=$(curl --insecure --silent --include \
    --output /dev/null --write-out "%{http_code}" \
    -X GET 'https://localhost:8443/core-data/api/v2/ping?' \
    -H "Authorization: Bearer $TOKEN") 
if [[ $code != 200 ]]; then
    echo "self-signed Kong TLS verification cannot be implemented"
    snap_remove
    exit 1
fi

# enable this recheck, once this issue has been solved: https://warthogs.atlassian.net/browse/EDGEX-237?focusedCommentId=26353
# restart all of EdgeX (including the security-services) and make sure the same certificate still works
# snap disable edgexfoundry > /dev/null
# snap enable edgexfoundry > /dev/null

# sleep 240

# code=$(curl --insecure --silent --include \
#     --output /dev/null --write-out "%{http_code}" \
#     -X GET 'https://localhost:8443/core-data/api/v2/ping?' \
#     -H "Authorization: Bearer $TOKEN")
# if [[ $code != 200 ]]; then
#     echo "self-signed Kong TLS verification cannot be implemented"
#     snap_remove
#     exit 1
# fi

# check if edgeca missing, then install it
#  We are running the test script with 'sudo' and although the edgeca snap has the home interface, 
#  which allows access to the home directory, when running as sudo, the user is root, 
# so it has a different home directory and doesn't have write access to your home directory. 
# The simplest fix: snap install edgeca --devmode
if [ -z "$(snap list edgeca)" ]; then
    snap install edgeca
    edgeca_is_installed=true
    echo "edgeca installed"
fi

sleep 60

# generate CA-signed TLS certificate
su - "$USER" -c "edgeca gencsr --cn localhost --csr csrfile --key csrkeyfile"
su - "$USER" -c "edgeca gencert -o localhost.cert -i csrfile -k localhost.key"
snap set edgexfoundry env.security-proxy.tls-certificate="$(cat localhost.cert)"
snap set edgexfoundry env.security-proxy.tls-private-key="$(cat localhost.key)"

# verify CA-signed TLS certificate
code=$(curl --insecure --silent --include \
    --output /dev/null --write-out "%{http_code}" \
    --cacert /var/snap/edgeca/current/CA.pem \
    -X GET 'https://localhost:8443/core-data/api/v2/ping?' \
    -H "Authorization: Bearer $TOKEN")
if [[ $code != 200 ]]; then
    echo "CA-signed Kong TLS verification cannot be implemented"
    # snap_remove
    # exit 1
fi

# enable this recheck, once this issue has been solved: https://warthogs.atlassian.net/browse/EDGEX-237?focusedCommentId=26353
# restart all of EdgeX (including the security-services) and make sure the same certificate still works
# snap disable edgexfoundry > /dev/null
# snap enable edgexfoundry > /dev/null

# # sleep 240

# # recheck
# code=$(curl --insecure --silent --include \
#     --output /dev/null --write-out "%{http_code}" \
#     --cacert /var/snap/edgeca/current/CA.pem \
#     -X GET 'https://localhost:8443/core-data/api/v2/ping?' \
#     -H "Authorization: Bearer $TOKEN")
# if [[ $code != 200 ]]; then
#     echo "CA-signed Kong TLS verification cannot be implemented"
#     snap_remove
#     exit 1
# fi

# remove the snap to run the next test
snap_remove

# remove the edgeca if we installed it
if [ "$edgeca_is_installed" = true ] ; then
    snap remove --purge edgeca
    echo "edgeca removed"
fi

# remove keys if we generated
rm -rf private.pem public.pem localhost.cert localhost.key csrfile csrkeyfile
