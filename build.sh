#!/bin/bash
#
# Public Domain
#
# compile musl static apps
# - ./build tarball to produce initrd_progs.xz
# - ./build w       to build speciall C apps
#
# compile apps at will, and run:
# - ./build tgz to generate individual tgz pkgs
# - ./build sfs to produce big sfs packages
#

#set -x

# http://musl.libc.org/releases
export MUSL_VERSION=1.2.3
export MUSL_CC_VERSION=1.2.3 # linux cc tarballs -- change this in targets/*
MUSL_URL=http://musl.libc.org/releases/musl-${MUSL_VERSION}.tar.gz
# http://ftp.barfooze.de/pub/sabotage/tarballs
LINUX_HEADER_URL=http://ftp.barfooze.de/pub/sabotage/tarballs/linux-headers-4.19.88-1.tar.xz

# https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/
MINGW_VERSION=v10.0.0
MINGW_CC_VERSION=v9.0.0
MINGW_URL=https://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/mingw-w64-${MINGW_VERSION}.tar.bz2

# https://github.com/mstorsjo/llvm-mingw/releases
## see also zscripts/after_tarball_extract.sh
#llvm_mingw_version=20211002 ; export llvm_version='llvm_13.0.0'
#llvm_mingw_version=20220323 ; export llvm_version='llvm_14.0.0'
llvm_mingw_version=20220906 ; export llvm_version='llvm_15.0.0'
msvcrt_url=https://github.com/mstorsjo/llvm-mingw/releases/download/${llvm_mingw_version}/llvm-mingw-${llvm_mingw_version}-msvcrt-ubuntu-18.04-x86_64.tar.xz
msvcrt_url=https://github.com/mstorsjo/llvm-mingw/releases/download/${llvm_mingw_version}/llvm-mingw-${llvm_mingw_version}-ucrt-ubuntu-18.04-x86_64.tar.xz

# https://github.com/llvm/llvm-project/releases
CLANG_VER=14.0.0
CLANG_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-14.0.0/clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz

# https://github.com/rui314/mold/releases
mold_url=https://github.com/rui314/mold/releases/download/v1.7.1/mold-1.7.1-x86_64-linux.tar.gz

export RUNNING_OS="$(uname -s)"

if [ "$RUNNING_OS" != "Linux" ] ; then
    echo "Currently only Linux is supported"
    exit 1
fi

if [ $(id -u) -ne 0 ] ; then
    echo "The script may not work as expected with non-root users"
fi

if ! [ "$BUILD_CONF" ] ; then
	BUILD_CONF="$(pwd)/build.conf"
fi
if [ -f ${BUILD_CONF} ] ; then
	. ${BUILD_CONF}
fi

# possible BUILD_TYPEs that can be specified in one of the targets/
# - cross  (default): download and use cross compilers
# - chroot: use alpine linux in a chroot
# - system: use system gcc and libc - not good, only for compiling apps without deps
BUILD_TYPE=cross # default, some targets may change this

export MKFLG
export MWD=`pwd`
export MWD_ORIG=$(realpath `pwd`) # may be useful for chroot
export TARGET_TRIPLET=
export GENERIC_SANITY_CHECK_SH=${MWD}/scripts/generic_sanity_check.sh

# produce static binaries by default
# command-line may override this, and targets/* may override command-line
if [ -z "$STATIC_LINK" ] ; then
    STATIC_LINK=yes
fi

ARCH_LIN="i686 x86_64 arm aarch64"
ARCH_WIN='win32 win64 winarm winarm64'

SITE_MUSL=http://musl.cc 
SITE_MINGW=${SITE_MUSL}
SITE_WCROSS=https://sourceforge.net/projects/wdl/files/wcross
# toolchains.bootlin.com
SITE_BOOTLIN=

#arch    triplet               tarball
#i686    i686-linux-musl        i686-linux-musl-cross.tgz
#x86_64  x86_64-linux-musl      x86_64-linux-musl-cross.tgz
#arm     armv6-linux-musleabihf armv6-linux-musleabihf-cross.tgz
#aarch64 aarch64-linux-musl     aarch64-linux-musl-cross.tgz
#
#win32     i686-w64-mingw32    i686-w64-mingw32-cross.tgz   1
#win64     x86_64-w64-mingw32  x86_64-w64-mingw32-cross.tgz 1
#win32llvm i686-w64-mingw32
#win64llvm x86_64-w64-mingw32
#winarm    armv7-w64-mingw32
#winarm64  aarch64-w64-mingw32
#
#freebsd i686-pc-freebsd11

ARCH=`uname -m`
export OS_ARCH=$ARCH

function fatal_error() { echo -e "$@" ; exit 1 ; }
function exit_error() { echo -e "$@" ; exit 1 ; }

if [ -f .fatal ] ; then
    rm -f .fatal
fi

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

case "$1" in
	tgz)
		if [ "$2" ] ; then
			ARCHES=${2}
		else
			ARCHES=${ARCH_LIN}
		fi
		#--
		for xxarch in ${ARCHES}
		do
			dir=$(pwd)/out_static/00_${xxarch}
			if [ ! -d "$dir" ] ; then
				continue
			fi
			pkgs=$(find ${dir}/pkg -maxdepth 2 -type d -name '*_wstatic')
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
			ARCHES=${2}
		else
			ARCHES=${ARCH_LIN}
		fi
		#--
		for xxarch in ${ARCHES}
		do
			cd ${MWD}/out_static
			rootdir=00_${xxarch}
			if ! [ -d $rootdir ] ; then
				continue
			fi
			pkg_dir=static_packages-$(date "+%Y%m%d")-${xxarch}
			pkgs=$(find $rootdir -maxdepth 2 -type d -name '*_wstatic')
			if [ -z "$pkgs" ] ; then
				continue
			fi
			echo "Creating SFS file for $pkg_dir"
			mkdir -p ${pkg_dir}
			for i in ${pkgs} ; do
				cp -a --remove-destination ${i}/* ${pkg_dir}/
			done
			mksquashfs ${pkg_dir} ${pkg_dir}.sfs -comp gzip
			echo "Finished: ${pkg_dir}.sfs"
			echo
		done
		exit
		;;
esac

#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

help_msg() {
	echo "Build static packages

Usage: 

 [] use build.conf to automate target arch and packages to compile

  # $0 [-f] <-target arch> <-pkg pkg> [opts]
       target can be '${ARCH_LIN}'
       -target & -pkg can also be 'all'
       -f: rebuild and overwrite existing packages
  # $0 -targets (list all possible targets, includes mingw, etc)

  # $0 [-f] initrd
  # $0 [-f] initrd_progs
       produce initrd_progs-DATE.tar.xz (initrd_progs.conf)
       -f: rebuild and overwrite existing packages

  # $0 -download
  # $0 sfs  [arch] (create sfs file of all the compiled packages - 1 sfs per arch)
  # $0 tgz [arch] (create tgz packages of all the compiled packages)

The compiled binaries and pacakges can be found in output_static/00_ARCH/
"
	exit
}

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
			TARGET_ARCH='all'
			export DLD_ONLY='yes'
			shift
			#break
			;;
		-p|-pkg)
			BUILD_PKG="$2" ; shift 2
			[ "$BUILD_PKG" = "" ] && fatal_error "$0 -pkg: Specify a pkg to compile"
			PACKAGES=${BUILD_PKG}
			;;
		-a|-arch|-t|-target)
			TARGET_ARCH="$2"    ; shift 2
			[ "$TARGET_ARCH" = "" ] && fatal_error "$0 -arch: Specify a target arch" ;;
		-targets) ls ${MWD}/targets/ ; exit 0 ;;
		-h|-help|--help)
			help_msg
			exit ;;
		tarball|initrd|initrd_progs)
			if ! . ./initrd_progs.conf ; then
				exit_error 'initrd_progs.conf is missing'
			fi
			export INITRD_PROGS
			ipr=out_static/initrd_progs-$(date "+%Y%m%d")-static.tar.xz
			if [ "$FORCE_BUILD" = "" ] && [ -f $ipr ] ; then
				exit_error " -- File $ipr already exists\n Use -f to overwrite"
			fi
			PACKAGES=$(echo "$INITRD_PROGS"  | sed -e '/^$/d' -e '/^#.*/d' | cut -f 1 -d ':')
			TARGET_ARCH='all'
			break
			;;

		-f|f) export FORCE_BUILD=1;  shift ;;
		-static) STATIC_LINK=yes ;  shift ;;
		-shared) STATIC_LINK=no  ;  shift ;;
		-check)  WCROSS_MAKE_CHECK=yes  ;  shift ;;
		w|w_apps|c) PACKAGES='wbbox' ; TARGET_ARCH='all' ; break ;;

		-clean)
			echo -e "Press P and hit enter to proceed, any other combination to cancel.." ; read zz
			case $zz in p|P)
				rm -rf out_static 0sources cross-compiler* ;;
			esac
			exit
			;;
		chroot)
            PERFORM_CHROOT_ONLY=1
            TARGET_ARCH=alpine
            PACKAGES=none
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
	cd out_static
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

add_mold_to_toolchain() # x86_64 binary
{
    case ${TARGET_TRIPLET} in
        i?86*|x86_64*) ok=1 ;;
        *) return 0 ;;  # not supported
    esac
    if [ -z "$ADD_MOLD" ] ; then
        return 0
    fi
    echo "*** Add mold linker to toolchain..."
    if [ ! -f ${XPATH}/bin/mold ] ; then
        mold_file=${mold_url##*/} # basename
        mold_dir=${mold_file%.tar.*} # remove trailing .tar.gz
        retrieve ${mold_url}
        tar --strip=2 -C ${XPATH}/bin -xf ${MWD}/0sources/${mold_file} ${mold_dir}/bin/mold
    fi
    if [ -f ${XPATH}/bin/mold ] ; then
        ln -snfv mold ${XPATH}/bin/${TARGET_TRIPLET}-ld.mold
    fi
}


install_musl_compat_headers() # $1: install prefix
{
    xcurdirx=$(pwd)
    cd ${MWD}/pkg_src/musl-compat-headers
    make PREFIX=${1} install
    cd ${xcurdirx}
}

#==============================================================

function setup_compiler_cross()
{
    unset TARGET_TRIPLET
    unset CC_TARBALL
    unset TARBALL_SPECS
    unset TARBALL_URL
    unset TARBALL_ARCH
    unset COMPILER_SYMLINK
    #--
    case $TARGET_ARCH in
        default)  TARGET_ARCH=${OS_ARCH} ;;
        i*86|x86) TARGET_ARCH=i686    ;;
        arm64)    TARGET_ARCH=aarch64 ;;
        armv6|armv6l) TARGET_ARCH=arm ;;
    esac
    #--
    if [ -e "${MWD}/targets/${TARGET_ARCH}" ] ; then
        . ${MWD}/targets/${TARGET_ARCH}
        if [ -L "${MWD}/targets/${TARGET_ARCH}" ] && [ -z "$DONT_FOLLOW_TARGET_SYMLINK" ] ; then
            TARGET_ARCH=`readlink ${MWD}/targets/${TARGET_ARCH}`
        fi
        ARCH=${TARGET_ARCH}
        if [ -n "$TARBALL_URL" ] ; then
            SITE=${TARBALL_URL%/*}        # dirname
            CC_TARBALL=${TARBALL_URL##*/} # basename
        fi
    fi
    #--
    if [ -z "$CC_TARBALL" ] ; then
        exit_error "Cross compiler for $ARCH is not available."
    fi
    export TARGET_TRIPLET
    export CPU_ARCH=${TARGET_TRIPLET%%-*} # ex: i686, x86_64
    export XCOMPILER=${TARGET_TRIPLET}
    export WCROSS_PREFIX=${TARGET_TRIPLET}-
    #--
    echo -e "\n*** Arch: $ARCH  [$TARGET_TRIPLET]"
    sleep 1.0

    #--------------------------------------------

    TARBALL_DIR=${CC_TARBALL%.tar.*}  # remove trailing *.tar.*
    TARBALL_DIR=${TARBALL_DIR%.tgz}   # remove trailing .tgz
    TARBALL_DIR=${TARBALL_DIR%.txz}   # remove trailing .txz
    CC_DIR=cross-compiler/${TARBALL_DIR}
    export OVERRIDE_ARCH=${ARCH}   # see ./func
    export XPATH=${PWD}/${CC_DIR}  # see ./func
    echo
    mkdir -p cross-compiler
    cd cross-compiler
    (
    # --subshell--
    # currently using cross compilers from musl.cc
    # we're in $MWD/cross-compiler
    . ${MWD}/func
    retrieve ${SITE}/${CC_TARBALL}
    retrieve ${MUSL_URL}
    retrieve ${MINGW_URL}
    if [ "$DLD_ONLY" = "yes" ] ; then
        exit 0
    fi
    #--
    opts=''
    if [ ! -d ${XPATH} ] ; then
        extract ${CC_TARBALL}
        cd ${XPATH} || exit 1
        sync
        update_toolchain_root
        if [ -n "$TARBALL_SPECS" ] ; then
            echo "$TARBALL_SPECS" > specs.txt
        fi
        # ----
        sync
        echo "# ${MWD}/scripts/after_tarball_extract.sh"
        ${MWD}/scripts/after_tarball_extract.sh
        add_mold_to_toolchain
        install_musl_compat_headers ${TOOLCHAIN_INSTALL_PREFIX}/usr
    fi
    #--
    case ${TARGET_TRIPLET} in *musl*)
      if [ "$MUSL_VERSION" != "$MUSL_CC_VERSION" ] ; then
        echo "# ${GENERIC_SANITY_CHECK_SH}"
        . ${GENERIC_SANITY_CHECK_SH}
        if [ ! -d ${TOOLCHAIN_ROOT}/include/linux ] ; then
            echo -e "\nCompiling musl $MUSL_VERSION"
            SRC_URL=${LINUX_HEADER_URL}
            SRC_FILE=${SRC_URL##*/}    # basename
            SRC_DIR=${SRC_FILE%.tar.*} # remove trailing .tar.*
            #--
            extract ${SRC_FILE} || exit 1
            cd ${SRC_DIR} || exit 1
            #--
            xarch=$(uname -m)
            case ${xarch} in
                i?86) xarch=x86 ;;
                arm*) xarch=arm ;;
            esac
            #--
            make prefix=${TOOLCHAIN_ROOT} ARCH=${xarch} install
            cd ..
            rm -rf ${SRC_DIR}
        fi
        if [ ! -f ${XPATH}/musl_${MUSL_VERSION} ] ; then
            echo -e "\nCompiling musl $MUSL_VERSION"
            sleep 2
            SRC_URL=${MUSL_URL}
            SRC_FILE=${SRC_URL##*/}    # basename
            SRC_DIR=${SRC_FILE%.tar.*} # remove trailing .tar.*
            #--
            extract ${SRC_FILE}
            cd ${SRC_DIR}
            _configure --prefix=${TOOLCHAIN_ROOT} --syslibdir=${TOOLCHAIN_ROOT}/lib
            _make
            _make install
            #--
            cd ..
            rm -rf ${SRC_DIR}/*
            echo -n > ${XPATH}/musl_${MUSL_VERSION}
        fi
      fi ;;
    esac
    #--
    case ${TARGET_TRIPLET} in *xxxmingwxxx*) # *mingw*
      if [ "$MINGW_VERSION" != "$MINGW_CC_VERSION" ] ; then
        case ${TARGET_TRIPLET} in
            x86_64*) crt_lib='--enable-lib64 --disable-lib32' ;;
            i686*)   crt_lib='--enable-lib32 --disable-lib64' ;;
            *) exit 0 ;; #aarch64 armv7
        esac
        mcrt='ucrt' # msvcrt
        if [ ! -f ${XPATH}/mingw_${MINGW_VERSION} ] ; then
            # https://github.com/Zeranoe/mingw-w64-build
            echo -e "\nCompiling MinGW $MINGW_VERSION"
            sleep 2
            SRC_URL=${MINGW_URL}
            SRC_FILE=${SRC_URL##*/}    # basename
            SRC_DIR=${SRC_FILE%.tar.*} # remove trailing .tar.*
            #--
            extract ${SRC_FILE}
            cd ${SRC_DIR}
            #--
            cd mingw-w64-headers
            _configure --prefix=${XPATH}/${TARGET_TRIPLET} --with-default-msvcrt=${mcrt}
            make install
            cd ..
            #--
            cd mingw-w64-crt
            _configure --prefix=${XPATH}/${TARGET_TRIPLET} --with-default-msvcrt=${mcrt} ${crt_lib} # --with-sysroot=${XPATH}/${TARGET_TRIPLET}
            make install
            cd ..
            #--
            cd mingw-w64-libraries/winpthreads
            _configure --prefix=${XPATH}/${TARGET_TRIPLET} --disable-shared --enable-static
            make install
            cd ../../../
            #--
            rm -rf ${SRC_DIR}/*
            echo -n > ${XPATH}/mingw_${MINGW_VERSION}
        fi
      fi ;;
    esac
    ) # end of subshell
    if [ $? -ne 0 ] ; then
        exit_error
    fi

    echo $XPATH
    echo "# ${GENERIC_SANITY_CHECK_SH}"
    . ${GENERIC_SANITY_CHECK_SH}
    cd $MWD
}

#==============================================================

function setup_compiler_chroot()
{
    # --subshell--
    # Alpine Linux minimal chroot 
    # https://wiki.alpinelinux.org/wiki/Alpine_Linux_in_a_chroot
    . ${MWD}/func
    alpine_major_ver=${ALPINE_LINUX_VER%.*}
    #--
    alpine_arch=${OS_ARCH}
    case ${OS_ARCH} in
        i?86)    alpine_arch=x86     ;;
        x86_64)  alpine_arch=x86     ;; # want to compile i686 static binaries... always
        armv*)   alpine_arch=armhf   ;; # armv7
        *) echo "0$: $(uname -m) currently not supported.. edit me"
            exit ;;
    esac
    #--
    alpine_dir=v${alpine_major_ver}/releases/${alpine_arch}
    alpine_tarball=alpine-minirootfs-${ALPINE_LINUX_VER}-${alpine_arch}.tar.gz
    alpine_url=${ALPINE_LINUX_SITE}/${alpine_dir}/${alpine_tarball}
    #--
    retrieve ${alpine_url}
    if [ "$DLD_ONLY" = "yes" ] ; then
        exit 0
    fi
    #--
    if ! [ -f bin/busybox ] ; then
        extract ${alpine_tarball}
    fi
    #--
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
        zzdir=0sources/alpine_${alpine_arch}_${alpine_major_ver}
        mkdir -p ${MWD}/${zzdir}
        ln -snfv /WBUILDS/${zzdir} etc/apk/cache
        sync
    fi
    #--
    apk_add='apk add --allow-untrusted'
    #--
    if ! [ -e bin/bash ] ; then
        # --no-cache
        # base
        chroot . ${apk_add} build-base bash linux-headers
        chroot . ${apk_add} gcc-gnat gfortran gcc-go gcc-objc gcc-gdc libucontext-dev
        # extra build tools
        chroot . ${apk_add} cmake autoconf automake libtool bison mold samurai
        chroot . ${apk_add} bmake mk-configure mk-configure-dev # bsd
        chroot . ${apk_add} nasm yasm yasm-dev #uasm    # assemblers
        # essential dev apps
        chroot . ${apk_add} git gdb
        # python
        chroot . ${apk_add} meson scons waf py3-setuptools
        # tools
        chroot . ${apk_add} lzip tar xz gzip unzip zip bzip2
        # gtk
        #chroot . ${apk_add} gtk4.0-dev geany 
        # libs
        chroot . ${apk_add} \
            acl-static acl-dev \
            bzip2-static bzip2-dev \
            libftdi1-static libftdi1-dev \
            zlib-static zlib-dev
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
	mkdir -p out_static/00_${ARCH}/bin out_static/00_${ARCH}/log 0sources
	#--
	for one_pkg in ${PACKAGES}
	do
		case $one_pkg in ""|'#'*) continue ;; esac
		if [ -f .fatal ] ; then
			rm -f .fatal_error
			exit_error "Exiting.."
		fi
		#--
		export BUILD_PACKAGE=${one_pkg}
		#--
		pkg_dot_sbuild=''
        for i in ${one_pkg}.sbuild \
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
		mkdir -p ${MWD}/out_static/00_${ARCH}/log
		#--
		if [ "$BUILD_TYPE" = "chroot" ] ; then
			# with a chroot some variables must be modified
			MWD=/WBUILDS \
			XPATH=/WBUILDS/${CC_DIR} \
			chroot ${CHROOT_DIR} bash /WBUILDS/pkg/${build_script} ${pkg_dot_sbuild} 2>&1 | \
				tee ${MWD}/out_static/00_${ARCH}/log/${one_pkg}-chroot-build.log
		else
			# specify full script path, may need to get the script dir
			bash ${MWD}/pkg/${build_script} ${pkg_dot_sbuild} 2>&1 | \
				tee ${MWD}/out_static/00_${ARCH}/log/${one_pkg}--build.log
		fi
		cd ${MWD}
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

case $TARGET_ARCH in
    all) all=1 ;; # all: special target to cross-compile a pkg using several linux cross-compilers
    chroot|alpine) BUILD_TYPE='chroot' ;;
    system)        BUILD_TYPE='system' ;;
    *)
        if [ -e "${MWD}/${TARGET_ARCH}" ] ; then
            . ${TARGET_ARCH}
            TARGET_ARCH=${TARGET_ARCH##*/}
        elif [ -e "${MWD}/targets/${TARGET_ARCH}" ] ; then
            . ${MWD}/targets/${TARGET_ARCH}
        else
            exit_error "$TARGET_ARCH is not a valid target"
        fi
        ;;
esac

# chroot & system = linux
# if cross-compiling, the target/xxx has already set TARGET_TRIPLET
WCROSS_TARGET_OS='linux'  # default
WCROSS_TARGET_POSIX='yes' # default
case ${TARGET_TRIPLET} in
    # other than linux, wcross supports only *bsd and mingw cross-compilers
    *freebsd*) WCROSS_TARGET_OS='freebsd' ;;
    *openbsd*) WCROSS_TARGET_OS='openbsd' ;;
    *netbsd*)  WCROSS_TARGET_OS='netbsd' ;;
    *mingw*)   WCROSS_TARGET_OS='windows' ; WCROSS_TARGET_POSIX='' ;;
esac
export WCROSS_TARGET_OS
export WCROSS_TARGET_POSIX

export BUILD_TYPE
export STATIC_LINK
export WCROSS_MAKE_CHECK
#echo "$BUILD_TYPE" # debug

if [ "$BUILD_TYPE" = "system" ] ; then
    # system gcc & libs
    if [ "$TARGET_TRIPLET" = "system" ] ; then
        # TARGET_TRIPLET='system' may be set by a target/file (i.e. target/system-default)
        export CPU_ARCH=${OS_ARCH}
        CC_DIR="cross-compiler/system-${OS_ARCH}"
    else
        export CPU_ARCH=$(echo $TARGET_TRIPLET | cut -f 1 -d '-')
        export WCROSS_PREFIX=${TARGET_TRIPLET}-
        CC_DIR=cross-compiler/system-${TARGET_TRIPLET}
    fi
    export OVERRIDE_ARCH=${ARCH}   # see ./func
    export XPATH=${PWD}/${CC_DIR}  # see ./func
    #--
    if [ ! -d ${XPATH} ] ; then
        mkdir -p ${XPATH}/bin
        mkdir -p ${XPATH}/lib
        ln -sv ./ ${XPATH}/usr
    fi
    build_pkgs
    exit $?

elif [ "$BUILD_TYPE" = "chroot" ] ; then
    export CC_DIR=cross-compiler/${OS_ARCH}-chroot-musl
    export OVERRIDE_ARCH=${ARCH}   # see ./func
    export XPATH=${PWD}/${CC_DIR}
    export CHROOT_DIR=${XPATH}
    export CPU_ARCH=${OS_ARCH}
    mkdir -p ${CC_DIR}
    cd ${CC_DIR}
    ( setup_compiler_chroot )
    if [ $? -ne 0 ] ; then
        exit_error
    fi
    if [ -n "$PERFORM_CHROOT_ONLY" ] ; then
        echo " ** Performing Alpine chroot only, then you can do whatever you want inside"
        chroot . ls
        exec chroot . sh
    fi
    cd ${MWD}
    build_pkgs
    exit $?

else
    # cross compilers
    ARCHES=${TARGET_ARCH}
    case $TARGET_ARCH in
        all)
            ARCHES=${ARCH_LIN}
            # also include $ARCH_WIN if downloading only
            if [ "$DLD_ONLY" = "yes" ] ; then
                ARCHES="${ARCH_LIN} ${ARCH_WIN}"
            fi
            ;;
        "") echo -e "\nMust specify target arch: -a <arch>"
            echo "  <arch> can be one of these: $ARCH_LIN default"
            echo -e "\nSee also: $0 --help"
            exit 1 ;;
    esac
    #--
    for i in $ARCHES
    do
        TARGET_ARCH=${i}
        setup_compiler_cross
        build_pkgs
        cd ${MWD}
    done
fi

if [ "$INITRD_PROGS" ] ; then
    create_initrd_progs_tarball
fi

### END ###

	# fix config.h instead of configure.ac
	# #define malloc rpl_malloc
	#sed -i -e '/rpl_malloc/d' -e '/rpl_realloc/d' config.h
