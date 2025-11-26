#!/bin/bash
set -euo pipefail

# RLENV Build Script
# This script rebuilds the application from source located at /rlenv/source/l1vm/
#
# Original image: ghcr.io/mayhemheroes/l1vm:master
# Git revision: db7f1451e564523941f283a5b8da011b7782fd40

# ============================================================================
# Environment Variables
# ============================================================================
export CC=clang
export CCPP=clang++
export PATH=/root/bin:${PATH}
export LD_LIBRARY_PATH=/root/bin

# ============================================================================
# REQUIRED: Change to Source Directory
# ============================================================================
cd /rlenv/source/l1vm

# ============================================================================
# Clean Previous Build (recommended)
# ============================================================================
# Clean up old binaries to ensure fresh rebuild
rm -f assemb/l1asm 2>/dev/null || true
rm -f comp/l1com 2>/dev/null || true
rm -f prepro/l1pre 2>/dev/null || true
rm -f vm/l1vm vm/l1vm-nojit 2>/dev/null || true
rm -f /l1vm-nojit 2>/dev/null || true

# ============================================================================
# Build Commands (NO NETWORK, NO PACKAGE INSTALLATION)
# ============================================================================

# Fix MPFR module zerobuild config to add required preprocessor defines
sed -i 's/cflags = "-fPIC -O3 -fomit-frame-pointer -Wall"/cflags = "-fPIC -O3 -fomit-frame-pointer -Wall -DMPFR_USE_NO_MACRO -DMPFR_USE_INTMAX_T"/' \
    vm/modules/mpfr-c++/zerobuild.txt 2>/dev/null || true

echo "Building l1vm assembler..."
cd assemb
zerobuild force
cd ..

echo "Building l1vm compiler..."
cd comp
zerobuild force
cd ..

echo "Building l1vm preprocessor..."
cd prepro
zerobuild force
cd ..

echo "Building l1vm VM (no JIT)..."
cd vm
zerobuild zerobuild-nojit.txt force
cd ..

# Copy built binaries to ~/bin (for potential dependencies)
cp assemb/l1asm /root/bin/ 2>/dev/null || true
cp comp/l1com /root/bin/ 2>/dev/null || true
cp prepro/l1pre /root/bin/ 2>/dev/null || true
cp vm/l1vm* /root/bin/ 2>/dev/null || true

echo "Building modules..."
cd modules
chmod +x *.sh 2>/dev/null || true
./build.sh
./install.sh
cd ..

echo "Building programs..."
chmod +x *.sh 2>/dev/null || true
./build-all.sh || true

# ============================================================================
# Copy Artifacts (use 'cat >' for busybox compatibility)
# ============================================================================
echo "Copying build artifact to /l1vm-nojit..."
cat vm/l1vm-nojit > /l1vm-nojit

# ============================================================================
# Set Permissions
# ============================================================================
chmod 777 /l1vm-nojit 2>/dev/null || true

# ============================================================================
# REQUIRED: Verify Build Succeeded
# ============================================================================
if [ ! -f /l1vm-nojit ]; then
    echo "Error: Build artifact not found at /l1vm-nojit"
    exit 1
fi

# Verify executable bit
if [ ! -x /l1vm-nojit ]; then
    echo "Warning: Build artifact is not executable"
fi

# Verify file size is reasonable
SIZE=$(stat -c%s /l1vm-nojit 2>/dev/null || stat -f%z /l1vm-nojit 2>/dev/null || echo 0)
if [ "$SIZE" -lt 1000 ]; then
    echo "Error: Build artifact is suspiciously small ($SIZE bytes)"
    exit 1
fi

echo "Build completed successfully: /l1vm-nojit ($SIZE bytes)"
