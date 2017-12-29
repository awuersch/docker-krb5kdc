#!/bin/bash -e
# /usr/sbin/krb5kdc -r $LDAP_KDC_REALM -n
if [[ -f /etc/krb5kdc/docker-kdc-realm ]]; then
  REALM=$(</etc/krb5kdc/docker-kdc-realm)
  if [[ -f /etc/krb5kdc/docker-kdc-run-admin-server ]]; then
    kadmind -r $REALM -nofork
  else
    krb5kdc -r $REALM -n
  fi
else
  sleep 10000000
fi
