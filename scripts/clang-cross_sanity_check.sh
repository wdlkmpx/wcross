#!/bin/bash
# Public Domain
#
# fix big x86_64 clang toolchain (4GB+) downloaded from the git repo

if [ -z "$XPATH" ] ; then
    echo "\$PATH is empty"
    exit 1
fi
if [ -z "$TARGET_TRIPLET" ] ; then
    echo "\$TARGET_TRIPLET is empty"
    exit 1
fi


get_sysroot_tarball()
{
    case ${TARGET_TRIPLET} in
        i686-*-freebsd11)    wurlx=https://sourceforge.net/projects/wdl/files/sysroot/freebsd/sysroot-freebsd11-i686.tar.xz    ;;
        x86_64-*-freebsd11)  wurlx=https://sourceforge.net/projects/wdl/files/sysroot/freebsd/sysroot-freebsd11-x86_64.tar.xz  ;;
        aarch64-*-freebsd11) wurlx=https://sourceforge.net/projects/wdl/files/sysroot/freebsd/sysroot-freebsd11-aarch64.tar.xz ;;
        aarch64-*musl*|aarch64-*linux*) wurlx=https://sourceforge.net/projects/wdl/files/sysroot/linux/sysroot-aarch64-linux-musl1.2.3-gcc11.2-static.tar.gz ;;
        *) exit_error "$TARGET_TRIPLET is not supported" ;;
    esac
}

#==================================================
# powerpc64-pc-freebsd11 is not supported by LLVM
# sparc64-pc-freebsd11   is not supported by LLVM
TARGETS='
i686-pc-freebsd11
x86_64-pc-freebsd11
aarch64-pc-freebsd11
'
#==================================================
create_symlinks()
{
    if [ ! -f ${XPATH}/bin/clang-target-wrapper.sh ] ; then
    echo '#!/bin/sh
#
# Copyright (c) 2018 Martin Storsjo
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

DIR="$(cd "$(dirname "$0")" && pwd)"
BASENAME="$(basename "$0")"
TARGET="${BASENAME%-*}"
EXE="${BASENAME##*-}"
ARCH="${TARGET%%-*}"
TARGET_OS="${TARGET##*-}"

# Check if trying to compile Ada; if we try to do this, invoking clang
# would end up invoking <triplet>-gcc with the same arguments, which ends
# up in an infinite recursion.
case "$*" in
*-x\ ada*) echo "Ada is not supported" >&2 ; exit 1 ;;
esac

# Allow setting e.g. CCACHE=1 to wrap all building in ccache.
if [ -n "$CCACHE" ]; then
    CCACHE=ccache
fi

# If changing this wrapper, change clang-target-wrapper.c accordingly.
CLANG="$DIR/clang"
FLAGS=""
FLAGS="$FLAGS --start-no-unused-arguments"
case $EXE in
clang++|g++|c++) FLAGS="$FLAGS --driver-mode=g++" ;;
c99) FLAGS="$FLAGS -std=c99" ;;
c11) FLAGS="$FLAGS -std=c11" ;;
esac

FLAGS="$FLAGS -target $TARGET"
if [ -f ${XPATH}/${TARGET_TRIPLET}/lib/libc++.a ] ; then
  FLAGS="$FLAGS -rtlib=compiler-rt"
  #FLAGS="$FLAGS -unwindlib=libunwind"
  FLAGS="$FLAGS -stdlib=libc++"
elif [ -f ${XPATH}/${TARGET_TRIPLET}/lib/libstdc++.a ] ; then
  FLAGS="$FLAGS -stdlib=libstdc++"
fi
FLAGS="$FLAGS -fuse-ld=lld"
FLAGS="$FLAGS --end-no-unused-arguments"

if [ -d ${XPATH}/${TARGET_TRIPLET}/includec++ ] ; then
  FLAGS="$FLAGS -isystem ${XPATH}/${TARGET_TRIPLET}/includec++"
fi

$CCACHE "$CLANG" $FLAGS "$@"
    
' > ${XPATH}/bin/clang-target-wrapper.sh
        chmod +x ${XPATH}/bin/clang-target-wrapper.sh
    fi

    if [ ! -e ${XPATH}/bin/llvm-addr2line ] ; then
        ln -sv llvm-symbolizer ${XPATH}/bin/llvm-addr2line
    fi

    i=${TARGET_TRIPLET}
    ln -sv llvm-addr2line ${XPATH}/bin/${i}-addr2line
    ln -sv llvm-ar ${XPATH}/bin/${i}-ar
    ln -sv llvm-nm ${XPATH}/bin/${i}-nm
    ln -sv clang-target-wrapper.sh ${XPATH}/bin/${i}-as
    ln -sv clang-target-wrapper.sh ${XPATH}/bin/${i}-c++
    ln -sv clang-target-wrapper.sh ${XPATH}/bin/${i}-clang
    ln -sv clang-target-wrapper.sh ${XPATH}/bin/${i}-clang++
    ln -sv clang-target-wrapper.sh ${XPATH}/bin/${i}-g++
    ln -sv clang-target-wrapper.sh ${XPATH}/bin/${i}-gcc
    ln -sv clang-target-wrapper.sh ${XPATH}/bin/${i}-cc
        
    ln -sv llvm-objcopy ${XPATH}/bin/${i}-objcopy
    ln -sv llvm-objdump ${XPATH}/bin/${i}-objdump
    ln -sv llvm-ranlib  ${XPATH}/bin/${i}-ranlib
    ln -sv llvm-readelf ${XPATH}/bin/${i}-readelf
    ln -sv llvm-strings ${XPATH}/bin/${i}-strings
    ln -sv llvm-strip   ${XPATH}/bin/${i}-strip
    ln -sv ld.lld ${XPATH}/bin/${i}-ld
}

delete_symlinks()
{
    rm -fv ${XPATH}/bin/clang-target-wrapper.sh
    rm -fv ${XPATH}/bin/llvm-addr2line
    for i in ${TARGETS}
    do
        rm -fv ${XPATH}/bin/${i}-addr2line
        rm -fv ${XPATH}/bin/${i}-ar
        rm -fv ${XPATH}/bin/${i}-nm
        rm -fv ${XPATH}/bin/${i}-as
        rm -fv ${XPATH}/bin/${i}-c++
        rm -fv ${XPATH}/bin/${i}-clang
        rm -fv ${XPATH}/bin/${i}-clang++
        rm -fv ${XPATH}/bin/${i}-g++
        rm -fv ${XPATH}/bin/${i}-gcc
        rm -fv ${XPATH}/bin/${i}-cc
        rm -fv ${XPATH}/bin/${i}-objcopy
        rm -fv ${XPATH}/bin/${i}-objdump
        rm -fv ${XPATH}/bin/${i}-ranlib
        rm -fv ${XPATH}/bin/${i}-readelf
        rm -fv ${XPATH}/bin/${i}-strings
        rm -fv ${XPATH}/bin/${i}-strip
        rm -fv ${XPATH}/bin/${i}-ld
    done
}

if [ -n "$CROSS_USE_SYSTEM_LIBS" ] ; then
    # this prefix uses the system libs and headers, only for testing small apps...
    if [ ! -d "${XPATH}/${TARGET_TRIPLET}" ] ; then
        mkdir -p ${XPATH}/${TARGET_TRIPLET}/bin
        mkdir -p ${XPATH}/${TARGET_TRIPLET}/lib
        mkdir -p ${XPATH}/${TARGET_TRIPLET}/include
        ln -sv . mkdir -p ${XPATH}/${TARGET_TRIPLET}/usr
    fi
elif [ ! -d "${XPATH}/${TARGET_TRIPLET}" ] ; then
    # setup sysroot for target triplet...
    get_sysroot_tarball
    fsbd_sysroot=$(basename "${wurlx}")
    #--
    mkdir -p ${XPATH}/${TARGET_TRIPLET}
    (
        if [ ! "$W_FUNC_IS_SOURCED" ] ; then
            . ${MWD}/func
        fi
        retrieve ${wurlx}
        cd ${XPATH}/${TARGET_TRIPLET}
        tar --strip-components=1 -xf ${MWD}/0sources/${fsbd_sysroot}
    ) || {
        rm -rf ${XPATH}/${TARGET_TRIPLET}
        exit 1
    }
fi

if [ ! -e "${XPATH}/bin/${TARGET_TRIPLET}-gcc" ] ; then
    create_symlinks
fi

#delete_symlinks

