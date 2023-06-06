#!/bin/bash
# Public Domain
#

help()
{
    echo "syntax:
  $0 <sysroot>

  sysroot can be:
        freebsd|netbsd|openbsd

  specific versions:
        freebsd11 freebsd12 freebsd13
        openbsd7
        netbsd9
"
    exit 1
}

#==================================================================

wget='wget --no-check-certificate -c'

# FreeBSD, releases are moved to the archive after some time
#   https://download.freebsd.org/releases
#   http://ftp-archive.freebsd.org/pub/FreeBSD/releases
#   http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases
# 
# https://cdn.openbsd.org/pub/OpenBSD/
# https://ftp.netbsd.org/pub/NetBSD/

freebsd10='
i686|freebsd10|http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/i386/10.4-RELEASE/base.txz
#x86_64|freebsd10|http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/amd64/10.4-RELEASE/base.txz
'

freebsd11='
i686|freebsd11|http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/i386/11.4-RELEASE/base.txz
x86_64|freebsd11|http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/amd64/11.4-RELEASE/base.txz
aarch64|freebsd11|http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/arm64/11.4-RELEASE/base.txz
####_powerpc64_sparc64_use_gcc4.2.1_-_not_compatible_with_clang
###powerpc64|freebsd11|http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/powerpc/11.4-RELEASE/base.txz
###sparc64|freebsd11|http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/sparc64/11.4-RELEASE/base.txz'
# powerpc64-pc-freebsd11 is not supported by LLVM
# sparc64-pc-freebsd11   is not supported by LLVM

freebsd12='
i686|freebsd12|https://download.freebsd.org/releases/i386/12.4-RELEASE/base.txz
x86_64|freebsd12|https://download.freebsd.org/releases/amd64/12.4-RELEASE/base.txz
aarch64|freebsd12|https://download.freebsd.org/releases/arm64/12.4-RELEASE/base.txz
#ppc|freebsd12|https://download.freebsd.org/releases/powerpc/powerpc/12.4-RELEASE/base.txz
#ppc64|freebsd12|https://download.freebsd.org/releases/powerpc/powerpc64/12.4-RELEASE/base.txz
###sparc64|freebsd12|https://download.freebsd.org/releases/sparc64/12.4-RELEASE/base.txz'

freebsd13='
i686|freebsd13|http://ftp-archive.freebsd.org/pub/FreeBSD/releases/i386/13.1-RELEASE/base.txz
x86_64|freebsd13|http://ftp-archive.freebsd.org/pub/FreeBSD/releases/amd64/13.1-RELEASE/base.txz
aarch64|freebsd13|http://ftp-archive.freebsd.org/pub/FreeBSD/releases/arm64/13.1-RELEASE/base.txz
##riscv64|freebsd13|http://ftp-archive.freebsd.org/pub/FreeBSD/releases/riscv/riscv64/13.1-RELEASE/base.txz
##ppc|freebsd13|http://ftp-archive.freebsd.org/pub/FreeBSD/releases/powerpc/powerpc/13.1-RELEASE/base.txz
##ppc64|freebsd13|http://ftp-archive.freebsd.org/pub/FreeBSD/releases/powerpc/powerpc64/13.1-RELEASE/base.txz
##ppc64le|freebsd13|http://ftp-archive.freebsd.org/pub/FreeBSD/releases/powerpc/powerpc64le/13.1-RELEASE/base.txz
##ppcspe|freebsd13|http://ftp-archive.freebsd.org/pub/FreeBSD/releases/powerpc/powerpcspe/13.1-RELEASE/base.txz
'

freebsd14='
'

openbsd7='
x86_64|openbsd7|https://cdn.openbsd.org/pub/OpenBSD/7.1/amd64/base71.tgz@https://cdn.openbsd.org/pub/OpenBSD/7.1/amd64/comp71.tgz
'

netbsd9='
x86_64|netbsd9|https://ftp.netbsd.org/pub/NetBSD/NetBSD-9.3/amd64/binary/sets/base.tar.xz@https://ftp.netbsd.org/pub/NetBSD/NetBSD-9.3/amd64/binary/sets/comp.tar.xz
'

freebsd=
openbsd="${openbsd7}"
netbsd="${netbsd9}"

case $1 in
    freebsd10) sysroots="${freebsd10}" ;;
    freebsd11) sysroots="${freebsd11}" ;;
    freebsd12) sysroots="${freebsd12}" ;;
    freebsd13) sysroots="${freebsd13}" ;;
    freebsd)   sysroots="${freebsd10} ${freebsd11} ${freebsd12} ${freebsd13} ${freebsd14}" ;; 
    openbsd) sysroots="${openbsd}" ;;
    netbsd)  sysroots="${netbsd}" ;;
    all) sysroots="${freebsd}${openbsd}${netbsd}" ;;
    *) help ;;
esac


if [ -z "$(echo $sysroots)" ] ; then
    echo "Nothing to process"
    exit
fi

#==================================================================

mkdir -p bsdx
cd bsdx

for i in $sysroots
do

 IFS="|" read XXTARGET_ARCH XXTARGET_OS bsd_base_url <<< "$i"

 case ${XXTARGET_ARCH} in
    "#"*) continue ;; # empty or comment
 esac

 triplet=${XXTARGET_ARCH}-pc-${XXTARGET_OS}

 echo "triplet: ${triplet}"
 echo "${bsd_base_url}: ${bsd_base_url}"

 IFS="-" read XXTARGET_ARCH xxstuff XXTARGET_OS <<< "$triplet"

 bsd_sysroot=sysroot-${XXTARGET_OS}-${XXTARGET_ARCH}
 bsd_base=${bsd_sysroot}_base
 echo "$bsd_sysroot"

 bsd_base2=''
 case ${bsd_base_url} in
    *"@"*)
        bsd_base2=${bsd_sysroot}_base2
        if [ ! -f ${bsd_base}.tar.xz ] ; then
            ${wget} -O ${bsd_base}.tar.xz $(echo $bsd_base_url | cut -f 1 -d '@')
        fi
        if [ ! -f ${bsd_base2}.tar.xz ] ; then
            ${wget} -O ${bsd_base2}.tar.xz $(echo $bsd_base_url | cut -f 2 -d '@')
        fi
        ;;
    *)
        if [ ! -f ${bsd_base}.tar.xz ] ; then
            ${wget} -O ${bsd_base}.tar.xz "$bsd_base_url"
        fi
        ;;
 esac

 #----------------------------------------------------------

 if [ ! -f ${bsd_base}/usr/lib/libc.a ] ; then
    mkdir -p ${bsd_base}
    cd ${bsd_base}
    # NetBSD x86_64 includes 32 libs in lib/i386/*
    if [ -n "$bsd_base2" ] ; then
        tar --exclude='i386/*' -xf ../${bsd_base2}.tar.xz
    fi
    tar --exclude='i386/*' -xf ../${bsd_base}.tar.xz
    cd ..
    sync
    #--
    for i in \
        bin boot dev etc libexec \
        mnt media net proc \
        rescue root sys tmp \
        sbin stand var \
        usr/bin usr/sbin usr/libexec usr/libdata/perl5 \
        lib/i386 usr/lib/i386 libdata/firmware
    do
        if [ -d ${bsd_base}/${i} ] || [ -L ${bsd_base}/${i} ] ; then
            rm -rf ${bsd_base}/${i}
        fi
    done
    #--
    rm -f ${bsd_base}/usr/lib/include
 fi

 #----------------------------------------------------------

 if [ ! -f ${bsd_sysroot}/lib/libc.a ] ; then
    mkdir -p ${bsd_sysroot}/bin
    mkdir -p ${bsd_sysroot}/lib
    mkdir -p ${bsd_sysroot}/include
    ln -sv . ${bsd_sysroot}/usr
    if [ -e ${bsd_base}/COPYRIGHT ] ; then # freebsd
        cp -av ${bsd_base}/COPYRIGHT ${bsd_sysroot}/
    fi
    echo "Copying ${bsd_base}/usr/include/*"
    cp -af --remove-destination ${bsd_base}/usr/include/* ${bsd_sysroot}/include
    echo "Copying ${bsd_base}/usr/lib/*"
    cp -af --remove-destination ${bsd_base}/usr/lib/* ${bsd_sysroot}/lib/
    echo "Copying ${bsd_base}/lib/*"
    cp -af --remove-destination ${bsd_base}/lib/*     ${bsd_sysroot}/lib/
    #-- freebsd 10
    if [ -f ${bsd_sysroot}/lib/private/libssh.a ] ; then
        cp -af --remove-destination ${bsd_sysroot}/lib/private/*  ${bsd_sysroot}/lib/
        sync
        rm -rf ${bsd_sysroot}/lib/private/
    fi
    #--
    rm -rf ${bsd_sysroot}/lib/clang \
        ${bsd_sysroot}/lib/pam_* \
        ${bsd_sysroot}/lib/snmp_* \
        ${bsd_sysroot}/lib/aout \
        ${bsd_sysroot}/lib/compat
    #--
    find ${bsd_base} -name '*-config' | \
        while read l; do
            xbasename=${l##*/}
            cp -fv $l ${bsd_sysroot}/bin/${xbasename}.fixme
        done
    #--
    if [ -n "$(ls ${bsd_sysroot}/lib/casper/*.so* 2>/dev/null)" ] ; then
        # fix broken symlinks to .so files located in /lib/casper
        mv -f ${bsd_sysroot}/lib/casper/*.so* ${bsd_sysroot}/lib
    fi
    sync
    (
    cd ${bsd_sysroot}/lib
    for i in $(find . -type l)
    do
        if [ ! -e "$i" ] ; then
            #echo "broken symlink: $i"
            target=$(ls ${i}.* 2>/dev/null | head -n 1)
            if [ -n "$target" ] ; then
                ln -snfv ${target#./} ${i}
            fi
        fi
    done
    )
    #-- OpenBSD doesn't include .so symlinks... must create it now
    if [ ! -f ${bsd_sysroot}/lib/libc.so ] ; then
        (
        cd ${bsd_sysroot}/lib
        for sofile in $(find -type f -name '*.so.*')
        do
            so1=${sofile%.*}
            so0=${so1%.*}
            case $so0 in *.so)
                ln -sv ${sofile} ${so1}
                ln -sv ${sofile} ${so0}
            esac
        done
        )
    fi
    #--
    if [ ! -d ${bsd_sysroot}/lib/libdata ] ; then
        cp -a ${bsd_base}/usr/libdata ${bsd_sysroot}/lib/
    fi
    if [ -d ${bsd_sysroot}/lib/libdata/pkgconfig ] ; then
        # FreeBSD, NetBSD
        mv ${bsd_sysroot}/lib/libdata/pkgconfig ${bsd_sysroot}/lib/
    elif [ -d ${bsd_sysroot}/lib/pkgconfig ] ; then
        # OpenBSD
        pcapps=$(ls ${bsd_sysroot}/lib/pkgconfig)
        if [ -n "$pcapps" ] ; then
            mv ${bsd_sysroot}/lib/pkgconfig ${bsd_sysroot}/lib/pkgconfig.fixme
        fi
    else
        mkdir -p ${bsd_sysroot}/lib/pkgconfig
    fi
 fi

 #----------------------------------------------------------

 echo ''${XXTARGET_OS}'-'${XXTARGET_ARCH}'

Origin: '$(echo ${bsd_base_url} | tr "@" "\n")'

It is meant to be used with LLVM & GCC cross-compilers

For gcc, you need to build a cross compiler using the sysroot

Example for LLVM toolchains that need a sysroot for a certain target:

  tar -C /opt -xf '${bsd_sysroot}'.tar.xz
  
  Pass --sysroot=/opt/'${bsd_sysroot}' to the compiler
' > ${bsd_sysroot}/readme.txt

 if [ ! -f ${bsd_sysroot}.tar.xz ] ; then
    tar -cJf ${bsd_sysroot}.tar.xz ${bsd_sysroot}
    #( cd ${bsd_sysroot} ; tar -cJf ../${bsd_sysroot}.tar.xz . )
 fi

done  #for i in $sysroots
