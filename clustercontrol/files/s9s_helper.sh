#!/bin/bash
# ClusterControl puppet helper script
# Generate/read default SSH key to be used by puppet hosts
# ClusterControl requires proper SSH key setup between controller host and monitored DB hosts
# This script generates/reads private and public RSA key file under $KEYPATH

KEYPATH=/etc/puppet/modules/clustercontrol/files
[ ! -z "$2" ] && KEYPATH=$2/files
KEYFILE=$KEYPATH/id_rsa_s9s
KEYFILE_PUB=$KEYPATH/id_rsa_s9s.pub
KEYGEN=`command -v ssh-keygen`
[ -z "$KEYGEN" ] && echo "Error: Unable to locate ssh-keygen binary" && exit 1
[ ! -z "$1" ] && OPT=$1 || OPT='--generate-key'

do_rsa_keygen()
{
    if [ ! -f $KEYFILE ]; then
        $KEYGEN -q -t rsa -f $KEYFILE -C '' -N '' >& /dev/null
        chmod 644 $KEYFILE
        chmod 644 $KEYFILE_PUB
        echo "New key generated at $KEYPATH"
        exit 0
    else
        echo "Nothing to do. $KEYFILE is exist"
        exit 0
    fi
}

do_read_key()
{
    if [ -f "$KEYFILE_PUB" ]; then
        cut -d' ' -f2 $KEYFILE_PUB | tr -d "\r\n\t "
    else
        echo "Error: $KEYFILE_PUB not found"
        exit 1
    fi
}

do_generate_token()
{
    token=$(python -c 'import uuid; print uuid.uuid4()' | sha1sum | cut -f1 -d' ')
    echo $token
}

if [ "$OPT" == '--generate-key' ]; then
    do_rsa_keygen
elif [ "$OPT" == '--read-key' ]; then
    do_read_key
elif [ "$OPT" == '--generate-token' ]; then
    do_generate_token
else
    echo 'Supported options'
    echo '--generate-key   : Generate a SSH RSA key to be used by Puppet module (default)'
    echo '--read-key       : Read the generated SSH RSA (Puppet module)'
    echo '--generate-token : Generate ClusterControl API token'
fi
exit 0