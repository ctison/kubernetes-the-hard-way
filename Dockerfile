# renovate: kubernetes/kubernetes
ARG KUBERNETES_VERSION='v1.19.1'

FROM ubuntu:20.10@$sha256:bb03a3e24da9704fc94ff11adbbfd9c93bb84bfab6fd57c9bab3168431a1d1ff as base

SHELL [ "/bin/bash", "--norc", "--noprofile", "-euxo", "pipefail", "-O", "nullglob", "-c" ]
ENV LANG C.UTF-8

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
  apt-get install --no-install-recommends -y ca-certificates curl && \
  rm -rf -- /var/lib/apt/lists/

#
# Kubectl
#
FROM base as kubectl

ARG KUBERNETES_VERSION="${KUBERNETES_VERSION}"
WORKDIR /usr/local/bin/
RUN curl -fLO kubectl https://storage.googleapis.com/kubernetes-release/release/"$KUBECTL_VERSION"/bin/linux/amd64/kubectl
RUN chmod 500 kubectl

#
# Build configs
#
FROM kubectl as build

# Install cfssl (Cloudflare SSL).
ARG CFSSL_VERSION='v1.4.1'
WORKDIR /usr/local/bin/
RUN curl -fLo cfssl https://github.com/cloudflare/cfssl/releases/download/v"$CFSSL_VERSION"/cfssl_"$CFSSL_VERSION"_linux_amd64
RUN curl -fLo cfssljson https://github.com/cloudflare/cfssl/releases/download/v"$CFSSL_VERSION"/cfssljson_"$CFSSL_VERSION"_linux_amd64
RUN chmod 500 cfssl{,json}

WORKDIR /build/
COPY /scripts/buid/ ./

# Generate a certificate for each identity in our cluster.
# https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/04-certificate-authority.md
RUN bash 01-certificates.sh

# Generate a kubeconfig for each identity in our cluster.
# https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/05-kubernetes-configuration-files.md
RUN bash 02-kubeconfigs.sh

# Generate the data encryption key used by kubernetes to encrypt data at rest.
# https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/06-data-encryption-keys.md
RUN bash 03-data-encryption-key.sh

#
# ETCD
# https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/07-bootstrapping-etcd.md
FROM base as etcd

ARG ETCD_VERSION='v3.3.25'
WORKDIR /usr/local/bin/
RUN curl -LO https://github.com/etcd-io/etcd/releases/download/v"$ETCD_VERSION"/etcd-v"$ETCD_VERSION"-linux-amd64.tar.gz && \
  tar --no-same-{o,p} --strip=1 -xf etcd-v"$ETCD_VERSION"-linux-amd64.tar.gz etcd-v"$ETCD_VERSION"-linux-amd64/etcd{,ctl} && \
  chmod 500 etcd{,ctl} && \
  rm etcd-v"$ETCD_VERSION"-linux-amd64.tar.gz

RUN mkdir -p mkdir -p /etc/etcd /var/lib/etcd
COPY --from=build /build/ssl/ca.pem /build/ssl/kubernetes-key.pem /build/ssl/kubernetes.pem /etc/etcd/
ENTRYPOINT [ "/usr/local/bin/etcd"]

##############################################################################
# Worker Node Components
# https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/08-bootstrapping-kubernetes-controllers.md

#
# Kubernetes API server
#
FROM kubectl as kube-apiserver

ARG KUBERNETES_VERSION="${KUBERNETES_VERSION}"
WORKDIR /usr/local/bin/
RUN curl -fLo https://storage.googleapis.com/kubernetes-release/release/"$KUBERNETES_VERSION"/bin/linux/amd64/kube-apiserver
RUN chmod 500 kube-apiserver

WORKDIR /var/lib/kubernetes/
COPY --from=build /build/ssl/ca.pem /build/ssl/ca-key.pem ./
COPY --from=build /build/ssl/kubernetes.pem /build/ssl/kubernetes-key.pem ./
COPY --from=build /build/ssl/service-account.pem /build/ssl/service-account-key.pem ./
COPY --from=build /build/configs/encryption.yaml ./

# Add the kubeconfigs.
COPY --from=build /build/kubeconfigs/admin.kubeconfig ~/
COPY --from=build /build/kubeconfigs/kube-controller-manager.kubeconfig ~/
COPY --from=build /build/kubeconfigs/kube-scheduler.kubeconfig ~/

#
# Kubernetes Controller Manager
#
FROM kubectl as kube-controller-manager

ARG KUBERNETES_VERSION="${KUBERNETES_VERSION}"
WORKDIR /usr/local/bin/
RUN curl -fLO https://storage.googleapis.com/kubernetes-release/release/"$KUBERNETES_VERSION"/bin/linux/amd64/kube-controller-manager
RUN chmod 500 kube-controller-manager

#
# Kubernetes Scheduler
#
FROM kubectl as kube-scheduler

ARG KUBERNETES_VERSION="${KUBERNETES_VERSION}"
WORKDIR /usr/local/bin/
RUN curl -fLO https://storage.googleapis.com/kubernetes-release/release/"$KUBERNETES_VERSION"/bin/linux/amd64/kube-scheduler
RUN chmod 500 kube-scheduler

##############################################################################
# Worker Node Components
# https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/09-bootstrapping-kubernetes-workers.md

#
# ContainerD
# 
FROM kubectl as containerd

#
# Kubelet
#
FROM kubectl as kubelet

#
# Kubernetes Proxy
#
FROM kubectl as kube-proxy
