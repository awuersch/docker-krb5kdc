#!/bin/bash -e
set -o pipefail

# set -x (bash debug) if log level is trace
# https://github.com/osixia/docker-light-baseimage/blob/stable/image/tool/log-helper
log-helper level eq trace && set -x

# create dir if they not already exists
[[ -d /etc/ldap/slapd.d ]] || mkdir -p /etc/ldap/slapd.d

FIRST_START_DONE="${CONTAINER_STATE_DIR}/kdc-first-start-done"
WAS_STARTED_WITH_TLS="/etc/ldap/docker-openldap-was-started-with-tls"
WAS_STARTED_WITH_TLS_ENFORCE="/etc/ldap/docker-openldap-was-started-with-tls-enforce"

ASSETS_DIR="${CONTAINER_SERVICE_DIR}/kdc/assets"
CERTS_DIR="$ASSETS_DIR/certs"

LDAP_TLS_CA_CRT_PATH="${CERTS_DIR}/$LDAP_TLS_CA_CRT_FILENAME"
LDAP_TLS_CRT_PATH="${CERTS_DIR}/$LDAP_TLS_CRT_FILENAME"
LDAP_TLS_KEY_PATH="${CERTS_DIR}/$LDAP_TLS_KEY_FILENAME"
LDAP_TLS_DH_PARAM_PATH="${CERTS_DIR}/dhparam.pem"

# CONTAINER_SERVICE_DIR and CONTAINER_STATE_DIR variables are set by
# the baseimage run tool more info : https://github.com/osixia/docker-light-baseimage

# container first start
if [ ! -e "$FIRST_START_DONE" ]; then

  #
  # Helpers
  #
  function get_ldap_base_dn() {
    # if LDAP_BASE_DN is empty set value from LDAP_DOMAIN
    if [ -z "$LDAP_BASE_DN" ]; then
      IFS='.' read -ra LDAP_BASE_DN_TABLE <<< "$LDAP_DOMAIN"
      for i in "${LDAP_BASE_DN_TABLE[@]}"; do
        EXT="dc=$i,"
        LDAP_BASE_DN=$LDAP_BASE_DN$EXT
      done
      LDAP_BASE_DN=${LDAP_BASE_DN::-1}
    fi
  }

  get_ldap_base_dn

  if [ "${KEEP_EXISTING_CONFIG,,}" == "true" ]; then
    log-helper info "/!\ KEEP_EXISTING_CONFIG = true configration will not be updated"
  else
    #
    # start OpenLDAP
    #

    # get previous hostname if OpenLDAP was started with replication
    # to avoid configuration pbs
    PREVIOUS_HOSTNAME_PARAM=""

    # if the config was bootstraped with TLS
    # to avoid error (#6) (#36) and (#44)
    # we create fake temporary certificates if they do not exists
    if [ -e "$WAS_STARTED_WITH_TLS" ]; then
      source $WAS_STARTED_WITH_TLS

      log-helper debug "Check previous TLS certificates..."

      # fix for #73
      # image started with an existing database/config created before 1.1.5
      [[ -z "$PREVIOUS_LDAP_TLS_CA_CRT_PATH" ]] && PREVIOUS_LDAP_TLS_CA_CRT_PATH="${CERTS_DIR}/$LDAP_TLS_CA_CRT_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_CRT_PATH" ]] && PREVIOUS_LDAP_TLS_CRT_PATH="${CERTS_DIR}/$LDAP_TLS_CRT_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_KEY_PATH" ]] && PREVIOUS_LDAP_TLS_KEY_PATH="${CERTS_DIR}/$LDAP_TLS_KEY_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_DH_PARAM_PATH" ]] && PREVIOUS_LDAP_TLS_DH_PARAM_PATH="${CERTS_DIR}/dhparam.pem"

      ssl-helper $LDAP_SSL_HELPER_PREFIX $PREVIOUS_LDAP_TLS_CRT_PATH $PREVIOUS_LDAP_TLS_KEY_PATH $PREVIOUS_LDAP_TLS_CA_CRT_PATH
      [ -f ${PREVIOUS_LDAP_TLS_DH_PARAM_PATH} ] || openssl dhparam -out ${LDAP_TLS_DH_PARAM_PATH} 2048

      chmod 600 ${PREVIOUS_LDAP_TLS_DH_PARAM_PATH}
    fi

    #
    # TLS config
    #
    if [[ -e "$WAS_STARTED_WITH_TLS" && "${LDAP_TLS,,}" != "true" ]]; then
      log-helper error "/!\ WARNING: LDAP_TLS=false but the container was previously started with LDAP_TLS=true"
      log-helper error "TLS can't be disabled once added. Ignoring LDAP_TLS=false."
      LDAP_TLS=true
    fi

    if [[ -e "$WAS_STARTED_WITH_TLS_ENFORCE" && "${LDAP_TLS_ENFORCE,,}" != "true" ]]; then
      log-helper error "/!\ WARNING: LDAP_TLS_ENFORCE=false but the container was previously started with LDAP_TLS_ENFORCE=true"
      log-helper error "TLS enforcing can't be disabled once added. Ignoring LDAP_TLS_ENFORCE=false."
      LDAP_TLS_ENFORCE=true
    fi

    if [[ "${LDAP_TLS,,}" == "true" ]]; then
      TLS_DIR=${CONTAINER_SERVICE_DIR}/kdc/assets/config/tls

      log-helper info "Add TLS config..."

      # generate a certificate and key with ssl-helper tool if LDAP_CRT and LDAP_KEY files don't exists
      # https://github.com/osixia/docker-light-baseimage/blob/stable/image/service-available/:ssl-tools/assets/tool/ssl-helper
      ssl-helper $LDAP_SSL_HELPER_PREFIX $LDAP_TLS_CRT_PATH $LDAP_TLS_KEY_PATH $LDAP_TLS_CA_CRT_PATH

      # create DHParamFile if not found
      [[ -f ${LDAP_TLS_DH_PARAM_PATH} ]] || openssl dhparam -out ${LDAP_TLS_DH_PARAM_PATH} 2048
      chmod 600 ${LDAP_TLS_DH_PARAM_PATH}

      [[ -f "$WAS_STARTED_WITH_TLS" ]] && rm -f "$WAS_STARTED_WITH_TLS"
      echo "export PREVIOUS_LDAP_TLS_CA_CRT_PATH=${LDAP_TLS_CA_CRT_PATH}" > $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_CRT_PATH=${LDAP_TLS_CRT_PATH}" >> $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_KEY_PATH=${LDAP_TLS_KEY_PATH}" >> $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_DH_PARAM_PATH=${LDAP_TLS_DH_PARAM_PATH}" >> $WAS_STARTED_WITH_TLS

      # enforce TLS
      if [[ "${LDAP_TLS_ENFORCE,,}" == "true" ]]; then
        touch $WAS_STARTED_WITH_TLS_ENFORCE
      fi

    # disable tls (not possible for now)
    #else
      #log-helper info "Disable TLS config..."
      #ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/kdc/assets/config/tls/tls-disable.ldif |& log-helper debug || true
      #[[ -f "$WAS_STARTED_WITH_TLS" ]] && rm -f "$WAS_STARTED_WITH_TLS"
    fi

    D="${CONTAINER_SERVICE_DIR}/kdc/assets/krb5kdc"
    if [[ -d "$D" ]]; then
      T=/etc/krb5kdc
      mkdir -p $T
      cp -r $D/.k5* $D/conf_keyfile $D/kadm5.acl $D/kdc.conf $T
      sed -i -e "{
        s|ldapi:///|$LDAP_URI|
        s|\$LDAP_HOSTNAME|$LDAP_HOSTNAME|
        s|\$LDAP_DOMAIN|$LDAP_DOMAIN|
      }" $T/kdc.conf

      if [[ X"${LDAP_ADM,,}" == X"true" ]]; then
	touch /etc/krb5kdc/docker-kdc-run-admin-server
      fi

      echo "${LDAP_KDC_REALM}" > /etc/krb5kdc/docker-kdc-realm
    else
      log-helper error "Error: the krb5kdc directory ($D) is empty"
      exit 1
    fi
  fi

  #
  # ldap client config
  #
  if [[ X"${LDAP_TLS,,}" == X"true" ]]; then
    log-helper info "Configure ldap client TLS configuration..."
    sed -i --follow-symlinks "s,TLS_CACERT.*,TLS_CACERT ${LDAP_TLS_CA_CRT_PATH},g" /etc/ldap/ldap.conf
    echo "TLS_REQCERT ${LDAP_TLS_VERIFY_CLIENT}" >> /etc/ldap/ldap.conf
    cp -f /etc/ldap/ldap.conf ${CONTAINER_SERVICE_DIR}/kdc/assets/ldap.conf

    [[ -f "$HOME/.ldaprc" ]] && rm -f $HOME/.ldaprc
    echo "TLS_CERT ${LDAP_TLS_CRT_PATH}" > $HOME/.ldaprc
    echo "TLS_KEY ${LDAP_TLS_KEY_PATH}" >> $HOME/.ldaprc
    cp -f $HOME/.ldaprc ${CONTAINER_SERVICE_DIR}/kdc/assets/.ldaprc
  fi

  #
  # remove container config files
  #
  if [[ X"${LDAP_REMOVE_CONFIG_AFTER_SETUP,,}" == X"true" ]]; then
    log-helper info "Remove config files..."
    rm -rf ${CONTAINER_SERVICE_DIR}/kdc/assets/config
  fi

  #
  # setup done :)
  #
  log-helper info "First start is done..."
  touch $FIRST_START_DONE
fi

ln -sf ${CONTAINER_SERVICE_DIR}/kdc/assets/.ldaprc $HOME/.ldaprc
ln -sf ${CONTAINER_SERVICE_DIR}/kdc/assets/ldap.conf /etc/ldap/ldap.conf

# force OpenLDAP to listen on all interfaces
ETC_HOSTS=$(cat /etc/hosts | sed "/$HOSTNAME/d")
echo "0.0.0.0 $HOSTNAME" ${HOSTNAME%%.*} > /etc/hosts
echo "$ETC_HOSTS" >> /etc/hosts
echo "$LDAP_HOSTNAME_IP $LDAP_HOSTNAME ${LDAP_HOSTNAME%%.*}" \
  | sed -e "s|\$LDAP_DOMAIN|$LDAP_DOMAIN|" >> /etc/hosts

exit 0
