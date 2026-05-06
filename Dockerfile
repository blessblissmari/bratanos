# Reproducible build environment for the BratanOS ISO.
# Lets non-Arch users build the ISO with `docker build` + `docker run`.
#
# Usage:
#   docker build -t bratanos-builder .
#   docker run --rm --privileged -v "$PWD":/build -w /build \
#       bratanos-builder make iso

FROM archlinux:latest

RUN pacman-key --init && \
    pacman -Syu --noconfirm && \
    pacman -S --noconfirm --needed \
        archiso \
        base-devel \
        git \
        sudo \
        squashfs-tools \
        libisoburn \
        dosfstools \
        e2fsprogs \
        erofs-utils \
        mtools \
        edk2-shell \
        syslinux \
        grub \
    && pacman -Scc --noconfirm

WORKDIR /build
CMD ["make", "iso"]
