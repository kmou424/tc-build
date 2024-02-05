#!/usr/bin/env bash

set -eo pipefail

# Function to show an informational message
function msg() {
    echo -e "\e[1;32m$@\e[0m"
}

# Build LLVM
msg "Building LLVM..."
./build-llvm.py \
	--vendor-string "IceCream-$(date +%Y%m%d)" \
        --install-folder "toolchain" \
	--targets ARM AArch64 X86 \
	--ref "release/17.x" \
	--shallow-clone \
	--projects clang lld polly bolt \
	--pgo kernel-defconfig-slim \
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
	--targets arm aarch64 x86_64 \
	--install-folder "toolchain"

# Remove unused products
msg "Removing unused products..."
rm -fr toolchain/include
rm -f toolchain/lib/*.a toolchain/lib/*.la toolchain/lib/clang/*/lib/linux/*.a*

# Strip remaining products
msg "Stripping remaining products..."
IFS=$'\n'
for f in $(find toolchain -type f -exec file {} \;); do
	if [ -n "$(echo $f | grep 'ELF .* interpreter')" ]; then
		i=$(echo $f | awk '{print $1}'); i=${i: : -1}
		# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
		msg "Setting library load paths for portability..."
		if [ -d $(dirname $i)/../lib/ldscripts ]; then
			patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN/../lib' "$i"
		else
			if [ "$(patchelf --print-rpath $i)" != "\$ORIGIN/../../lib:\$ORIGIN/../lib" ]; then
				patchelf --set-rpath '$ORIGIN/../lib' "$i"
			fi
		fi
		# Strip remaining products
		if [ -n "$(echo $f | grep 'not stripped')" ]; then
			${stripBin} --strip-unneeded "$i"
		fi
	elif [ -n "$(echo $f | grep 'ELF .* relocatable')" ]; then
		if [ -n "$(echo $f | grep 'not stripped')" ]; then
			i=$(echo $f | awk '{print $1}');
			${stripBin} --strip-unneeded "${i: : -1}"
		fi
	else
		if [ -n "$(echo $f | grep 'not stripped')" ]; then
			i=$(echo $f | awk '{print $1}');
			${stripBin} --strip-all "${i: : -1}"
		fi
	fi
done

msg "build-tc HEAD: $(git rev-parse HEAD)"
msg "binutils HEAD: $(git -C src/binutils/ rev-parse HEAD)"
msg "llvm-project HEAD: $(git -C src/llvm-project/ rev-parse HEAD)"
