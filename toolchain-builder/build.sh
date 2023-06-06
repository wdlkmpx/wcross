#!/bin/bash
#
# Ideally this script should run inside a musl distro [chroot|container]
# to create smaller and portable cross-compilers
#

#set -x
#NATIVE=1  # (build a native compiler for TARGET, not a cross-compiler)

BINUTILS_VER=2.33.1  #2019-10-12
BINUTILS_VER=2.37    #2021-07-18
#BINUTILS_VER=2.38    #2022-02-09
#BINUTILS_VER=2.39    #2022-08-05
#BINUTILS_VER=2.40    #2023-01-16

GCC_VER=5.5.0   #2017-10-10 
GCC_VER=6.5.0   #2018-10-30
GCC_VER=7.5.0   #2019-11-14
GCC_VER=8.5.0   #2021-05-14
GCC_VER=9.5.0   #2022-05-27
GCC_VER=10.4.0  #2022-06-28
GCC_VER=11.3.0  #2022-04-21
#GCC_VER=12.2.0  #2022-08-19

GCC_MAJOR_VER=${GCC_VER%%.*}

SYSTEM_GCC_VER=$(gcc -dumpversion)
SYSTEM_GCC_MAJOR_VER=${SYSTEM_GCC_VER%%.*}

GMP_VER=5.1.3   #2013-10-30
GMP_VER=6.1.2   #2016-12-16
GMP_VER=6.2.1   #2020-11-14

MPFR_VER=3.1.6  #2017-09-17
MPFR_VER=4.0.2  #2019-01-31
MPFR_VER=4.1.1  #2020-11-17
MPFR_VER=4.2.0  #2023-01-06

MPC_VER=1.0.3   #2015-09-06
MPC_VER=1.1.0   #2018-01-11
MPC_VER=1.2.1   #2020-10-23
MPC_VER=1.3.1   #2022-12-16

ISL_VER=0.21    #2019-11-09
ISL_VER=0.24    #2021-05-01
if [ $SYSTEM_GCC_MAJOR_VER -ge 11 ] ; then
# https://github.com/firasuke/mussel/issues/11#issuecomment-1339523516
ISL_VER=0.25    #2022-07-02
fi

CLOOG_VER=0.18.5  #2017-04-27

MUSL_VER=1.2.3
#LINUX_VER=5.4.229
LINUX_VER=headers-5.4.229
MINGW_VER=v10.0.0

GNU_SITE=https://ftpmirror.gnu.org/gnu
GCC_SITE=https://ftpmirror.gnu.org/gnu/gcc
BINUTILS_SITE=https://ftpmirror.gnu.org/gnu/binutils
GMP_SITE=https://ftpmirror.gnu.org/gnu/gmp
MPC_SITE=https://ftpmirror.gnu.org/gnu/mpc
MPFR_SITE=https://ftpmirror.gnu.org/gnu/mpfr
ISL_SITE=https://libisl.sourceforge.io
#CLOOG_SITE=https://github.com/periscop/cloog/releases/download/cloog-${CLOOG_VER}

MUSL_SITE=https://musl.libc.org/releases
MUSL_REPO=git://git.musl-libc.org/musl

MINGW_SITE=https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release

#=====================================================================

# process args, set VAR=value
for i in $@
do
    case $i in
        *=*) echo $i ; eval "$i" ; shift ;;
        download|-download) DOWNLOAD_ONLY=1 ; shift ;;
        clean)
            rm -rf gcc-* binutils-* musl-* gmp-* mpc-* mpfr-* isl-* build build-* linux-* mingw-w64-*
            exit 0 ;;
        distclean)
            rm -f 0sources
            exit 0 ;;
    esac
done

#=====================================================================

export WDOWNLOAD_DIR=$(pwd)/0sources
export WSUMFILES_DIR=$(pwd)/hashes

exit_error() { echo -e "$@" ; exit 1 ; }

if [ -f ../functions.sh ] ; then
    . ../functions.sh
elif [ -f ./functions.sh ] ; then
    . ./functions.sh
else
    echo "Cannot find functions.sh"
    exit 1
fi

TOPDIR=`pwd`
REL_TOP=..

if [ -z "$TARGET" ] ; then
    # might want to override apps version in targets/xxx
    TARGET=$1
    if [ -f "$1" ] ; then
        . "$1"
    elif [ -f targets/${1} ] ; then
        . targets/${1}
    elif [ -f targets-extra/${1} ] ; then
        . targets-extra/${1}
    else
        echo "Valid targets:" 
        ls targets/
        exit 1
    fi
fi

if [ -f build.conf ] ; then
    . ./build.conf
fi

case ${TARGET} in
    *-*-*) ok=1 ;;
    *) echo "Invalid TARGET: ${TARGET}" ; exit ;;
esac
echo "  TARGET: ${TARGET}"

case ${TARGET} in
    *mingw*)
        unset MUSL_VER
        unset LINUX_VER
        unset SYSROOT_URL
        unset GLIBC_VER
        ;;
    *musl*)
        unset MINGW_VER
        unset SYSROOT_URL
        unset GLIBC_VER
        ;;
    *gnu*)
        unset MINGW_VER
        unset SYSROOT_URL
        unset MUSL_VER
        ;;
    *) # must be a BSD sysroot
        unset GLIBC_VER
        unset MUSL_VER
        unset LINUX_VER
        unset MINGW_VER
        if [ -z "$SYSROOT_URL" ] ; then
            echo "Must specify \$SYSROOT_URL"
            exit 1
        fi
        ;;
esac

BUILD=$(cc -dumpmachine)
if [ -z "$BUILD" ] ; then
    BUILD=$(gcc -dumpmachine)
fi

BUILD_TMP=${TOPDIR}/0buildtmp
BUILD_DIR=

if [ "${NATIVE}" ] ; then
    # - will compile a native compiler for target
    # - this requires a cross-compiler for target in order to
    #   compile the native compiler, the cc must already be in $PATH
    HOST=${TARGET}
    SYSROOT=/
    BUILD_DIR=${BUILD_TMP}/native_${TARGET}
    if [ "$INSTALL_ROOTDIR" ] ; then
        OUTPUT=${INSTALL_ROOTDIR}/${TARGET}-native
        PREFIX=${OUTPUT}
    else
        OUTPUT=${TOPDIR}/0output/${TARGET}-native
    fi
else
    # will compile a cross-compiler for target
    # $HOST might be set by build.conf
    #HOST=
    SYSROOT=/${TARGET}
    BUILD_DIR=${BUILD_TMP}/cross_${TARGET}
    if [ "$INSTALL_ROOTDIR" ] ; then
        OUTPUT=${INSTALL_ROOTDIR}/${TARGET}-cross
        PREFIX=${OUTPUT}
    else
        OUTPUT=${TOPDIR}/0output/${TARGET}-cross
    fi
fi
export PATH=${OUTPUT}/bin:${PATH}

echo "BUILD=${BUILD}"
echo "HOST=${HOST}"
echo "BUILD_DIR=${BUILD_DIR}"
echo
echo "GCC_VER  = $GCC_VER"
echo "GMP_VER  = $GMP_VER"
echo "MPFR_VER = $MPFR_VER"
echo "ISL_VER  = $ISL_VER"


#=====================================================================

if [ ! -e 0sources ] ; then
    if [ -f ../build.sh ] ; then # part of a bigger source tree
        mkdir -p ../0sources
        ln -sv ../0sources 0sources
    else
        mkdir -p 0sources
    fi
fi

#=====================================================================

download_file_and_check() # url
{
    download_file "$1"
    outf=$(basename "$1")
    if [ -f ${TOPDIR}/hashes/${outf}.sha1 ] ; then
        check_sum_file_by_ext ${TOPDIR}/hashes/${outf}.sha1
        if [ $? -ne 0 ] ; then
            exit 1
        fi
    fi
}


patch_dir() # $1:dir
{
    local dir=$1
    patchfiles=''
    if [ -f ${dir}/patches_applied ] ; then
        echo "$dir: patches have been already applied. delete dir to apply again"
        echo
        return 0
    fi
    if [ "$CONFIG_SUB" ] && [ -f ${dir}/config.sub ] ; then
        cp -av --remove-destination "$CONFIG_SUB" "${dir}/config.sub"
    fi
    # musl-cross-make sees any file as a patch, we'll go for '*.*'
    wcurdirx=$(pwd)
    cd ${dir}
    if [ -d ${TOPDIR}/patches/${dir} ] ; then
        apply_patches_from_dir ${TOPDIR}/patches/${dir}
    fi
    if [ -n "$MUSL_VER" ] && [ -d ${TOPDIR}/patches-musl/${dir} ] ; then
        apply_patches_from_dir ${TOPDIR}/patches-musl/${dir}
    elif [ -n "$MINGW_VER" ]  && [ -d ${TOPDIR}/patches-mingw/${dir} ] ; then
        apply_patches_from_dir ${TOPDIR}/patches-mingw/${dir}
    fi
    if [ "$WPATCHES_APPLIED" ] ; then
        printf "" > patches_applied
    fi
    cd ${wcurdirx}
    echo
}


extract_file() # $1:tarball
{
    local file=$1
    local dir=${file%.tar.*}  #extracted dir
    extract_archive "$file" "$dir"
    if [ "$LAST_EXTRACTED_FILE" ] ; then
        # patch directory
        patch_dir ${dir}
    fi
}

#=====================================================================

download_file_and_check ${GCC_SITE}/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz
download_file_and_check ${BINUTILS_SITE}/binutils-${BINUTILS_VER}.tar.xz
download_file_and_check ${GMP_SITE}/gmp-${GMP_VER}.tar.xz
download_file_and_check ${MPC_SITE}/mpc-${MPC_VER}.tar.gz
download_file_and_check ${MPFR_SITE}/mpfr-${MPFR_VER}.tar.xz
download_file_and_check ${ISL_SITE}/isl-${ISL_VER}.tar.xz
#download_file_and_check ${CLOOG_SITE}/cloog-${CLOOG_VER}.tar.gz
if [ -n "${MUSL_VER}" ] ; then
    download_file_and_check ${MUSL_SITE}/musl-${MUSL_VER}.tar.gz
fi
if [ -n "${MINGW_VER}" ] ; then
    download_file_and_check ${MINGW_SITE}/mingw-w64-${MINGW_VER}.tar.bz2
fi
if [ -n "${SYSROOT_URL}" ] ; then
    download_file_and_check ${SYSROOT_URL}
fi
if [ -n "$LINUX_VER" ] ; then
    set_linux_url ${LINUX_VER}
    download_file_and_check "$LINUX_URL"
fi

CONFIG_SUB=${TOPDIR}/0sources/config.sub
if [ ! -f ${CONFIG_SUB} ] ; then
    download_file_and_check https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.sub
    chmod +x ${CONFIG_SUB}
fi

if [ -n "$DOWNLOAD_ONLY" ] ; then
    echo
    echo "* All files downloaded. Finished"
    exit 0
fi

#=====================================================================

if [ ! -d ${BUILD_DIR} ] ; then
    mkdir -p ${BUILD_DIR}
fi
if [ ! -d ${OUTPUT} ] ; then
    mkdir -p ${OUTPUT}
fi

cd ${BUILD_TMP}

extract_file binutils-${BINUTILS_VER}.tar.xz
extract_file gcc-${GCC_VER}.tar.xz
extract_file gmp-${GMP_VER}.tar.xz
extract_file mpc-${MPC_VER}.tar.gz
extract_file mpfr-${MPFR_VER}.tar.xz
extract_file isl-${ISL_VER}.tar.xz
if [ -n "${MUSL_VER}" ] ; then
    extract_file musl-${MUSL_VER}.tar.gz
fi
if [ -n "${MINGW_VER}" ] ; then
    extract_file mingw-w64-${MINGW_VER}.tar.bz2
fi
if [ -n "${LINUX_VER}" ] ; then
    extract_file linux-${LINUX_VER}.tar.xz
fi
sync

#=====================================================================

# this variables will be used later
GCC_SRCDIR=${REL_TOP}/gcc-${GCC_VER}
BINUTILS_SRCDIR=${REL_TOP}/binutils-${BINUTILS_VER}
GMP_SRCDIR=${REL_TOP}/gmp-${GMP_VER}
MPC_SRCDIR=${REL_TOP}/mpc-${MPC_VER}
MPFR_SRCDIR=${REL_TOP}/mpfr-${MPFR_VER}
ISL_SRCDIR=${REL_TOP}/isl-${ISL_VER}
if [ -n "${MUSL_VER}" ] ; then
    MUSL_SRCDIR=${REL_TOP}/musl-${MUSL_VER}
fi
if [ -n "${LINUX_VER}" ] ; then
    LINUX_SRCDIR=${REL_TOP}/linux-${LINUX_VER}
fi
if [ -n "${MINGW_VER}" ] ; then
    MINGW_SRCDIR=${REL_TOP}/mingw-w64-${MINGW_VER}
fi
if [ -n "${SYSROOT_URL}" ] ; then
    echo -n # TODO
fi

#=====================================================================
#                              litecross
#=====================================================================

fn_export_autoconf_vars ${TARGET}

cd ${BUILD_DIR}
CURDIR=`pwd`

###
# build musl with this script
#
# 1. libgmp
# 2. libmpfr (dep: libgmp)
# 3. libmpc  (dep: libgmp, libmpfr)
# 4. libisl  (dep: libgmp)
# 5. gcc     (dep: libgmp, libmpfr, libmpc, libisl)

XGCC_DIR=../obj_gcc/gcc
XGCC="${XGCC_DIR}/xgcc -B ${XGCC_DIR}"
#XGCC="${XGCC_DIR}/xgcc -B ${XGCC_DIR} -B ${CURDIR}/obj_sysroot/${TARGET}/lib"
XCPP="${XGCC_DIR}/cpp -B ${XGCC_DIR}"
XAR=${CURDIR}/obj_binutils/binutils/ar
XAS=${CURDIR}/obj_binutils/gas/as-new
XRANLIB=${CURDIR}/obj_binutils/binutils/ranlib
XRC="${CURDIR}/obj_binutils/binutils/windres --preprocessor=${XGCC_DIR}/xgcc --preprocessor-arg=-B --preprocessor-arg=${XGCC_DIR} --preprocessor-arg=-I${CURDIR}/obj_sysroot/${TARGET}/include --preprocessor-arg=-E --preprocessor-arg=-xc-header --preprocessor-arg=-DRC_INVOKED -c 1252"
DLLTOOL=${CURDIR}/obj_binutils/binutils/dlltool

if [ "$HOST" ] ; then
    TOOLCHAIN_CONFIG+=" --build=${BUILD} --host=${HOST}"
fi

if [ ! "$MAKE" ] ; then
    MAKE='make'
fi

MAKE+=' MULTILIB_OSDIRNAMES='
MAKE+=' INFO_DEPS= infodir='
MAKE+=' ac_cv_prog_lex_root=lex.yy'
MAKE+=' MAKEINFO=false'

FULL_BINUTILS_CONFIG="${COMMON_CONFIG}
${TOOLCHAIN_CONFIG}
${BINUTILS_CONFIG}
--prefix=${PREFIX}
--target=${TARGET}
--with-sysroot=${SYSROOT}
--libdir=/lib
--disable-multilib
--disable-separate-code
--disable-werror
--disable-shared
--enable-static
--enable-deterministic-archives"

FULL_GCC_CONFIG="${GCC_LANGUAGES}
${COMMON_CONFIG}
${TOOLCHAIN_CONFIG}
${GCC_CONFIG}
--disable-bootstrap
--disable-assembly
--disable-werror
--target=${TARGET}
--prefix=${PREFIX}
--libdir=/lib
--disable-multilib
--with-sysroot=${SYSROOT}
--enable-tls
--disable-libmudflap
--disable-libsanitizer
--disable-gnu-indirect-function
--disable-libmpx
--enable-initfini-array
--enable-libstdcxx-time=rt
${GCC_CONFIG_FOR_TARGET}"

FULL_MINGW_HEADERS_CONFIG="${MINGW_CONFIG}
${MINGW_HEADERS_CONFIG}
--prefix=
--host=${TARGET}
--enable-sdk=all
--enable-idl
--enable-secure-api
--with-sysroot=${SYSROOT}"

FULL_MINGW_CRT_CONFIG="${MINGW_CONFIG}
${MINGW_CRT_CONFIG}
--prefix=
--host=${TARGET}
--with-sysroot=${SYSROOT}"

FULL_MINGW_PTHREADS_CONFIG="${MINGW_CONFIG}
--prefix=
--host=${TARGET}
--with-sysroot=${SYSROOT}"

if [ ! "$NATIVE" ] ; then
    # cross
    FULL_GCC_CONFIG+=" --with-build-sysroot=${CURDIR}/obj_sysroot
AR_FOR_TARGET=${PWD}/obj_binutils/binutils/ar
AS_FOR_TARGET=${PWD}/obj_binutils/gas/as-new
LD_FOR_TARGET=${PWD}/obj_binutils/ld/ld-new
NM_FOR_TARGET=${PWD}/obj_binutils/binutils/nm-new
OBJCOPY_FOR_TARGET=${PWD}/obj_binutils/binutils/objcopy
OBJDUMP_FOR_TARGET=${PWD}/obj_binutils/binutils/objdump
RANLIB_FOR_TARGET=${PWD}/obj_binutils/binutils/ranlib
READELF_FOR_TARGET=${PWD}/obj_binutils/binutils/readelf
STRIP_FOR_TARGET=${PWD}/obj_binutils/binutils/strip-new
"
    MUSL_CONFIG+=" CC=${XGCC} LIBCC=../obj_gcc/${TARGET}/libgcc/libgcc.a"
    MUSL_MAKE_VARS="AR=../obj_binutils/binutils/ar RANLIB=../obj_binutils/binutils/ranlib"
else
    # native
    MUSL_MAKE_VARS=
fi

#=====================================================================
# create symlinks and dirs

if [ ! -e src_binutils ] ; then
    ln -sfv ${BINUTILS_SRCDIR} src_binutils
    mkdir -p obj_binutils
fi

if [ ! -e src_gcc_base ] ; then
    ln -sfv ${GCC_SRCDIR} src_gcc_base
fi

if [ -n "${MUSL_SRCDIR}" ] && [ ! -e src_musl ] ; then
    ln -sfv ${MUSL_SRCDIR} src_musl
    mkdir -p obj_musl
fi

if [ -n "${MINGW_SRCDIR}" ] && [ ! -e src_mingw ] ; then
    ln -sfv ${MINGW_SRCDIR} src_mingw
    mkdir -p obj_mingw
fi

[ ! -e src_gmp ]  && ln -sfv ${GMP_SRCDIR} src_gmp
[ ! -e src_mpc ]  && ln -sfv ${MPC_SRCDIR} src_mpc
[ ! -e src_mpfr ] && ln -sfv ${MPFR_SRCDIR} src_mpfr
[ ! -e src_isl ]  && ln -sfv ${ISL_SRCDIR} src_isl

if [ ! -d src_gcc ] ; then
    mkdir -p obj_gcc
    mkdir -p src_gcc
    ( #subshell
    cd src_gcc
    ln -sf ../src_gcc_base/* . 
    # symlink to gmp, mpc, mpfr and isl inside the gcc sources
    # this way there's no need to compile them indidually
    ln -sf ../src_gmp gmp
    ln -sf ../src_mpc mpc
    ln -sf ../src_mpfr mpfr
    ln -sf ../src_isl isl
    ) #end-of-subshell
fi

#=====================================================================
# configure and compile

mkdir -p ${OUTPUT}

# 1. kernel headers
if [ -n "${SYSROOT_URL}" ] ; then
    if [ ! -f ${OUTPUT}/${TARGET}/lib/libc.a ] ; then
        # sysroot already includes libc, headers, etc
        SYSROOT_TARBALL=$(basename "${SYSROOT_URL}")
        SYSROOT_DIR=${SYSROOT_TARBALL%.tar.*}
        cd ${OUTPUT}
        extract_file ${SYSROOT_TARBALL}
        mv ${SYSROOT_DIR} ${TARGET}
        cd ${BUILD_DIR}
    fi

elif [ -n "${LINUX_SRCDIR}" ] ; then
    if [ ! -d ${OUTPUT}${SYSROOT}/include/linux ] ; then
        cd ${LINUX_SRCDIR}
        install_linux_headers ${TARGET} ${OUTPUT}${SYSROOT}
        cd ${BUILD_DIR}
    fi
fi


# 2. binutils
if [ ! -f obj_binutils/binutils/ar ] ; then # obj_binutils/Makefile
    #-- Makefile: recipe for target 'all-bfd' failed
    sed -i 's%doc po%%' src_binutils/bfd/Makefile.in
    sed -i '/SUBDIRS = po/d' $(find src_binutils/ -maxdepth 2 -name Makefile.in)
    #--
    cmd_echo cd obj_binutils
    cmd_echo ../src_binutils/configure ${FULL_BINUTILS_CONFIG}
    cmd_echo ${MAKE} all
    cmd_echo ${MAKE} DESTDIR=${OUTPUT} install
    cmd_echo cd ..
fi


# 3. gcc
if [ ! -f obj_gcc/Makefile ] ; then
    #-- reduce build time/fix possible issues by not building unneeded stuff
    sed -i -e '/DIST_SUBDIRS/d' -e 's%SUBDIRS = .*%SUBDIRS = .%' src_isl/Makefile.in
    sed -i -e 's% tests%%' -e 's% doc%%' src_gmp/Makefile.in
    sed -i -e 's% tests doc tools%%' src_mpc/Makefile.in
    sed -i -e 's%doc src tests tune tools/bench%src%' src_mpfr/Makefile.in
    sed -i -e 's%testsuite man%%' src_gcc/libffi/Makefile.in
    sed -i -e 's%doc po testsuite%%' src_gcc/libstdc++-v3/Makefile.in
    sed -i -e 's% testsuite%%' \
       src_gcc/libatomic/Makefile.in \
       src_gcc/libitm/Makefile.in \
       src_gcc/libiberty/Makefile.in \
       src_gcc/libphobos/Makefile.in \
       src_gcc/libgo/Makefile.in \
       src_gcc/libgomp/Makefile.in \
       src_gcc/libvtv/Makefile.in
    #--
    cmd_echo cd obj_gcc
    cmd_echo ../src_gcc/configure ${FULL_GCC_CONFIG}
    cmd_echo cd ..
fi

exit ######

if [ ! -f obj_gcc/gcc/.lc_built ] ; then
    cd obj_gcc
    cmd_echo ${MAKE} all-gmp
    cmd_echo ${MAKE} all-mpfr
    cmd_echo ${MAKE} all-mpc
    cmd_echo ${MAKE} all-isl
    cmd_echo ${MAKE} all-gcc
    cd ..
    printf "" > obj_gcc/gcc/.lc_built
fi

# 4. libc
mkdir -p obj_sysroot

if [ -n "$MUSL_VER" ] && [ ! -f obj_musl/.lc_configured ] ; then
    # *** musl doesn't use or require linux headers ***
    cmd_echo cd obj_musl
    cmd_echo ../src_musl/configure ${MUSL_CONFIG} \
        --prefix=${PREFIX} \
        --host=${TARGET}
    cmd_echo ${MAKE} DESTDIR=${CURDIR}/obj_sysroot install-headers
    cmd_echo cd ..
    printf "" > obj_musl/.lc_configured
    printf "" > obj_sysroot/.lc_headers

elif [ -n "${MINGW_VER}" ] && [ ! -f obj_mingw_headers/.lc_configured ] ; then
    mkdir -p obj_mingw_headers
    cmd_echo cd obj_mingw_headers
    cmd_echo ${MAKE} DESTDIR=${CURDIR}/obj_sysroot/${TARGET} install
    cmd_echo rm -f ${CURDIR}/obj_sysroot/mingw
    cmd_echo ln -s ${TARGET} ${CURDIR}/obj_sysroot/mingw
    cmd_echo cd ..
    printf "" > obj_mingw_headers/.lc_configured
    printf "" > obj_sysroot/.lc_headers
fi


# 5. gcc
if [ ! -f obj_gcc/${TARGET}/libgcc/libgcc.a ] ; then
    cmd_echo cd obj_gcc
    cmd_echo ${MAKE} enable_shared=no all-target-libgcc
    cmd_echo cd ..
fi

if [ -n "$MUSL_VER" ] && [ ! -f obj_musl/.lc_built ] ; then
    cmd_echo cd obj_musl
    cmd_echo ${MAKE} ${MUSL_MAKE_VARS}
    cmd_echo ${MAKE} ${MUSL_MAKE_VARS} DESTDIR=${CURDIR}/obj_sysroot install
    cmd_echo ${MAKE} ${MUSL_MAKE_VARS} DESTDIR=${OUTPUT}${SYSROOT} install
    cmd_echo cd ..
    printf "" > obj_musl/.lc_built
    printf "" > obj_sysroot/.lc_libs
fi

if [ ! -f obj_gcc/.lc_built ] ; then #???
    cmd_echo cd obj_gcc
    cmd_echo ${MAKE}
    cmd_echo ${MAKE} DESTDIR=${OUTPUT} install
    cmd_echo ln -sf ${TARGET}-gcc ${OUTPUT}/bin/${TARGET}-cc
    cmd_echo cd ..
    printf "" > obj_gcc/.lc_built
fi

#=====================================================================

echo
echo "-----------------"
echo "post process"

( # subshell
cd ${OUTPUT}
dedup_toolchain_apps ${TARGET}
)

