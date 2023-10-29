ARG IMAGE_NAME="${IMAGE_NAME:-kinoite}"
ARG SOURCE_IMAGE="${SOURCE_IMAGE:-kinoite}"
ARG BASE_IMAGE="quay.io/fedora-ostree-desktops/${SOURCE_IMAGE}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-38}"

FROM fedora:38 AS akmods-builder

RUN dnf -y update && dnf -y install wget

RUN dnf -y install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Update cachebust in case a rebuild is required without usage of cache.
ARG CACHEBUST=9

RUN cd /etc/yum.repos.d/ && \
wget https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/repo/fedora-$(rpm -E %fedora)/bieszczaders-kernel-cachyos-fedora-$(rpm -E %fedora).repo && \
wget https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/repo/fedora-$(rpm -E %fedora)/bieszczaders-kernel-cachyos-addons-fedora-$(rpm -E %fedora).repo && cd /tmp

RUN dnf -y install kernel-cachyos-bore-eevdf kernel-cachyos-bore-eevdf-headers kernel-cachyos-bore-eevdf-devel kernel-cachyos-bore-eevdf-modules kernel-cachyos-bore-eevdf-core kernel-cachyos-bore-eevdf-devel-matched
RUN dnf -y install akmod-nvidia akmod-VirtualBox

COPY akmods.sh /tmp/akmods.sh
RUN /tmp/akmods.sh

FROM ${BASE_IMAGE}:${FEDORA_MAJOR_VERSION} AS builder

ARG IMAGE_NAME="${IMAGE_NAME}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION}"

# install RPM-fusion
RUN rpm-ostree install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

COPY --from=ghcr.io/ublue-os/akmods-nvidia:38-535 /rpms /tmp/akmods-rpms

RUN rpm-ostree install \
    /tmp/akmods-rpms/ublue-os/ublue-os-nvidia-addons-*.rpm

RUN mkdir /tmp/nvidia

COPY install-nvidia.sh /tmp/install-nvidia.sh

RUN cd /etc/yum.repos.d/ && wget https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos-addons/repo/fedora-$(rpm -E %fedora)/bieszczaders-kernel-cachyos-addons-fedora-$(rpm -E %fedora).repo

# add bore-sysctl and uksmd-lts
RUN rpm-ostree install bore-sysctl uksmd

# enable systemd services

RUN systemctl enable uksmd.service

COPY --from=akmods-builder /var/cache/akmods/*/* /tmp/nvidia

RUN cd /etc/yum.repos.d/ && \
wget https://copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos/repo/fedora-$(rpm -E %fedora)/bieszczaders-kernel-cachyos-fedora-$(rpm -E %fedora).repo && cd /tmp

# Enable cliwrap.
RUN rpm-ostree cliwrap install-to-root / && \
# Replace the kernel, kernel-core and kernel-modules packages.
rpm-ostree override remove kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra --install kernel-cachyos-bore-eevdf

# install kernel headers
RUN rpm-ostree override remove kernel-headers --install kernel-cachyos-bore-eevdf-headers

# install akmods
RUN ls /tmp/nvidia && /tmp/install-nvidia.sh

RUN rpm-ostree install \
    xorg-x11-drv-nvidia{,-cuda,-devel,-kmodsrc} \
    xorg-x11-drv-nvidia-libs.i686 \
    nvidia-container-toolkit supergfxctl supergfxctl-plasmoid

RUN mv /etc/nvidia-container-runtime/config.toml{,.orig}
RUN cp /etc/nvidia-container-runtime/config{-rootless,}.toml

RUN systemctl enable supergfxd.service

RUN rpm-ostree uninstall xorg-x11-drv-nvidia-power

RUN semodule --verbose --install /usr/share/selinux/packages/nvidia-container.pp
RUN ln -s /usr/bin/ld.bfd /etc/alternatives/ld
RUN ln -s /etc/alternatives/ld /usr/bin/ld
