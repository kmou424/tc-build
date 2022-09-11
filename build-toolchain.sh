#!/usr/bin/env bash

set -eo pipefail

# Function to show an informational message
function msg() {
    echo -e "\e[1;32m$@\e[0m"
}

# Build LLVM
msg "Building LLVM..."
./build-llvm.py \
	--clang-vendor "IceCream" \
        --install-folder "toolchain" \
	--targets "ARM;AArch64;X86" \
	--branch "release/15.x" \
	--shallow-clone \
	--projects "clang;lld;polly;bolt" \
	--lto "full" \
	--pgo "kernel-defconfig-slim" \
	--bolt \
	--defines "LLVM_PARALLEL_COMPILE_JOBS=$(nproc) LLVM_PARALLEL_LINK_JOBS=$(nproc) CMAKE_C_FLAGS=-O3 CMAKE_CXX_FLAGS=-O3"

# Build binutils
msg "Building binutils..."
if [ $(which clang) ] && [ $(which clang++) ]; then
	export CC=$(which ccache)" clang"
	export CXX=$(which ccache)" clang++"
	[ $(which llvm-strip) ] && stripBin=llvm-strip
else
	export CC=$(which ccache)" gcc"
	export CXX=$(which ccache)" g++"
	[ $(which strip) ] && stripBin=strip
fi
./build-binutils.py \
	--targets arm aarch64 x86_64
	--install-folder "toolchain"

# Remove unused products
msg "Removing unused products..."
rm -fr toolchain/include
rm -f toolchain/lib/*.a toolchain/lib/*.la toolchain/lib/clang/*/lib/linux/*.a*

# Strip remaining products
msg "Stripping remaining products..."
for f in $(find toolchain -type f -exec file {} \; | grep 'not stripped' | awk '{print $1}'); do
	strip ${f: : -1}
done

# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
msg "Setting library load paths for portability..."
for bin in $(find toolchain -mindepth 2 -maxdepth 3 -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}'); do
	# Remove last character from file output (':')
	bin="${bin: : -1}"

	echo "$bin"
	patchelf --set-rpath '$ORIGIN/../lib' "$bin"
done

msg "build-tc HEAD: $(git rev-parse HEAD)"
msg "binutils HEAD: $(git -C binutils/ rev-parse HEAD)"
msg "llvm-project HEAD: $(git -C llvm-project/ rev-parse HEAD)"
