#!/bin/bash
umask 0077
shopt -s nullglob
set -euo pipefail

mkdir -p kubeconfigs && cd kubeconfigs

# Identities is an array of strings of the form "%s(USER) %s(GROUP) %s(HOSTNAMES)".
IDENTITIES=(
  'admin'                   # admin user
  'worker-0'                # kubelet node 0
  'kube-controller-manager' # kubernetes controller manager
  'kube-proxy'              # kubernetes proxy
  'kube-scheduler'          # kubernetes scheduler
  "kubernetes"              # kubernetes api
)

# Generate a kubeconfig for each identity.
for IDENTITY in "${IDENTITIES[@]}"; do
  # Set the cluster.
  kubectl --kubeconfig="$IDENTITY".kubeconfig config set-cluster kubernetes-the-hard-way \
    --certificate-authority=../ssl/ca.pem \
    --embed-certs=true \
    --server=https://kubernetes:6443
  # Set the user.
  kubectl --kubeconfig="$IDENTITY".kubeconfig config set-credentials "$IDENTITY" \
    --client-certificate=../ssl/"$IDENTITY".pem \
    --client-key=../ssl/"$IDENTITY"-key.pem \
    --embed-certs=true
  # Set the context binding the cluster and the user.
  kubectl --kubeconfig="$IDENTITY".kubeconfig config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user="$IDENTITY"
  # Set the default context.
  kubectl --kubeconfig="$IDENTITY".kubeconfig config use-context default
done
