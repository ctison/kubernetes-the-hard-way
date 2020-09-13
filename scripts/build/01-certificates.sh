#!/bin/bash
umask 0077
shopt -s nullglob
set -euo pipefail

# We use Certificate Signing Requests (CSR) to generate certificates.
# https://en.wikipedia.org/wiki/Certificate_signing_request

# Provision CA certificates for our PKI.
mkdir -p ssl && cd ssl
cat > config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF
cat <<EOF | cfssl gencert -config config.json -initca - | cfssljson -bare ca
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "Kubernetes The Hard Way",
      "OU": "ca"
    }
  ]
}
EOF

# There are the the kubernetes api's hostnames trusted by its certificate.
KUBERNETES_IPS=10.32.0.1,10.240.0.10,10.240.0.11,10.240.0.12,127.0.0.1
KUBERNETES_HOSTNAMES=$(echo kubernetes{,.default{,.svc{,.cluster{,.local}}}} | tr ' ' ','),$KUBERNETES_IPS

# Identities is an array of strings of the form "%s(USER) %s(GROUP) %s(HOSTNAMES)".
IDENTITIES=(
  'admin system:users'                                            # admin user
  'system:node:worker-0 system:nodes worker-0'                    # kubelet node 0
  'system:kube-controller-manager system:kube-controller-manager' # kubernetes controller manager
  'system:kube-proxy system:kube-proxy'                           # kubernetes proxy
  'system:kube-scheduler system:kube-scheduler'                   # kubernetes scheduler
  "kubernetes kubernetes $KUBERNETES_HOSTNAMES"                   # kubernetes api
  'service-accounts kubernetes'                                   # certificate used by k8s to generate service account tokens (not really an identity)
)

# Provision certificates for each identity.
for IDENTITY in "${IDENTITIES[@]}"; do
  # Split identity into user, group and hostnames.
  IFS=' ' read -r USER GROUP HOSTNAMES <<< "$IDENTITY"
  # Generate certificates
  # shellcheck disable=SC2046
  cat <<EOF | cfssl gencert \
    -ca=ca.pem \
    -ca-key=ca-key.pem \
    -config=config.json \
    -profile=kubernetes \
    $(if test "$HOSTNAMES" != ""; then echo -n "-hostname=$HOSTNAMES"; fi) \
    - | cfssljson -bare "$(echo "$USER" | rev | cut -d: -f1 | rev)"
{
  "CN": "$USER",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "Kubernetes The Hard Way",
      "OU": "$GROUP"
    }
  ]
}
EOF
done
