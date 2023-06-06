#!/bin/bash
#
# Public Domain
#
# pkg/00_pkg_build   is used when compiling .sbuild packages
# pkg/00_local_build is used when compiling through wcross_make
#
# You can create a special dir with standalone / relocatable / static apps
# - 0wsys/bin        (something that works on all x86 cpus)
# - 0wsys-i686/bin
# - 0wsys-x86_64/bin

#set -x

help_msg()
{
	echo "Build static packages

Usage: 

 0) use build.conf to automate target arch and packages to compile

 1) $0 [-f] <-target arch> <-pkg pkg> [opts]
       target can be '${ARCH_LIN}'
       -target & -pkg can also be 'all'
       -f: rebuild and overwrite existing packages
 2) $0 -targets (list all possible targets, includes mingw, etc)
 3) $0 [-f] initrd_progs  (produce initrd_progs-DATE.tar.xz (initrd_progs.conf))
 4) $0 -download  (don't build, just download)
 5) $0 sfs [arch] (create sfs file of all the compiled packages - 1 sfs per arch)
 6) $0 tgz [arch] (create tgz packages of all the compiled packages)

The compiled binaries and packages can be found in output_static/00_ARCH/
"
	exit
}

#==========================================================

export WDOWNLOAD_DIR=$(pwd)/0sources
CHROOT_WDOWNLOAD_DIR=/WBUILDS/0sources
#export WSUMFILES_DIR=$(pwd)/0sources
#CHROOT_WSUMFILES_DIR=/WBUILDS/0sources

#==========================================================

SITE_MUSL=http://musl.cc 
SITE_MINGW=${SITE_MUSL}

#==========================================================

export RUNNING_OS="$(uname -s)"

if [ "$RUNNING_OS" != "Linux" ] ; then
    echo "Currently only Linux is supported"
    exit 1
fi

if [ $(id -u) -ne 0 ] ; then
    echo "The script may not work as expected with non-root users"
    sleep 2
fi

if ! [ "$BUILD_CONF" ] ; then
	BUILD_CONF="$(pwd)/build.conf"
fi
if [ -f ${BUILD_CONF} ] ; then
	. ${BUILD_CONF}
fi

. ./functions.sh || exit 1

# possible BUILD_TYPEs that can be specified in one of the targets/
# - cross  (default): download and use cross compilers
# - chroot: use alpine linux in a chroot
# - system: use system gcc and libc - not good, only for compiling apps without deps
BUILD_TYPE=cross # default, some targets may change this

export MKFLG
export MWD=`pwd`
export MWD_ORIG=$(realpath `pwd`) # may be useful for chroot
export TARGET_TRIPLET=
ALLOW_STRIP_BIN=${STRIP_BIN}

ARCH_LIN="i686 x86_64 arm aarch64"
ARCH_WIN='win32 win64 winarm winarm64'

export OS_ARCH=`uname -m`

function fatal_error() { echo -e "$@" ; exit 1 ; }
function exit_error() { echo -e "$@" ; exit 1 ; }

if [ -f .fatal ] ; then
    rm -f .fatal
fi

if [ ! -d ${WDOWNLOAD_DIR} ] ; then
    mkdir -p ${WDOWNLOAD_DIR}
fi

#==========================================================

get_wtarget()  #system and chroot targets require some special logic
{
	if [ "$1" = "system" ] ; then
		. /etc/os-release
		OS_DESC=${PRETTY_NAME// /_} #os-release
		echo system-${OS_ARCH}-${OS_DESC}
	elif [ "$1" = "chroot" ] ; then
		# only alpine chroot is currently supported
		if [ -z "${ALPINE_ARCH}" ] ; then
			set_alpine_arch
		fi
		echo chroot-musl-${ALPINE_ARCH}
	else
		# return all args
		echo "$@"
	fi
}

set_alpine_arch() # for chroot
{
	case $OS_ARCH in
		x86_64)
			if [ "$CHROOT_X86_32" ] ; then #build.conf
				ALPINE_ARCH=x86
			else
				ALPINE_ARCH=x86_64
			fi
			;;
		i?86)    ALPINE_ARCH=x86     ;;
		armv*)   ALPINE_ARCH=armhf   ;; # armv7
		aarch64) ALPINE_ARCH=aarch64 ;;
		*) exit_error "0$: $(uname -m) currently not supported.. edit me" ;;
	esac
}

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

case "$1" in
	tgz)
		if [ "$2" ] ; then
			ARCHES=$(get_wtarget ${2})
		else
			ARCHES=${ARCH_LIN}
		fi
		#--
		for xxarch in ${ARCHES}
		do
			dir=$(pwd)/out_w/00_${xxarch}
			if [ ! -d "$dir" ] ; then
				continue
			fi
			pkgs=$(find ${dir}/pkg -maxdepth 2 -type d -name '*_w*')
			if [ -z "$pkgs" ] ; then
				continue
			fi
			for i in ${pkgs} ; do
				echo ${i##*/}.tar.gz
				if [ -f ${dir}/${i##*/}.tar.gz ] ; then
					continue
				fi
				(
				cd $(dirname ${i})
				tar -zcf $(basename ${i}).tar.gz $(basename ${i})
				mv $(basename ${i}).tar.gz ..
				)
			done
			echo "-- ${dir}/${i}.tar.gz"
		done
		echo ; echo ; echo Finished.
		exit
		;;
	sfs)
		if [ "$2" ] ; then
			ARCHES=$(get_wtarget ${2})
		else
			ARCHES=${ARCH_LIN}
		fi
		#--
		for xxarch in ${ARCHES}
		do
			cd ${MWD}/out_w
			rootdir=00_${xxarch}
			if ! [ -d $rootdir ] ; then
				continue
			fi
			case $xxarch in
				system*) pkg_dir=packages-$(date "+%Y.%m.%d")-${xxarch}        ;;
				*)       pkg_dir=static_packages-$(date "+%Y.%m.%d")-${xxarch} ;;
			esac
			pkgs=$(find $rootdir -maxdepth 2 -type d -name '*_w*')
			if [ -z "$pkgs" ] ; then
				continue
			fi
			echo "Creating SFS file for $pkg_dir"
			mkdir -p ${pkg_dir}
			for i in ${pkgs} ; do
				cp -a --remove-destination ${i}/* ${pkg_dir}/
			done
			sync
			mksquashfs ${pkg_dir} ${pkg_dir}.sfs -comp gzip
			echo "Finished: ${pkg_dir}.sfs"
			echo
		done
		exit
		;;
esac

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

## defaults (other defaults are in build.conf) ##
BUILD_ALL=no
export DLD_ONLY=no

if [ -z "$1" ] && [ ! -f ${BUILD_CONF} ] ; then
	help_msg
fi

## command line ##
while [ "$1" ]
do
	case $1 in
		-download|download)
			PACKAGES='all'
			WCROSS_TARGET='all'
			export DLD_ONLY='yes'
			shift
			;;
		-p|-pkg)
			BUILD_PKG="$2" ; shift 2
			[ "$BUILD_PKG" = "" ] && fatal_error "$0 -pkg: Specify a pkg to compile"
			PACKAGES=${BUILD_PKG}
			;;
		-a|-arch|-t|-target)
			WCROSS_TARGET="$2"    ; shift 2
			[ "$WCROSS_TARGET" = "" ] && fatal_error "$0 -target: Specify a target" ;;
		-targets) ls ${MWD}/targets/ ; exit 0 ;;
		-h|-help|--help)
			help_msg
			exit ;;
		tarball|initrd|initrd_progs)
			if ! . ./initrd_progs.conf ; then
				exit_error 'initrd_progs.conf is missing'
			fi
			export INITRD_PROGS
			ipr=out_w/initrd_progs-$(date "+%Y%m%d")-static.tar.xz
			if [ "$FORCE_BUILD" = "" ] && [ -f $ipr ] ; then
				exit_error " -- File $ipr already exists\n Use -f to overwrite"
			fi
			PACKAGES=$(echo "$INITRD_PROGS"  | sed -e '/^$/d' -e '/^#.*/d' | cut -f 1 -d ':')
			WCROSS_TARGET='all'
			break
			;;

		-f|f) export FORCE_BUILD=1;  shift ;;
        # produce static binaries by default
		-static) STATIC_LINK=yes ;  shift ;;
		-shared) STATIC_LINK=no  ;  shift ;;
		-strip)   ALLOW_STRIP_BIN=yes ;  shift ;;
		-nostrip) ALLOW_STRIP_BIN=no  ;  shift ;;
		-gdb)
			ALLOW_STRIP_BIN=no
			WCFLAGS2="$WCFLAGS2 -O0 -ggdb3"
			shift ;;
		-check) WCROSS_MAKE_CHECK=yes ; unset WCROSS_MAKE_NOCHECK  ; shift ;;
		-nocheck) export WCROSS_MAKE_NOCHECK=1  ; shift ;;
		w|w_apps|c) PACKAGES='wbbox' ; WCROSS_TARGET='all' ; break ;;

		-clean)
			echo -e "Press P and hit enter to proceed, any other combination to cancel.." ; read zz
			case $zz in p|P)
				rm -rf out_w ${WDOWNLOAD_DIR} cross-compiler* ;;
			esac
			exit
			;;
		sys|-sys)
			WCROSS_TARGET='system'
			shift
			;;
		chroot|-chroot)
			WCROSS_TARGET='alpine'
			PACKAGES=_none_
			shift
			;;
		*)
			echo "Unrecognized option: $1"
			shift
			;;
	esac
done

if [ "$BUILD_ALL" = "yes" ] ; then
	PACKAGES="all"
elif [ "$BUILD_PKG" != "" ] ; then
	PACKAGES="$BUILD_PKG"
fi

if [ "$PACKAGES" = "all" ] ; then
	PACKAGES=$(find pkg -maxdepth 1 -name '*.sbuild' | \
		sed -e 's|.*/||' -e 's%\.sbuild%%' | sort)
fi

if [ -z "$1" ] && [ -z "$PACKAGES" ] ; then
	help_msg
fi

#==============================================================

function create_initrd_progs_tarball()
{
	cd out_w
	echo ; echo
	pkgx=initrd_progs-$(date "+%Y%m%d")-static.tar.xz
	for xxarch in ${ARCH_LIN}
	do
		arch00=00_${xxarch}
		cd ${arch00} || exit_error aaah
		mkdir -p bin/
		rm -f bin/*
		while read iprog
		do
			case $iprog in '#'*) continue ;; esac
			case $iprog in '') continue ;; esac
			pkgname=$(echo $iprog | cut -f1 -d ':')
			pkgname=${pkgname%_static}
			bins=$(echo $iprog | cut -f2 -d ':')
			pkgdir=$(ls -d pkg/${pkgname}-* | tail -1)
			if ! [ -d $pkgdir ] ; then
				exit_error
			fi
			for bin in $bins
			do
				echo "#### $bin"
				fbin=$(find $pkgdir \( -type f -or -type l \) -name $bin -executable | grep bin | head -1)
				if ! [ "$fbin" ] ; then
					exit_error "cannot find '$bin' in '$pkgdir'"
				fi
				cp -av --remove-destination ${fbin} bin/
				progs2tar="${progs2tar} ${arch00}/bin/${bin}"
			done
		done <<< "$INITRD_PROGS"
		echo -----------
		cd ..
	done
	echo -e "\n\n*** Creating $pkgx"
	tar -Jcf $pkgx ${progs2tar}
	cd ..
	echo "Done."
	exit
}

#==============================================================

install_musl_compat_headers() # $1: install prefix
{
    ( cd ${MWD}/pkg_patches/0musl-compat-headers
        make PREFIX=${1} install )
}


cross_toolchain_sanity_check()
{
    if [ ! -d "${XPATH}/bin" ] || [ ! -d "${XPATH}/lib" ] || [ ! -d "${XPATH}/include" ]; then
        exit_error "$XPATH is not properly set up"
    fi
    # $TARBALL_ARCH is specified in targets/xxx
    if [ -n "$TARBALL_ARCH" ] && [ -n "$TARBALL_ARCH2" ] ; then
        if [ "$OS_ARCH" != "$TARBALL_ARCH" ] && [ "$OS_ARCH" != "$TARBALL_ARCH2" ] ; then
            exit_error "ERROR: the $TARGET_TRIPLET cross compiler is $TARBALL_ARCH/$TARBALL_ARCH2 and your system is $OS_ARCH"
        fi
    elif [ -n "$TARBALL_ARCH" ] ; then
        if [ "$OS_ARCH" != "$TARBALL_ARCH" ] ; then
            exit_error "ERROR: the $TARGET_TRIPLET cross compiler is $TARBALL_ARCH and your system is $OS_ARCH"
        fi
    fi
    # $COMPILER_SYMLINK is set in targets/xxx
    if [ -n "$COMPILER_SYMLINK" ] ; then
        if [ ! -e "$COMPILER_SYMLINK" ] ; then
            mkdir -p $(dirname ${COMPILER_SYMLINK})
            ln -snfv ${XPATH} ${COMPILER_SYMLINK}
        fi
    fi
    # extra sanity checks scripts/functions set by targets/xxx
    if [ -n "$SANITY_CHECK" ] ; then
        # source script 
        . ${SANITY_CHECK}
    elif [ -n "$SANITY_CHECK_FUNC" ] ; then
        ${SANITY_CHECK_FUNC}
    fi
}


cross_toolchain_after_extract()  #this is run once
{
    if [ "$AFTER_EXTRACT_FUNC" ] ; then
        cmd_echo ${AFTER_EXTRACT_FUNC}
    fi
    #-- musl updates
    case ${TARGET_TRIPLET} in *musl*)
        if [ "$MUSL_AFTER_EXTRACT_UPDATE" ] ; then
            rm -fv ${XPATH}/${TARGET_TRIPLET}/lib/libc.a
            export W_FORCED_PKG_DEPS='0musl' # force pkg/0--libs/0musl.sbuild
        fi
        if [ -n "$MUSL_NEED_NEWER_HEADERS" ] ; then
            rm -rf ${XPATH}/${TARGET_TRIPLET}/include/linux
            export W_FORCED_PKG_DEPS="$W_FORCED_PKG_DEPS 0linux-headers"
        fi ;;
    esac
    #-- generic GCC stuff
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
        for i in $(ls ${XPATH}/bin | grep "${TARGET_TRIPLET}-gnat") ; do
            app=${i##*-}
            ln -sv ${i} ${XPATH}/bin/${app}
        done
    fi
    #--
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
    (  #dedup binutils apps
    cd ${XPATH}
    dedup_toolchain_apps ${TARGET_TRIPLET}
    )
    # remove some directories
    for i in share/doc share/man share/info share/locale
    do
        if [ -d ${XPATH}/${i} ] ; then
            cmd_echo rm -rf ${XPATH}/${i}
        fi
    done
    # make sure some dirs exist
    if [ -d ${XPATH}/${TARGET_TRIPLET} ] ; then
        if [ ! -e ${XPATH}/${TARGET_TRIPLET}/usr ] ; then
            ln -sv . ${XPATH}/${TARGET_TRIPLET}/usr
        fi
        mkdir -p ${XPATH}/${TARGET_TRIPLET}/lib/pkgconfig
    fi
    ## may need to install extra stuff
    case ${TARGET_TRIPLET} in
        *musl*)  cmd_echo install_musl_compat_headers ${TOOLCHAIN_INSTALL_PREFIX} ;;
        #*mingw*) install_mingw_compat_headers ${TOOLCHAIN_INSTALL_PREFIX} ;;
    esac
}


#==============================================================

function setup_compiler_cross()
{
    unset TARGET_TRIPLET
    unset CC_TARBALL
    unset TARBALL_SPECS
    unset TARBALL_URL TARBALL_ARCH TARBALL_CHK
    unset COMPILER_SYMLINK
    unset MUSL_TOOLCHAIN
    #--
    case ${WCROSS_TARGET} in
        default)  WCROSS_TARGET=${OS_ARCH} ;;
        i*86|x86) WCROSS_TARGET=i686    ;;
        arm64)    WCROSS_TARGET=aarch64 ;;
        armv6|armv6l) WCROSS_TARGET=arm ;;
    esac
    export WTARGET=${WCROSS_TARGET}
    . ${MWD}/targets/${WCROSS_TARGET} || exit_error
    if [ -z "$TARGET_TRIPLET" ] ; then
        exit_error "\$TARGET_TRIPLET is required"
    fi
    if [ -n "$TARBALL_URL" ] ; then
        SITE=${TARBALL_URL%/*}        # dirname
        CC_TARBALL=${TARBALL_URL##*/} # basename
    fi
    #--
    if [ -z "$CC_TARBALL" ] ; then
        exit_error "Cross compiler for ${WCROSS_TARGET} is not available."
    fi
    # known toolchains, pkg.sbuild uses this info to
    # determine what hacks or patches apply
    case ${TARGET_TRIPLET} in
        # bsd
        *freebsd*) export FREEBSD_TOOLCHAIN='yes' ;;
        *openbsd*) export OPENBSD_TOOLCHAIN='yes' ;;
        *netbsd*)  export NETBSD_TOOLCHAIN='yes'  ;;
        *bsd*)     export BSD_TOOLCHAIN='yes'     ;;
        # linux
        *-musl*)   export MUSL_TOOLCHAIN='yes'   ;;
        *-uclibc*) export UCLIBC_TOOLCHAIN='yes' ;;
        *-gnu*)    export GLIBC_TOOLCHAIN='yes'  ;;
        *linux*)   export GLIBC_TOOLCHAIN='yes'  ;;
        # windows
        *mingw*)   export MINGW_TOOLCHAIN='yes' ;;
    esac
    #--
    export TARGET_TRIPLET
    export CPU_ARCH=${TARGET_TRIPLET%%-*} # ex: i686, x86_64
    #--
    echo -e "\n*** Arch: $ARCH  [$TARGET_TRIPLET]"
    sleep 1.0

    #--------------------------------------------

    TARBALL_DIR=${CC_TARBALL%.tar.*}  # remove trailing *.tar.*
    TARBALL_DIR=${TARBALL_DIR%.tgz}   # remove trailing .tgz
    TARBALL_DIR=${TARBALL_DIR%.txz}   # remove trailing .txz
    export CC_DIR=cross-compiler/${TARBALL_DIR}
    export XPATH=${PWD}/${CC_DIR}     # see ./func
    echo
    mkdir -p cross-compiler
    #----
    download_file ${SITE}/${CC_TARBALL}
    #-- always using ${XPATH}/${TARGET_TRIPLET} as the sysroot (even when it's empty)
    TOOLCHAIN_ROOT=${XPATH}/${TARGET_TRIPLET}
    TOOLCHAIN_INSTALL_PREFIX=${TOOLCHAIN_ROOT}/usr
    #--
    if [ ! -d ${XPATH} ] && [ "$DLD_ONLY" != "yes" ] ; then
        WTAR_OPTS='-C cross-compiler' extract_archive ${CC_TARBALL}
        ( cd ${XPATH} ) || exit_error
        sync
        if [ -n "$TARBALL_SPECS" ] ; then
            echo "$TARBALL_SPECS" > ${XPATH}/specs.txt
        fi
        cmd_echo cross_toolchain_after_extract
    fi
    #--
    cd $MWD
    echo $XPATH
    #cmd_echo cross_toolchain_after_extract ; exit #uncomment to debug
    cmd_echo cross_toolchain_sanity_check
}

#==============================================================

function setup_compiler_chroot()
{
    # Alpine Linux minimal chroot 
    # https://wiki.alpinelinux.org/wiki/Alpine_Linux_in_a_chroot
    alpine_major_ver=${ALPINE_LINUX_VER%.*}
    #--
    alpine_dir=v${alpine_major_ver}/releases/${ALPINE_ARCH}
    alpine_tarball=alpine-minirootfs-${ALPINE_LINUX_VER}-${ALPINE_ARCH}.tar.gz
    alpine_url=${ALPINE_LINUX_SITE}/${alpine_dir}/${alpine_tarball}
    #--
    download_file ${alpine_url}
    if [ "$DLD_ONLY" = "yes" ] ; then
        exit 0
    fi
    if ! [ -f bin/busybox ] ; then
        extract_archive ${alpine_tarball}
    fi
    if [ ! -e dev/zero ] || [ ! -f /run/alpine_mounted ] ; then
        chroot_dir=$(pwd)
        mount -o bind /dev ${chroot_dir}/dev
        mount -t proc none ${chroot_dir}/proc
        mount -o bind /sys ${chroot_dir}/sys
        cp -L /etc/resolv.conf ${chroot_dir}/etc/
        #echo -e 'nameserver 8.8.8.8\nnameserver 2620:0:ccc::2' > ${chroot_dir}/etc/resolv.conf
        # make $MWD available to chroot jail as /WBUILDS
        mkdir -p ${chroot_dir}/WBUILDS
        mount -o bind ${MWD} ${chroot_dir}/WBUILDS
        # this signals that all mountpoints have been established..
        touch /run/alpine_mounted
    fi
    #--
    if ! [ -L etc/apk/cache ] ; then
        # store package cache outside chroot jail
        zzdir=0sources/alpine_${ALPINE_ARCH}_${alpine_major_ver}
        mkdir -p ${MWD}/${zzdir}
        ln -snfv /WBUILDS/${zzdir} etc/apk/cache
        sync
    fi
    #--
    apk_add='cmd_echo chroot . apk add --allow-untrusted' #--no-cache
    #--
    if ! [ -e bin/bash ] ; then
        # base
        ${apk_add} build-base bash linux-headers
        ${apk_add} gcc-gnat gfortran gcc-go gcc-objc gcc-gdc libucontext-dev
        # extra build tools
        ${apk_add} cmake autoconf automake libtool bison mold samurai
        ${apk_add} bmake mk-configure mk-configure-dev # bsd
        ${apk_add} nasm yasm yasm-dev #uasm    # assemblers
        # essential dev apps
        ${apk_add} git gdb lldb py3-lldb
        # python
        ${apk_add} meson scons waf py3-setuptools py3-pip
        # perl
        ${apk_add} perl perl-utils
        #chroot . cpan App::cpanminus
        #chroot . cpan Devel::PatchPerl
        # tools
        ${apk_add} lzip tar xz gzip unzip zip bzip2
        ${apk_add} rsync # needed to install kernel headers
        # gtk
        #chroot . ${apk_add} gtk4.0-dev geany 
        # libs
        ${apk_add} \
            acl-static acl-dev    bzip2-static bzip2-dev \
            libftdi1-static libftdi1-dev   zlib-static zlib-dev
        # make sure Ada produces static binaries by default
        for i in gnatbind gnatlink ; do
            if [ -e ${XPATH}/usr/bin/${i} ] && [ ! -e ${XPATH}/usr/bin/${i}-bin ] ; then
                mv -fv ${XPATH}/usr/bin/${i} ${XPATH}/usr/bin/${i}-bin
                echo '#!/bin/sh
exec '${i}'-bin -static "$@"
' > ${XPATH}/usr/bin/${i}
                chmod +x ${XPATH}/usr/bin/${i}
            fi
        done
        # make sure gFortran produces static binaries by default
        if [ -e ${XPATH}/usr/bin/gfortran ] && [ ! -e ${XPATH}/usr/bin/gfortran-bin ] ; then
            mv -fv ${XPATH}/usr/bin/gfortran ${XPATH}/usr/bin/gfortran-bin
            echo '#!/bin/sh
echo "gfortran-bin -static-libgfortran -static-libgcc -static "$@""
exec gfortran-bin -static-libgfortran -static-libgcc -static "$@"
' > ${XPATH}/usr/bin/gfortran
            chmod +x ${XPATH}/usr/bin/gfortran
        fi
        #--
        install_musl_compat_headers ${XPATH}/usr
    fi
    if [ ! -d "./bin" ] && [ ! -d "./lib" ] ; then
        exit_error "error with chroot"
    fi
}

#==============================================================

function build_pkgs()
{
	rm -f .fatal
	mkdir -p out_w/00_${WTARGET}/bin out_w/00_${WTARGET}/log ${WDOWNLOAD_DIR}
	#--
	for one_pkg in ${PACKAGES}
	do
		case $one_pkg in ""|'#'*) continue ;; esac
		#--
		export BUILD_PACKAGE=${one_pkg}
        if [ "$BUILD_PACKAGE" = "none" ] ; then
            break  #end this
        fi
		#--
		pkg_dot_sbuild=''
        wsbuild=
        if [ -n "${EXTRA_PKG_DIR}" ] ; then
            wsbuild=${EXTRA_PKG_DIR}/${one_pkg}.sbuild
        fi
        for i in ${one_pkg}.sbuild ${wsbuild} \
                 pkg/${one_pkg}.sbuild \
                 pkg/0--libs/${one_pkg}.sbuild \
                 pkg/${one_pkg}
        do
                if [ -e "${i}" ] ; then
                    pkg_dot_sbuild=${i}
                    break
                fi
        done
		#--
        if [ "$one_pkg" = "00_local_build" ] ; then
            build_script="00_local_build"
        else
            build_script="00_pkg_build"
            if [ -z "${pkg_dot_sbuild}" ] || [ -z ${pkg_dot_sbuild} ] ; then
                exit_error "Can't find ${one_pkg}"
            fi
        fi
		mkdir -p ${MWD}/out_w/00_${WTARGET}/log
		#--
		if [ "$BUILD_TYPE" = "chroot" ] ; then
			# with a chroot some variables must be modified
			MWD=/WBUILDS \
			WDOWNLOAD_DIR=${CHROOT_WDOWNLOAD_DIR} \
			WSUMFILES_DIR=${CHROOT_WSUMFILES_DIR} \
			XPATH=/WBUILDS/${CC_DIR} \
			chroot ${CHROOT_DIR} bash /WBUILDS/pkg/${build_script} ${pkg_dot_sbuild} 2>&1 | \
				tee ${MWD}/out_w/00_${WTARGET}/log/${one_pkg}-chroot-build.log
		else
			# specify full script path, may need to get the script dir
			bash ${MWD}/pkg/${build_script} ${pkg_dot_sbuild} 2>&1 | \
				tee ${MWD}/out_w/00_${WTARGET}/log/${one_pkg}--build.log
		fi
		cd ${MWD}
		if [ -f .fatal ] ; then
			rm -f .fatal
			exit_error "Exiting.."
		fi
	done
	rm -f .fatal
}



#==============================================================
#                       MAIN
#==============================================================

which make &>/dev/null || fatal_error "Install make"
which gcc &>/dev/null || fatal_error "Install gcc"

if [ "$PACKAGES" = "local" ] ; then
    PACKAGES=00_local_build
fi

WTARGET=${WCROSS_TARGET}
case ${WCROSS_TARGET} in system|chroot|alpine)
    EXTRA_PKG_DIR='pkg/sysgcc' ;;
esac

case ${WCROSS_TARGET} in
    all) all=1 ;; # all: special target to cross-compile a pkg using several linux cross-compilers
    *)
        if [ -e "${MWD}/${WCROSS_TARGET}" ] ; then
            WTARGET=${WCROSS_TARGET##*/}
            . ${WCROSS_TARGET}
            WCROSS_TARGET=${WTARGET}
        elif [ -e "${MWD}/targets/${WCROSS_TARGET}" ] ; then
            . ${MWD}/targets/${WCROSS_TARGET}
        else
            exit_error "${WCROSS_TARGET} is not a valid target"
        fi
        ;;
esac

if [ -z "$WLIBDIR" ] ; then
	#only targets/system may change it to lib64
	export WLIBDIR='lib'
fi

# chroot & system = linux
# if cross-compiling, the target/xxx has already set TARGET_TRIPLET
WCROSS_TARGET_OS='linux'  # default
WCROSS_TARGET_POSIX='yes' # default

case ${TARGET_TRIPLET} in
    # other than linux, only bsd and mingw targets are reconigzed...
    *freebsd*) WCROSS_TARGET_OS='freebsd' ;;
    *openbsd*) WCROSS_TARGET_OS='openbsd' ;;
    *netbsd*)  WCROSS_TARGET_OS='netbsd' ;;
    *mingw*)   WCROSS_TARGET_OS='windows' ; WCROSS_TARGET_POSIX='' ;;
esac
export WCROSS_TARGET_OS
export WCROSS_TARGET_POSIX

export BUILD_TYPE
#echo "$BUILD_TYPE" # debug
# STATIC_LINK is empty by default (=no)
# this is set by -static or -shared and overriden by targets/xxx
# unless the targets/xxx sets STATIC_LINK only if it's empty
export STATIC_LINK
export WCROSS_MAKE_CHECK
export ALLOW_STRIP_BIN
export WCFLAGS2

if [ "$BUILD_TYPE" = "chroot" ] ; then
    # alpine linux is the only supported chroot
    set_alpine_arch
    export MUSL_TOOLCHAIN='yes'
    export CC_DIR=cross-compiler/$(get_wtarget chroot)
    export WTARGET=$(get_wtarget chroot)  # see ./func
    export XPATH=${PWD}/${CC_DIR}
    export CHROOT_DIR=${XPATH}
    export TARGET_TRIPLET='linux-chroot'
    case ${ALPINE_ARCH} in
		x86)
			export CPU_ARCH=i686
			export TARGET_TRIPLET='i686-linux-chroot'
			;;
		*)
			export CPU_ARCH=${ALPINE_ARCH}
			export TARGET_TRIPLET="${ALPINE_ARCH}-linux-chroot"
			;;
    esac
    mkdir -p ${CC_DIR}
    cd ${CC_DIR}
    setup_compiler_chroot
    if [ "$PACKAGES" = "_none_" ] ; then
        echo " ** Performing Alpine chroot only, then you can do whatever you want inside"
        chroot . ls
        exec chroot . sh
    fi
    cd ${MWD}
    build_pkgs
    exit $?

elif [ "$BUILD_TYPE" = "system" ] ; then
    # system gcc & libs
    # challenge: properly support lib64
    export CPU_ARCH=${OS_ARCH}
    export CC_DIR=cross-compiler/$(get_wtarget system) #include distro desc
    export WTARGET=$(get_wtarget system)  # see ./func
    export XPATH=${PWD}/${CC_DIR}         # see ./func
    export TARGET_TRIPLET='linux-system'
    #--
	if [ ! -d ${XPATH} ] ; then
		mkdir -p ${XPATH}/bin
		if [ "${WLIBDIR}" = "lib64" ] ; then
			mkdir -p ${XPATH}/lib64/pkgconfig
			ln -sv lib64 ${XPATH}/lib
		else
			mkdir -p ${XPATH}/lib/pkgconfig
		fi
		mkdir -p ${XPATH}/include
		ln -sv ./ ${XPATH}/usr
		export W_FORCED_PKG_DEPS="$W_FORCED_PKG_DEPS 0linux-headers"
	fi
    build_pkgs
    exit $?

else
    # cross compilers
    if [ -z "${WCROSS_TARGET}" ] ; then
        echo -e "\nMust specify target arch: -a <arch>"
        echo "  <arch> can be one of these: $ARCH_LIN default"
        echo -e "\nSee also: $0 --help"
        exit 1
    fi
    ARCHES=${WCROSS_TARGET}
    if [ "${WCROSS_TARGET}" = "all" ] ; then
        ARCHES=${ARCH_LIN}
    fi
    #--
    for i in $ARCHES
    do
        WCROSS_TARGET=${i}
        setup_compiler_cross
        build_pkgs
        cd ${MWD}
    done
fi

if [ "$INITRD_PROGS" ] ; then
    create_initrd_progs_tarball
fi

### END ###
