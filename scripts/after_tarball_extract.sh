#!/bin/sh
# Public Domain
#
# this is NOT sourced
#
# fixes to apply after extracting toolchain tarballs
# this must be called as the last step
#

glibc_url=https://ftp.gnu.org/gnu/glibc/glibc-2.36.tar.xz

if [ -z "$XPATH" ] ; then
    echo "syntax: $0 <DIR>"
    XPATH="$1"
fi

if [ -z "$XPATH" ] ; then
    echo "\$PATH is empty"
    exit 1
fi

if [ -z "$TARGET_TRIPLET" ] ; then
    TARGET_TRIPLET=$(ls -d ${XPATH}/*-*-* | head -1)
    TARGET_TRIPLET=${TARGET_TRIPLET##*/} # basename
fi

if [ -z "$TARGET_TRIPLET" ] ; then
    echo "\$TARGET_TRIPLET is empty"
    exit 1
fi

#==================================================================

compile_glibc() # assuming we're inside da toolchain sysroot
{
    # recompile glibc to make it compatible with linux 3.2.0+
    if [ -f "lib/libc.a" ] ; then
        return 0
    fi
    SRC_URL=${glibc_url}
    SRC_FILE=${SRC_URL##*/}    # basename
    SRC_DIR=${SRC_FILE%.tar.*} # remove trailing .tar.*
    # https://github.com/archlinux/svntogit-packages/blob/packages/glibc/trunk/PKGBUILD
    retrieve ${SRC_URL}
    extract_pkg_and_cd
    #--
    src_dir=$(pwd)
    build_dir=${src_dir}-build
    mkdir -p ${build_dir}
    cd ${build_dir}
    #--
    GPREFIX=${XPATH}/${TARGET_TRIPLET}
    # discarded
    #  --enable-kernel=4.4 --enable-stack-protector=strong
    #  --enable-systemtap ## error: systemtap support needs sys/sdt.h with asm support
    #  --enable-cet
    #  --disable-shared     # <command-line>: fatal error: .../glibc-2.36-build/libc-modules.h: No such file or directory
    #  --enable-static-nss  # nss_module.c:153:7: error: 'is_nscd' undeclared (first use in this function)
    CFLAGS="-I${GPREFIX}/include" CXXFLAGS="-I${GPREFIX}/include" \
    ${src_dir}/configure \
        --disable-build-nscd \
        --host=${TARGET_TRIPLET} \
        --build=$(gcc -dumpmachine) \
        --disable-timezone-tools \
        --prefix=${GPREFIX} \
        --with-headers=${GPREFIX}/inlcude \
        --enable-bind-now \
        --disable-multi-arch \
        --disable-profile \
        --disable-crypt \
        --disable-werror \
        --libdir=${GPREFIX}/lib \
        --libexecdir=${GPREFIX}/lib || exit 1
    make install || exit 1
    rm -rf ${src_dir} ${build_dir}
}


#==================================================================
# fix toolchain according to some rules..

case ${XPATH} in
 *--glibc--*|*--musl--*)
    echo "#### FIX BUILDROOT ####"
    rm -fv ${XPATH}/bin/python-freeze-importlib
    if [ ! -L ${XPATH}/bin/${TARGET_TRIPLET}-ld ] && [ -f ${XPATH}/bin/${TARGET_TRIPLET}-ld.bfd ] ; then
        ln -snfv ${TARGET_TRIPLET}-ld.bfd ${XPATH}/bin/${TARGET_TRIPLET}-ld
    fi
    rm -fv ${XPATH}/bin/${TARGET_TRIPLET}-gcc-[1-9]* # ex: aarch64-linux-musl-gcc-11.2.1

    TT=${XPATH}/${TARGET_TRIPLET}
    #setup_mold
    if [ -d ${TT}/sysroot ] && [ ! -L ${TT}/sysroot ] ; then
        rm -fv ${TT}/sysroot/usr/lib/*.so*
        rm -rf ${TT}/sysroot/usr/bin
        rm -rf ${TT}/sysroot/usr/sbin
        sync
        #--
        cp -a --remove-destination ${TT}/sysroot/usr/* ${TT}/sysroot/
            sync
        rm -rf ${TT}/sysroot/usr/
        for i in $(ls -d ${TT}/sysroot/*)
        do
            rmdir ${i} 2>/dev/null
        done
        rm -rf ${TT}/sysroot/bin
        rm -rf ${TT}/sysroot/sbin
        rm -rf ${TT}/sysroot/dev
        rm -rf ${TT}/sysroot/etc
        rm -rf ${TT}/sysroot/var
        rm -rf ${TT}/sysroot/sbin
        rm -rf ${TT}/sysroot/lib32
        rm -rf ${TT}/sysroot/lib64
        rm -rf ${TT}/sysroot/share
        sync
        cp -a --remove-destination ${TT}/sysroot/* ${TT}
        rm -rf ${TT}/sysroot
        ln -sv ./ ${TT}/sysroot
    fi
    if [ ! -e ${TT}/usr ] ; then
        ln -sv ./ ${TT}/usr
        ln -sv lib ${TT}/lib32 
        ln -sv lib ${TT}/lib64 
        mkdir -p ${TT}/sbin ${TT}/share
    fi
    #rm -fv ${TT}/lib/*.so*
    ;;

  *musl*) #### musl-cross-make
    echo "#### FIX MUSL-CROSS-MAKE ####"
    if [ ! -L ${XPATH}/bin/${TARGET_TRIPLET}-ld ] && [ -f ${XPATH}/bin/${TARGET_TRIPLET}-ld.bfd ] ; then
        ln -snfv ${TARGET_TRIPLET}-ld.bfd ${XPATH}/bin/${TARGET_TRIPLET}-ld
    fi
    rm -fv ${XPATH}/bin/${TARGET_TRIPLET}-gcc-[1-9]* # ex: aarch64-linux-musl-gcc-11.2.1
    #rm -fv ${XPATH}/${TARGET_TRIPLET}/lib/*.so*
    ;;
esac

case ${TARGET_TRIPLET} in *-musl*)
    if [ "$MUSL_VERSION" != "$MUSL_CC_VERSION" ] ; then
        # force new version & headers (see build.sh)
        rm -fv ${XPATH}/${TARGET_TRIPLET}/lib/libc.a
        if [ -n "$MUSL_NEED_NEWER_HEADERS" ] ; then
            rm -rf ${XPATH}/${TARGET_TRIPLET}/include/linux
        fi
    fi
    echo -n > ${XPATH}/musl_${MUSL_CC_VERSION}
    ;;
esac

#==================================================================
# remove some directories
for i in share/doc share/man share/info share/locale
do
    if [ -d ${XPATH}/${i} ] ; then
        rm -rf ${XPATH}/${i}
        echo "removed ${XPATH}/${i}"
    fi
done

# create some directories
if [ -d ${XPATH}/${TARGET_TRIPLET} ] ; then
    if [ ! -e ${XPATH}/${TARGET_TRIPLET}/usr ] ; then
        ln -sv . ${XPATH}/${TARGET_TRIPLET}/usr
    fi
    mkdir -p ${XPATH}/${TARGET_TRIPLET}/lib/pkgconfig \
             ${XPATH}/${TARGET_TRIPLET}/sbin \
             ${XPATH}/${TARGET_TRIPLET}/share
fi


#==================================================================
#                GCC - DEDUPLICATE BINUTILS
#==================================================================

dedup_toolchain_apps()
{
    # bin/i686-linux-musl-ar -> ../../bin/${TRIPLET}-ar
    if [ ! -e ${XPATH}/bin/${TARGET_TRIPLET}-gcc ] ; then
        return
    fi
    if [ ! -e ${XPATH}/${TARGET_TRIPLET}/bin/ar ] ; then
        return 0 # probably an llvm toolchain or something is wrong
    elif [ -L ${XPATH}/${TARGET_TRIPLET}/bin/ar ] ; then
        return 0 # already processed
    fi
    for app1 in $(ls ${XPATH}/${TARGET_TRIPLET}/bin | grep -v 'fixme')
    do
        # ln -snfv ../../bin/i686-linux-musl-ar i686-linux-musl/bin/ar
        ln -snfv ../../bin/${TARGET_TRIPLET}-${app1} ${XPATH}/${TARGET_TRIPLET}/bin/${app1}
    done
    return 0
}

dedup_toolchain_apps



#==================================================================
#                     GCC GNAT (ADA)
#==================================================================

if [ -e ${XPATH}/bin/${TARGET_TRIPLET}-gnat ] && [ ! -e ${XPATH}/bin/gnat ] ; then
    # create scrips & symlinks (without prefix to avoid dealing with cross-compilation issues)
    # a script is supposed to make this bin dir the first in $PATH
    rm -f ${XPATH}/bin/gnatmake
    echo '#!/bin/sh
exec '${TARGET_TRIPLET}'-gnatmake --GCC="'${TARGET_TRIPLET}'-gcc ${GCC_SYSROOT}" --GNATBIND=gnatbind --GNATLINK=gnatlink ${GCC_LIB} "$@"
' > ${XPATH}/bin/gnatmake
    chmod +x ${XPATH}/bin/gnatmake
    #--
    rm -f ${XPATH}/bin/gnatbind
    echo '#!/bin/sh
exec '${TARGET_TRIPLET}'-gnatbind -static "$@"
' > ${XPATH}/bin/gnatbind
    chmod +x ${XPATH}/bin/gnatbind
    #--
    rm -f ${XPATH}/bin/gnatlink
    echo '#!/bin/sh
exec '${TARGET_TRIPLET}'-gnatlink --GCC="'${TARGET_TRIPLET}'-gcc ${GCC_STATIC} ${GCC_SYSROOT}" "$@"
' > ${XPATH}/bin/gnatlink
    chmod +x ${XPATH}/bin/gnatlink
    #--
    for i in $(ls ${XPATH}/bin | grep "${TARGET_TRIPLET}-gnat")
    do
        app=${i##*-}
        ln -sv ${i} ${XPATH}/bin/${app}
    done
fi



#==================================================================
#                   GCC GFORTRAN (FORTRAN)
#==================================================================

if [ -e ${XPATH}/bin/${TARGET_TRIPLET}-gfortran ] && [ ! -e ${XPATH}/bin/gfortran ] ; then
    rm -f ${XPATH}/bin/gfortran
    echo '#!/bin/sh
if [ -n "${GCC_STATIC}" ] ; then # it may be -static, change it to -static-libgcc
    GCC_STATIC="-static-libgcc"
fi
exec '${TARGET_TRIPLET}'-gfortran -static-libgfortran ${GCC_STATIC} ${GCC_SYSROOT} "$@"
' > ${XPATH}/bin/gfortran
    chmod +x ${XPATH}/bin/gfortran
fi



#==================================================================
#   MINGW LLVM - https://github.com/mstorsjo/llvm-mingw/releases
#==================================================================

if [ -d ${XPATH}/generic-w64-mingw32 ] && [ -d ${XPATH}/aarch64-w64-mingw32 ] ; then
    # - the cross compiler is basically ready to use as is.. works as expected
    # - generic-w64-mingw32 only contains 'include'
    #   and all the targets contain symlinks to that include dir
    # - fix sysroot: a proper include dir must be present in each target
    for mingw_arch in aarch64-w64-mingw32 armv7-w64-mingw32 \
                      i686-w64-mingw32 x86_64-w64-mingw32
    do
        rm -fv ${XPATH}/${mingw_arch}/include # symlink
        sync
        cp -a ${XPATH}/generic-w64-mingw32/include ${XPATH}/${mingw_arch}/
        ln -sv ./ ${XPATH}/${mingw_arch}/usr
        mkdir -p ${XPATH}/${mingw_arch}/lib/pkgconfig
    done
    sync
    #--
    if [ -n "$llvm_version" ] ; then
        echo -n > ${llvm_version}
    fi
    rm -rf ${XPATH}/generic-w64-mingw32
fi


# the official llvm binaries are huge and not stripped
if [ -e ${XPATH}/bin/bbc ] && [ `stat -c %s ${XPATH}/bin/bbc` -gt 32820608 ] ; then
	#14.0 debug   : 64416936
	#14.0 stripped: 22820608
	for i in $(ls ${XPATH}/bin/*) $(find ${XPATH}/lib -name '*.so*')
	do
		if [ -L $i ] ; then
			continue
		fi
		echo "strip ${i##*/}"
		strip $i
	done
fi
