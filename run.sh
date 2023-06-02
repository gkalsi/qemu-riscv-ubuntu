#!/usr/bin/env bash
set -euo pipefail

# NOTE:
# Install prerequisites on Ubuntu:
# 
#    $ sudo apt install libslirp-dev gcc-riscv64-linux-gnu
# 

ARTIFACTS_ROOT_DIR="artifacts"

# Create the artifacts root dir if it's not there already.
if [ ! -d "$ARTIFACTS_ROOT_DIR" ]; then
    mkdir -p "$ARTIFACTS_ROOT_DIR"
fi

cd $ARTIFACTS_ROOT_DIR

# Download and build fresh QEMU binaries if they don't already exist.
QEMU_TAR_URL="https://download.qemu.org/qemu-8.0.0-rc4.tar.xz"
QEMU_TAR="qemu-8.0.0-rc4.tar.xz"
QEMU_DIRECTORY="./qemu-8.0.0-rc4"
QEMU_BINARY="$QEMU_DIRECTORY/build/qemu-system-riscv64"
QEMU_IMG="$QEMU_DIRECTORY/build/qemu-img"
if ! [ -f $QEMU_BINARY ]; then
    # The binary doesn't exist, we need to build it.
    if ! [ -d $QEMU_DIRECTORY ]; then
        # The folder doesn't exist, we need to untar it.
        if ! [ -f $QEMU_TAR ]; then
            # The archive doesn't exist at all, we need to download it.
            wget $QEMU_TAR_URL
        fi
        tar xvJf qemu-8.0.0-rc4.tar.xz
    fi
    pushd qemu-8.0.0-rc4
    ./configure --enable-slirp
    make -j$(nproc)
    popd
fi


# Download and build U-Boot if it doesn't already exist.
U_BOOT_REMOTE="https://github.com/u-boot/u-boot.git"
U_BOOT_DIRECTORY="./u-boot"
U_BOOT_BIN="$U_BOOT_DIRECTORY/u-boot.bin"
if ! [ -f $U_BOOT_BIN ]; then
    if ! [ -d $U_BOOT_DIRECTORY ]; then
        git clone $U_BOOT_REMOTE
    fi
    export CROSS_COMPILE="riscv64-linux-gnu-"
    pushd $U_BOOT_DIRECTORY
    make qemu-riscv64_smode_defconfig # builds supervisor mode binaries, use qemu-riscv64_defconfig for regular
    make -j$(nproc)
    popd
fi


# Download Ubuntu if it doesn't already exist.
UBUNTU_REMOTE="https://cdimage.ubuntu.com/releases/22.04.2/release/ubuntu-22.04.2-preinstalled-server-riscv64+unmatched.img.xz"
UBUNTU_IMG="ubuntu-22.04.2-riscv64.img"
UBUNTU_QCOW=${UBUNTU_IMG/.img/.qcow2}
UBUNTU_IMG_XZ="$UBUNTU_IMG.xz"
if ! [ -f $UBUNTU_IMG ]; then
    if ! [ -f $UBUNTU_IMG_XZ ]; then
        wget $UBUNTU_REMOTE -O $UBUNTU_IMG_XZ
    fi
    echo "Decompressing..."
    xz -dk $UBUNTU_IMG_XZ
fi

# The default preinstalled image reserves ~4.2GiB for the disk.
# The actual disk is about ~2.xGiB used on boot which isn't really
# large enough to do anything useful.
# Even a single `apt update && apt upgrade` will fill up the disk
# so we convert the disk image to a QCOW2 QEMU disk image and adjust
# the capacity to some large number.
if ! [ -f $UBUNTU_QCOW ]; then
    $QEMU_IMG convert $UBUNTU_IMG $UBUNTU_QCOW
    $QEMU_IMG resize $UBUNTU_QCOW 30G
    $QEMU_IMG info $UBUNTU_QCOW
fi


# Start 'er up
$QEMU_BINARY -machine virt -m 8G -smp cpus=8 -nographic        \
    -cpu rv64,v=true,zba=true,zbb=true,vlen=512,vext_spec=v1.0 \
    -kernel $U_BOOT_BIN                                        \
    -device virtio-rng-pci                                     \
    -device virtio-net-device,netdev=net0                      \
    -netdev user,id=net0,hostfwd=tcp::5555-:22                 \
    -drive file=$UBUNTU_QCOW,format=raw,if=virtio

# Generate a set of keys to use to communicate with the host.
ssh-keygen -f ./$ARTIFACTS_ROOT_DIR/id_rsa -t ed25519

# Copy the generated SSH certificate to the QEMU machine.
# TODO(gkalsi): 
sshpass -ffilename default_password.txt scp -P 5555 -o StrictHostKeyChecking=no ./$ARTIFACTS_ROOT_DIR/id_rsa.pub ubuntu@localhost:~/.ssh/authorized_keys

# SSH into the target machine.
scp -i ./id_rsa -P 5555 ./bootstrap_guest.sh ubuntu@localhost:~/bootstrap_guest.sh

ssh -i ./id_rsa -p 5555 ubuntu@localhost -t 'bash ~/bootstrap_guest.sh'
