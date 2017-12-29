#!/bin/bash

(($#==2)) || {
  >&2 echo "usage: $0 container-name hostname-prefix"
  exit 1
}

NAME=$1
HOSTNAME_PREFIX=$2

. ~/.ldapvars

BASEDIR=${BASEDIR:-/home/tony/home/docker/awuersch/krb5kdc}
LDAP_DOMAIN=tony.wuersch.name
LDAP_REALM=TONY.WUERSCH.NAME
LDAP_KDC_REALM=ANTHONY.WUERSCH.NAME
LDAP_URI="ldaps://ldap1.tony.wuersch.name"
KRB5KDC_VOLUME="${KRB5KDC_VOLUME:-$BASEDIR/data/krb5kdc}"
KRB5KDC_TARGET=/container/service/kdc/assets/krb5kdc
CERT_VOLUME="${CERT_VOLUME:-$BASEDIR/data/certs/$HOSTNAME_PREFIX}"
CERT_TARGET="${CERT_TARGET:-/container/service/kdc/assets/certs}"

docker run \
  --name $NAME \
  --hostname "$HOSTNAME_PREFIX.$LDAP_DOMAIN" \
  --env LDAP_DOMAIN="$LDAP_DOMAIN" \
  --env LDAP_REALM="$LDAP_REALM" \
  --env LDAP_KDC_REALM="$LDAP_KDC_REALM" \
  --env LDAP_URI="$LDAP_URI" \
  --env LDAP_REMOVE_CONFIG_AFTER_SETUP=false \
  --mount type=bind,source=$KRB5KDC_VOLUME,target=$KRB5KDC_TARGET \
  --detach awuersch/kdc:0.1.0 \
  --loglevel debug \
  --keep-startup-env
