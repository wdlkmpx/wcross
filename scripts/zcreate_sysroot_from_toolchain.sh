#!/bin/sh
# Public Domain
#
# run inside toolchain and export XPATH
#   or specify dir as a param in the command line
# only gcc toolchains qualify
#

XPATH="$1"

if [ -z "$XPATH" ] ; then
    echo "syntax: $0 <DIR>"
    exit 1
fi
if [ ! -d "$XPATH" ] ; then
    echo "$XPATH is not a directory"
    exit 1
fi

CWD=$(pwd)
cd "$XPATH"

#===================================================

if [ -z "$TARGET_TRIPLET" ] ; then
    TARGET_TRIPLET=$(ls -d *-*-* | head -1)
    TARGET_TRIPLET=${TARGET_TRIPLET##*/} # basename
fi

if [ -z "$TARGET_TRIPLET" ] ; then
    echo "\$TARGET_TRIPLET is empty"
    exit 1
fi

if [ ! -e ${TARGET_TRIPLET}/bin/as ] ; then
    echo "This doesn't look like a gcc toolchain"
    exit 1
fi

#===================================================

# ggc version can be found in include/c++/
# example: aarch64-linux-musl/include/c++/11.2.1
GCC_VERSION=$(ls ${TARGET_TRIPLET}/include/c++)
if [ -z "$GCC_VERSION" ] ; then
    echo "Could not determine GCC version, toolchain not suitable"
    exit 1
fi
echo "GCC_VERSION: $GCC_VERSION"

#===================================================

pdir=${CWD}/sysroot-${TARGET_TRIPLET}-${GCC_VERSION}
mkdir -p ${pdir}

if [ ! -e ${pdir}/include ] ; then
    cp -a ${TARGET_TRIPLET}/* ${pdir}
    #rm -rf ${pdir}/bin/* ${pdir}/sbin/* ${pdir}/share/*
    rm -rf ${pdir}/bin ${pdir}/sbin ${pdir}/share

    libgcc=$(find lib -name 'libgcc.a')
    cc1=$(find . -name 'cc1')
    for i in ${libgcc} ${cc1}
    do
        gccdir=$(dirname "$i")
        cp -av ${gccdir}/*.a ${gccdir}/*.o ${gccdir}/*.so ${pdir}/lib
        sync
    done
fi

# create special symlink: includec++
if [ ! -e ${pdir}/includec++ ] ; then
    ln -sv include/c++/${GCC_VERSION} ${pdir}/includec++
fi

# includec++ must contain all the C++ headers
# remove include/c++/${GCC_VERSION}/${TARGET_TRIPLET}
#    example: aarch64-linux-musl/include/c++/11.2.1/aarch64-linux-musl
if [ -d ${pdir}/include/c++/${GCC_VERSION}/${TARGET_TRIPLET} ] ; then
    cp -af ${pdir}/include/c++/${GCC_VERSION}/${TARGET_TRIPLET}/* ${pdir}/include/c++/${GCC_VERSION}/
    sync
    rm -rfv ${pdir}/include/c++/${GCC_VERSION}/${TARGET_TRIPLET}
fi

# remove unwanted libs
rm -fv ${pdir}/lib/libgfortran*
# la files are no needed
rm -fv ${pdir}/lib/*.la

if [ ! -f ${pdir}/lib/libgcc.a ] ; then
    echo "ERROR: lib/libgcc.a is missing"
    exit 1
fi

echo "Done"
echo
