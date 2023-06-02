#!/usr/bin/env bash
set -euo pipefail

# Update the guest machine. This could take hours.
sudo apt-get update && sudo apt-get -y upgrade

# llvm Builds with cmake and we use clang to build it.
# Ubuntu ships with Clang 14 by default which is too old
# to use the Risc-V vector instructions so we need to build
# Clang 16.
sudo apt-get --assume-yes install cmake clang g++

# Download the LLVM project.
wget https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-16.0.0.tar.gz
tar -xzf llvmorg-16.0.0.tar.gz
mkdir llvm-project-llvmorg-16.0.0/build


# DLLVM_ENABLE_PROJECTS chooses which clang projects to enable. One possible option is
# 'all' which builds everything but when I tried this it failed with the following error
# regarding RISC-V:
#
#    libc build: Invalid or unknown libc compiler target triple: riscv
#
# Seems like it was having trouble building libc for some reason.
cmake -S llvm-project-llvmorg-16.0.0/llvm -B llvm-project-llvmorg-16.0.0/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_PROJECTS='clang;clang-tools-extra;lld;compiler-rt;lldb' \
        -DCMAKE_CXX_COMPILER=g++ \
        -DCMAKE_C_COMPILER=gcc

cmake --build llvm-project-llvmorg-16.0.0/build -j8

cmake --install llvm-project-llvmorg-16.0.0/build --prefix /usr/local