#!/bin/bash
#
# Public Domain
#
# ** uses functions from $MWD/functions.sh (must be sourced first)
#
# this is sourced by
# - pkg/00_pkg_build   (uses everything)
# - pkg/00_local_build (uses a few functiones to compile)
#
# build.sh exports some important variables that are used everywhere
# However all exported variables can be empty except $MWD, $XPATH and $BUILD_TYPE
#
# - MWD        (main directory)
# - OS_ARCH    (running system arch)
# - BUILD_TYPE (cross / chroot / system)
# - WCROSS_TARGET_OS    (linux / windows / freebsd / netbsd / windows)
# - WCROSS_TARGET_POSIX (yes / [empty])
#
#   if /WBUILDS exists... then it's a chroot and BUILD_TYPE=chroot
#
# - XPATH    (cross compiler root dir)
#  (scripts should use TOOLCHAIN_ROOT which is set in this script)
#   - TOOLCHAIN_ROOT (target toolchain rootdir) [exported]
#   - INSTALL_DIR    (pkg install dir)
#   - GCC_SYSROOT = --sysroot=<proper_dir>     [exported]
#   - GCC_INCLUDE = -I=<proper_dir>            [exported]
#   - GCC_LIB     = -L=<proper_dir>            [exported]
#   - W_SYSROOT   = $TOOLCHAIN_ROOT            [exported]
#   - TOOLCHAIN_INSTALL_PREFIX (where to install libs) [not exported]
#                              (this works for all BUILD_TYPEs)
#   - TOOLCHAIN_SYSROOT_BIN  (bin directory for toolchain
#                             to store -config files and stuff)
#   - TOOLCHAIN_INSTALL_LIBDIR (lib directory for toolchain)
#
# BUILD_TYPE=cross
# - TARGET_TRIPLET (ie: i686-linux-musl)
# - XCOMPILER      (ie: i686-linux-musl)
# - WCROSS_PREFIX  (ie: i686-linux-musl-)
#
# These flags are generated according to some rules
# They work the same for static and shared builds, can be used anywhere
# - WMK_CFLAGS
# - WMK_CXXFLAGS
# - WMK_LDFLAGS
#
# The flags only influence paths and linking, but when it comes to creating static libraries
# it's a particular setting that must be set for each project (in the .sbuild files)

#=====================================================================

if [ -z "${MWD}" ] ; then
	echo "Use build.sh"
	exit 1
fi

if ! [ "$BUILD_CONF" ] ; then
	BUILD_CONF=${MWD}/build.conf
fi
if ! [ -f ${BUILD_CONF} ] ; then
	echo "build.conf not found"
	exit 1
fi
. ${BUILD_CONF}

BUILDTMP=${MWD}/build_tmp/${WTARGET}
pkgdir_all=${MWD}/out_w/00_${WTARGET}/pkg_all

#=====================================================================

if [ "$STATIC_LINK" = "yes" ] ; then
    ## flags to force static libc
    export GCC_STATIC="-static"
    # fix static apps: _make LDFLAGS=${GCC_ALL_STATIC}
    export GCC_ALL_STATIC="-all-static"
    # --static = -all-static (this is basically for autotools (libtool) projets)
    #            (if it doesn't work then Makefile.in/am must be fixed) 
    export GCC__STATIC="--static"
    # only static libs are compiled, so we always need the private
    # part of pkg-config files
    #   https://stackoverflow.com/questions/21027388/how-to-make-pkg-check-modules-work-with-static-libraries
    #   PKG_CHECK_MODULES_STATIC works for pkg-config > 0.29
    export PKG_CONFIG="pkg-config --static"
    # wconf configure recognizes this var (needs fixing to work just like autoconf)
    export W_PKG_CONFIG_STATIC=1
    # WARNING: things may be broken when using the system gcc
    #          need static flags only for the packages compiled, not the whole system
    #          and both scenarios [static & shared] are broken with the system gcc
    #          Probably need to manually fix .pc files to include --static libs by default
fi


if [ "$BUILD_TYPE" = "chroot" ] ; then
	WLDFLAGS=${WLDFLAGS_CHROOT}
	WCFLAGS=${WCFLAGS_CHROOT}
elif [ "$BUILD_TYPE" = "system" ] ; then
	WLDFLAGS=${WLDFLAGS_SYSTEM}
	WCFLAGS=${WCFLAGS_SYSTEM}
elif [ "$BUILD_TYPE" = "cross" ] ; then
	WLDFLAGS=${WLDFLAGS_CROSS}
	WCFLAGS=${WCFLAGS_CROSS}
fi

WMK_CFLAGS="$(echo $CFLAGS $WCFLAGS $WCFLAGS2)"
WMK_CXXFLAGS="$CXXFLAGS"
WMK_LDFLAGS="$(echo $LDFLAGS $GCC_STATIC $GCC__STATIC $WLDFLAGS $WLDFLAGS2)"


if [ -d /WBUILDS ] ; then
    BUILD_TYPE='chroot'
    TOOLCHAIN_ROOT=/
    TOOLCHAIN_INSTALL_PREFIX=/usr
    TOOLCHAIN_INSTALL_LIBDIR=/usr/${WLIBDIR}
    TOOLCHAIN_SYSROOT_BIN=/usr/bin
    unset GCC_SYSROOT GCC_INCLUDE GCC_LIB
    unset W_SYSROOT
else
    # anything other than chroot requires $XPATH to store libs and headers
    # ${XPATH}/bin contains special apps (usually the cross-compiler)
    if [ -e "${XPATH}/${TARGET_TRIPLET}" ] ; then
        # cross sysroot
        # /bin /lib are reserved for the cross compiler apps/libs
        export TOOLCHAIN_ROOT=${XPATH}/${TARGET_TRIPLET}
        TOOLCHAIN_INSTALL_PREFIX=${TOOLCHAIN_ROOT}
        TOOLCHAIN_INSTALL_LIBDIR=${TOOLCHAIN_ROOT}/${WLIBDIR}
        ## Need to set the toolchain sysroot bindir for -config files 
        if [ -e ${XPATH}/${TARGET_TRIPLET}/bin/ld ] ; then
            # this is a gcc toolchain that contains only 1 cross compiler / toolchain
            # no need to export an extra bin path
            # everything must go to ${XPATH}/bin
            TOOLCHAIN_SYSROOT_BIN=${XPATH}/bin
        else
            # asumme it's a clang toolchain which can compile for many targets
            # and each target includes a sysroot
            TOOLCHAIN_SYSROOT_BIN=${XPATH}/${TARGET_TRIPLET}/bin
            PATH=${TOOLCHAIN_SYSROOT_BIN}:${PATH}
        fi
    else
        # system
        export TOOLCHAIN_ROOT=${XPATH}
        TOOLCHAIN_INSTALL_PREFIX=${XPATH}/usr
        TOOLCHAIN_INSTALL_LIBDIR=${XPATH}/usr/${WLIBDIR}
        TOOLCHAIN_SYSROOT_BIN=${XPATH}/bin
    fi
    PATH=${XPATH}/bin:${PATH}
    if [ -d ${MWD}/0wsys-${OS_ARCH}/bin ] ; then
		PATH=${MWD}/0wsys-${OS_ARCH}/bin:${PATH}
	fi
    if [ -d ${MWD}/0wsys/bin ] ; then #static binaries?
        PATH=${MWD}/0wsys/bin:${PATH}
    fi
    export PATH
    #--
    export GCC_INCLUDE="-I${TOOLCHAIN_ROOT}/include" # CFLAGS
    export GCC_LIB="-L${TOOLCHAIN_ROOT}/${WLIBDIR}"  # LDFLAGS
    #--
    WMK_CFLAGS="$WMK_CFLAGS $GCC_INCLUDE"
    WMK_CXXFLAGS="$WMK_CXXFLAGS $GCC_INCLUDE"
    WMK_LDFLAGS="$WMK_LDFLAGS $GCC_LIB"
fi


if [ "$BUILD_TYPE" = "chroot" ] ; then
    # only BUILD_TYPE='chroot' installs to the system dir (inside the chroot)
    export PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin
    export LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib
    export PKG_CONFIG_PATH=/usr/lib/pkgconfig:/usr/share/pkgconfig:/lib/pkgconfig
    #--
elif [ "$BUILD_TYPE" = "system" ] ; then
    # $TOOLCHAIN_ROOT headers & libs + system headers & libs
    # WLIBDIR can lib or lib64
    export PATH=${XPATH}/bin:${PATH}
    export LD_LIBRARY_PATH=${TOOLCHAIN_ROOT}/${WLIBDIR}:${LD_LIBRARY_PATH}
    export PKG_CONFIG_PATH=${TOOLCHAIN_ROOT}/${WLIBDIR}/pkgconfig:${PKG_CONFIG_PATH}
    export CPATH=${TOOLCHAIN_ROOT}/include
elif [ "$BUILD_TYPE" = "cross" ] ; then
    # - ${TOOLCHAIN_ROOT}/usr is a symlink
    #--
    export W_SYSROOT=${TOOLCHAIN_ROOT}
    export GCC_SYSROOT="--sysroot=${W_SYSROOT}" # CFLAGS
    WMK_CFLAGS="$GCC_SYSROOT $WMK_CFLAGS"
    WMK_CXXFLAGS="$GCC_SYSROOT $WMK_CXXFLAGS"
    #--
    export XCOMPILER=${TARGET_TRIPLET}
    export WCROSS_PREFIX=${TARGET_TRIPLET}-
    #--
    # ${XPATH}/lib should only contain libs need to to run the
    # toolchain binaries and to add stuff to the compiler itself
    export LD_LIBRARY_PATH=${XPATH}/lib:${LD_LIBRARY_PATH}
    export PKG_CONFIG_PATH=${TOOLCHAIN_ROOT}/lib/pkgconfig
    export PKG_CONFIG_LIBDIR=${TOOLCHAIN_ROOT}/lib
    #export PKG_CONFIG_SYSROOT_DIR=${TOOLCHAIN_ROOT}
    #export PKG_CONFIG_DEBUG_SPEW=1
    # dont use: CPATH, *_INCLUDE_PATH
    #           these break the system compiler and configure fail (among other things)
    # cross compiler:
    #           run `./xxx-xxx-gcc -print-prog-name=cc1` -v
    #           to determine the include paths, and create a symlink if needed
    #--
    ## system pkg-config must always exist (even as a symlink to pkgconf)
    ## create pkg-config with cross profix (exported variables make it usable)
    if [ ! -e ${XPATH}/bin/${TARGET_TRIPLET}-pkg-config ] ; then
        ln -snfv $(command -v pkg-config) ${XPATH}/bin/${TARGET_TRIPLET}-pkg-config
    fi
else
    exit_error "invalid \$BUILD_TYPE: $BUILD_TYPE"
fi

# don't add LDFLAGS / CFLAGS / CXXFLAGS to this list (see _make)
CROSS_MK_PARAMS="CC=${WCROSS_PREFIX}gcc
CCX=${WCROSS_PREFIX}g++
CXX=${WCROSS_PREFIX}g++
AR=${WCROSS_PREFIX}ar
AS=${WCROSS_PREFIX}as
LD=${WCROSS_PREFIX}ld
RANLIB=${WCROSS_PREFIX}ranlib
NM=${WCROSS_PREFIX}nm
STRIP=${WCROSS_PREFIX}strip
OC=${WCROSS_PREFIX}objcopy
OBJCOPY=${WCROSS_PREFIX}objcopy
OBJDUMP=${WCROSS_PREFIX}objdump
READELF=${WCROSS_PREFIX}readelf
SIZE=${WCROSS_PREFIX}size
STRINGS=${WCROSS_PREFIX}strings
GFORTRAN=${WCROSS_PREFIX}gfortran"

#----------------------
eval "$CROSS_MK_PARAMS"
#----------------------

#=====================================================================

function exit_error()
{
	echo -n > $MWD/.fatal
	if [ "$1" ] ; then
		echo "$@"
	fi
	echo " //// ERROR IN: $0"
	if [ -n "$PKG_SCRIPT" ] ; then
		echo " //// PKG_SCRIPT: ${PKG_SCRIPT}"
	fi
	exit 1
}


function build_sanity_check()
{
	if [ -z "$pkgname" ] ; then
		exit_error "\$pkgname has not been set, this must be fixed"
	fi
	if [ -n "$LINUX_ONLY" ] && [ "$WCROSS_TARGET_OS" != "linux" ] ; then
		exit_ok "This pkg ($pkgname) only compiles with a Linux compiler"
	fi
	if [ -n "$WINDOWS_ONLY" ]  && [ "$WCROSS_TARGET_OS" != "windows" ] ; then
		exit_ok "This pkg ($pkgname) only compiles with a MinGW cross compiler"
	fi
	if [ -n "$POSIX_ONLY" ] && [ "$WCROSS_TARGET_POSIX" != "yes" ] ; then
		exit_ok "This pkg ($pkgname) only compiles with compilers for POSIX systems"
	fi
	if [ "$BUILD_TYPE" = "chroot" ] && [ -n "$CHROOT_ALREADY_INSTALLED" ] ; then
		# using chroot with the latest apps, no need to compile some apps
		echo "CHROOT: $pkgname should already be installed, skipping.."
		exit 0
	fi
	if [ -n "$REQUIRED_APPS" ] ; then
		abort_if_app_is_missing ${REQUIRED_APPS}
	fi
	# set $INSTALL_DIR
	A=${WTARGET}
	A=${A#chroot-}
	A=${A#system-}
	if [ -n "$PKGDIR_ARCH" ] ; then
		# this is specified in xxx.sbuild (i.e: noarch)
		A=${PKGDIR_ARCH}
	fi
	if [ -z "$pkgrel" ] ; then
		pkgrel=0
	fi
	if [ "$STATIC_LINK" = "yes" ] ; then
		case ${WTARGET} in i?86) A=x86 ;; esac
		INSTALL_DIR=${MWD}/out_w/00_${WTARGET}/pkg/${pkgname}-${pkgver}-r${pkgrel}.${A}_wstatic
	else
		INSTALL_DIR=${MWD}/out_w/00_${WTARGET}/pkg/${pkgname}-${pkgver}-r${pkgrel}.${A}_w
	fi
	pkgdir=${INSTALL_DIR} # APKBUILD (alpine)
}


function extract_pkg()
{
	extract_archive "$@"
	echo -e "\n+============================================================================="
	echo -e "\nbuilding $@"
}


function extract_pkg_and_cd() #requires $SRC_FILE & $SRC_DIR
{
	if [ -z "$SRC_FILE" ] ; then
		exit_error '$SRC_FILE is empty -- fix the script'
	fi
	if [ -z "$SRC_DIR" ] ; then
		exit_error '$SRC_DIR is empty -- fix the script'
	fi
	if [ "$PKGDIR_FILE" ] || [ "$TOOLCHAIN_FILE" ] ; then
		check_installed_file
	fi
    #--
	# cd to temp build dir
	if ! [ -d ${BUILDTMP} ] ; then
		mkdir -p ${BUILDTMP}
	fi
	cd ${BUILDTMP}
    #--
    if [ -n "$SRC_DIR_NEED_TO_CREATE" ] ; then
        # tarball contains everything in the root dir
        mkdir -p ${SRC_DIR}
        cd ${SRC_DIR}
        extract_pkg ${SRC_FILE}
    else
        extract_pkg ${SRC_FILE}
        cd ${SRC_DIR}
        if [ $? -ne 0 ] ; then
            exit_error "(extract_pkg_and_cd): wrong dir? you should set SRC_DIR= in $PKG_SCRIPT"
        fi
    fi
    patch_pkg
    unset SRC_DIR_NEED_TO_CREATE
}


function abort_if_file_not_found()
{
	if ! [ "$1" ] ; then
		[ -n "${INSTALL_DIR}" ] && rm -rf ${INSTALL_DIR}
		exit_error "abort_if_file_not_found: no filename has been provided"
	fi
	for onefile in "$@" ; do
		if [ ! -f "$onefile" ] ; then
			[ -n "${INSTALL_DIR}" ] && rm -rf ${INSTALL_DIR}
			echo "$onefile: file does no exist!"
			exit_error
		fi
	done
}

#=====================================================================

function _cmake()
{
	rm -rf builddir
	mkdir builddir
	cmd_echo2 cd builddir

	CMAKE_OPTS="$opts $W_OPTS"
	if [ "$STATIC_LINK" = "yes" ] ; then
		# https://stackoverflow.com/a/51126719
		# this is overriden by project(), so may need to patch CMakeLists.txt...
		CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_FIND_LIBRARY_SUFFIXES=.a"
		# since cmake 3.4
		# Strongly suggest to a compiler to use static linkage by default.
		# This should make linking to static libc possible
		CMAKE_OPTS="${CMAKE_OPTS}
-DCMAKE_LINK_SEARCH_START_STATIC=ON
-DCMAKE_LINK_SEARCH_END_STATIC=ON"
		##https://answers.ros.org/question/231381/how-do-i-remove-rdynamic-from-link-options/
		#set(CMAKE_SHARED_LIBRARY_LINK_CXX_FLAGS "")
	fi
	#-- cmake regognizes da flags
	export_make_wflags
	#--
	if [ -n "$W_SYSROOT" ] ; then
		#-- https://stackoverflow.com/questions/67936256/how-to-cross-compile-with-cmake
		CMAKE_OPTS="${CMAKE_OPTS} -DCMAKE_TOOLCHAIN_FILE=my_toolchain.cmake"
		#--
		case ${TARGET_TRIPLET} in
			*mingw*)   WCROSS_SYSNAME='Windows' ;;
			*freebsd*) WCROSS_SYSNAME='FreeBSD' ;;
			*)         WCROSS_SYSNAME='Linux'   ;; # default
		esac
		#--
		cat > my_toolchain.cmake <<EOF
set(CMAKE_SYSTEM_NAME ${WCROSS_SYSNAME})
set(CMAKE_SYSTEM_PROCESSOR ${CPU_ARCH})
set(CMAKE_C_COMPILER ${WCROSS_PREFIX}gcc)
set(CMAKE_ASM_COMPILER ${WCROSS_PREFIX}gcc)
set(CMAKE_CXX_COMPILER ${WCROSS_PREFIX}g++)
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)
set(CMAKE_SYSROOT ${W_SYSROOT})
set(CMAKE_FIND_ROOT_PATH ${W_SYSROOT})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
	else
		# system cc: need to specify $TOOLCHAIN_ROOT if not using a chroot
		if [ ! -d /WBUILDS ] ; then
			CMAKE_OPTS="${CMAKE_OPTS}
-DCMAKE_FIND_ROOT_PATH=${TOOLCHAIN_ROOT}
-DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=BOTH
-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH
-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH
"
		fi
	fi
	hl_echo "cmake ${CMAKE_OPTS} $@ ../"
	cmake ${CMAKE_OPTS} "$@" ../
	if [ $? -ne 0 ] ; then
		exit_error
	fi
	#cmake -LH .. &> zzcmake.all.opts
	unset W_OPTS
}


export_make_wflags()
{
	# must pass LDFLAGS, CFLAGS and CXXFLAGS as env variables (env=xxx make ...)
	# - otherwise it's not possible to change or edit them
	# - if they are passed as make PARAM=xxx
	# change env CFLAGS & LDFLAGS only if they are empty
	# (provide W path and flags for compilation)
    # - add extra flags: EXTRA_CFLAGS / EXTRA_CXXFLAGS / EXTRA_LDFLAGS
	if [ -z "${CFLAGS}" ] ; then
		export CFLAGS="${WMK_CFLAGS} ${EXTRA_CFLAGS}"
		echo "# export CFLAGS=${WMK_CFLAGS} ${EXTRA_CFLAGS}"
	fi
	if [ -z "${CXXFLAGS}" ] ; then
		export CXXFLAGS="${WMK_CXXFLAGS} ${EXTRA_CXXFLAGS}"
		echo "# export CXXFLAGS=${WMK_CXXFLAGS} ${EXTRA_CXXFLAGS}"
	fi
	if [ -z "${LDFLAGS}" ] ; then
		export LDFLAGS="${WMK_LDFLAGS} ${EXTRA_LDFLAGS}"
		echo "# export LDFLAGS=${LDFLAGS} ${EXTRA_LDFLAGS}"
	fi
}


function _configure()
{
	# - special configure for autotools and compatible scripts (i.e: wconf)
	# - but also works with non-autotools configure scripts (not all)
	#   with special params specified in the .sbuild file (i.e: zlib, clzip)
	unset host
	#--
	unset CONFIGURE_CROSS
	if [ -d autosetup ] ; then
		# autosetup -- http://msteveb.github.io/autosetup/developer/
		CONFIGURE_CROSS=1
	elif [ -f configure.ac ] || [ -f configure.in ] ; then
		#autotools
		if [ -z "$W_AUTOGEN" ] ; then
			W_AUTOGEN='autogen.sh'
		fi
		export FORCE_UNSAFE_CONFIGURE=1
		if [ ! -f configure ] ; then
			echo "* configure script is missing"
			if [ -f ${W_AUTOGEN} ] ; then
				cmd_echo2 sh ${W_AUTOGEN}
			else
				cmd_echo2 autoreconf -vi
			fi
			if [ $? -ne 0 ] ; then
				env | grep -E '_PATH|_CONFIG'
				exit_error
			fi
			# always use the latest config.sub/config.guess after autoreconf
			update_config_sub
		fi
		#-- speep up some tests...
		cmd_echo2 fn_export_autoconf_vars ${TARGET_TRIPLET}
		#--
		CONFIGURE_CROSS=1
	elif [ -f configure.project ] ; then
		CONFIGURE_CROSS=1
	fi
	#--
	if ! [ -f configure ] ; then
		exit_error " --- configure script not found"
	fi
	CONF_OPTS="$opts $W_OPTS" #opts is set in the calling script
	case ${CONF_OPTS} in *--help*)
		./configure --help
		echo ; echo "--help: was detected, remove it from opts"
		exit_error #don't continue even if compiling dependency
		;;
	esac
	#--
	echo "PATH: $PATH"
	if [ -n "${XCOMPILER}" ] ; then
		# autotools and compatible configure scripts
		# --build=xxx + --host=yyy = cross compilation mode
		#      autotools will not run any test that require execution
		if [ "$CONFIGURE_CROSS" ] ; then
			CONF_OPTS="$CONF_OPTS --host=${XCOMPILER} --build=$(gcc -dumpmachine)"
		fi
	fi
	#--
	if [ -n "$DONT_OVERRIDE_FLAGS" ] ; then
		# ffmpeg requires empty CFLAGS & LDFLAGS
		unset CFLAGS CXXFLAGS LDFLAGS DONT_OVERRIDE_FLAGS
	else
		export_make_wflags
	fi
	#-
    if [ "$STATIC_LINK" = "yes" ] && [ -f configure.project ] && [ -z "$W_00_LOCAL_BUILD" ] ; then
        sed -i 's/ -g / /' configure.project
    fi
	# run script
	hl_echo "./configure $@ ${CONF_OPTS}"
	./configure "$@" ${CONF_OPTS}
	if [ $? -ne 0 ] ; then
		env | grep -E '_PATH|_CONFIG'
		exit_error
	fi
	unset W_OPTS CFLAGS CXXFLAGS LDFLAGS DONT_OVERRIDE_FLAGS
}


function _make()
{
	# - special make for projects without autotools and cmake
	# - works with autotools though
	# - don't use after _cmake
	# - just use 'make' if you want to avoid this complex logic or there's an issue 'cause by this func
	echo "PATH: $PATH"
	if [ -z "$WMAKE" ] ; then
		WMAKE="make ${MKFLG}"
	fi
	if [ -f configure ] || [ -e CMakeFiles ] || [ -f CMakeLists.txt ] ; then
		# don't add CROSS_MK_PARAMS if configure script is present
		wmkparams="$@"
	else
		# no build system, try to make the thing compile ok
		wmkparams="${CROSS_MK_PARAMS} $@"
		export_make_wflags
	fi
	if [ "$FORCE_FLAGS" ] ; then
		# defective makefiles: force $*FLAGS and $CROSS_MK_PARAMS
		hl_echo "${WMAKE} LDFLAGS="$WMK_LDFLAGS" CFLAGS="$WMK_CFLAGS" CXXFLAGS="$WMK_CXXFLAGS" ${CROSS_MK_PARAMS} "$@""
		${WMAKE} LDFLAGS="$WMK_LDFLAGS" CFLAGS="$WMK_CFLAGS" \
				CXXFLAGS="$WMK_CXXFLAGS" ${CROSS_MK_PARAMS} "$@"
	elif [ -n "$MAKE_NO_STDERR" ] ; then
		# some apps might want to silence stderr if it gets incredibly long
		hl_echo "${WMAKE} ${wmkparams}"
		${WMAKE} ${wmkparams} 2>/dev/null
	else
		hl_echo "${WMAKE} ${wmkparams}"
		${WMAKE} ${wmkparams}
	fi
	if [ $? -ne 0 ] ; then
		env | grep -E '_PATH|_CONFIG'
		echo
		exit_error
	fi
	unset CFLAGS CXXFLAGS LDFLAGS WMAKE
	return 0
}


function _bmake()
{
    if [ -z "$MAKESYSPATH" ] && [ -d "/usr/share/mk" ] ; then
        # bmake needs $MAKESYSPATH if using something like '.include <bsd.prog.mk>'
        export MAKESYSPATH=/usr/share/mk
    fi
    # for some reason LDFLAGS may be ignored..
    WMAKE="bmake LDSTATIC=$GCC_STATIC" \
        _make "$@"
}


function _mkcmake () # mk-configure
{
	## mk-configure require special params/variables
	## beware of variable collision
	# PREFIX=/usr
	WMK_OPTS="$opts $W_OPTS
MKCOMPILERSETTINGS=yes
SYSCONFDIR=/etc
MKINFO=no MKMAN=no MKHTML=no
MKSHLIB=no
MKSTATICLIB=yes
INSTALL=install"
	if [ -n "${W_SYSROOT}" ] ; then
		WMK_OPTS="${WMK_OPTS}
SYSROOT=${TOOLCHAIN_ROOT}
TOOLCHAIN_DIR=${XPATH}/bin
TOOLCHAIN_PREFIX=${TARGET_TRIPLET}-"
	fi
	export_make_wflags
	hl_echo mkcmake ${WMK_OPTS} "$@"
	mkcmake ${WMK_OPTS} "$@"
	if [ $? -ne 0 ] ; then
		exit_error
	fi
	# don't unset variables
}


function _meson_build ()
{
	# assume 1.0 compatibility
	#--
	if [ "$MAKE_SCRIPT" = "yes" ] ; then
		#wcross_make
		if [ -z "$W_MESON" ] ; then
			# muon is the default meson app, because it just works everywhere (python is not needed)
			W_MESON='muon' 
		fi
		case ${W_MESON} in
			*meson*) MESON_IS_MUON=   ;;
			*muon*)  MESON_IS_MUON=1  ;;
			*) exit_error "$W_MESON must be *meson* or *muon*" ;;
		esac
	fi
	#--
	case $W_OPTS in help|configure)
		${W_MESON} $W_OPTS
		exit 0 ;;
	esac
	#-
	MESON_OPTS="$opts ${W_OPTS}"
	PCS='false'
	if [ "$STATIC_LINK" = "yes" ] ; then
		if [ ! "${MESON_IS_MUON}" ] ; then
			# muon doesn't support -Dprefer_static
			#MESON_OPTS="$MESON_OPTS -Dprefer_static=true"
			echo
		fi
		PCS='true'
	fi
	#-
	# -- the flags only affect muon and meson system compiler (1)
	export_make_wflags
	# --
	if [ -n "$W_SYSROOT" ] ; then
		if [ "${MESON_IS_MUON}" ] ; then
			# this actually makes meson work without the --cross-file 
			# but only use it with muon for now... (1)
			cmd_echo export ${CROSS_MK_PARAMS}
			# https://mesonbuild.com/Reference-tables.html
			cmd_echo export CC_LD=${LD} CXX_LD=${LD}
		else
			MESON_OPTS="--cross-file toolchain.txt $MESON_OPTS"
		fi
		cat > toolchain.txt <<EOF
[binaries]
c = '${CC}'
cpp = '${CXX}'
ar = '${AR}'
strip = '${STRIP}'
as = '${AS}'
ld = '${LD}'
ranlib = '${RANLIB}'
nm = '${NM}'
objcopy = '${OBJCOPY}'
objdump = '${OBJDUMP}'
readelf = '${READELF}'
size = '${SIZE}'
strings = '${STRINGS}'
fortran = '${GFORTRAN}'
pkgconfig = 'pkg-config'
#cmake = '.../bin/cmake'
#exe_wrapper = 'wine64'

#[built-in options]
#c_args = ['${GCC_SYSROOT}', '${GCC_INCLUDE}']
#c_link_args = ['${GCC_STATIC}', '${GCC_SYSROOT}', '${GCC_LIB}']
#cpp_args = ['${GCC_SYSROOT}', '${GCC_INCLUDE}']
#cpp_link_args = ['${GCC_STATIC}', '${GCC_SYSROOT}', '${GCC_LIB}']
#
#fortran_args = ['-Os', '-g0']
#fortran_link_args = []
#wrap_mode = 'nodownload'
#cmake_prefix_path = '.../sysroot/usr/lib/cmake'

[properties]
## sysroot: the flags have already set the sysroot, this adds a full path the flags.. again
#sys_root = '${W_SYSROOT}'
pkg_config_libdir = '${TOOLCHAIN_ROOT}/${WLIBDIR}'
pkg_config_static = '${PCS}'
#needs_exe_wrapper = true
#  enable meson build to pass a toolchain file to cmake
#cmake_toolchain_file = '.../toolchainfile.cmake'
#cmake_defaults = false
EOF
    fi
    hl_echo "${W_MESON} setup "$@" ${MESON_OPTS} builddir"
    ${W_MESON} setup "$@" ${MESON_OPTS} builddir    # . builddir
    if [ $? -ne 0 ] ; then
        exit_error
    fi
    #cmd_echo ${W_MESON} compile -C builddir
    #cmd_echo ninja -v -C builddir
    cmd_echo samu -v -C builddir
    unset W_OPTS
}


function _strip() # bin1 bin2 bin3 ...
{
    if [ "$ALLOW_STRIP_BIN" != "yes" ] ; then
        return
    fi
    for onebinary in "$@"
    do
        local file="$onebinary"
        if [ -f "$onebinary" ] ; then
            file="$onebinary"
        elif [ -f "${onebinary}.exe" ] ; then
            file="${onebinary}.exe"
        fi
        cmd_echo2 ${STRIP} "$file"
    done
}


function check_static_exe() # app
{
    local xappx=$1
	case ${TARGET_TRIPLET} in *mingw*)
		[ -f "${xappx}.exe" ] && return 0
		abort_if_file_not_found ${xappx}
		return 0 ;;
	esac
	abort_if_file_not_found ${xappx}
	if [ "$STATIC_LINK" != "yes" ] ; then
		return 0 # not required to be static
	fi
	# `file` is not reliable to detect if a binary is completely static
	if ( ${READELF} --program-headers ${xappx} | grep -E 'INTERP|program interpreter' ) ; then
		[ -n "${INSTALL_DIR}" ] && rm -rf ${INSTALL_DIR}
		exit_error "${xappx} is not static..!"
	fi
}


function install_exe()
{
    zzexe=${1}
    case ${TARGET_TRIPLET} in *mingw*)
        [ -f ${1}.exe ] && zzexe=${1}.exe ;;
    esac
    check_static_exe ${zzexe}
    #_strip ${zzexe}
    if [ ! -d "$2" ] ; then
        mkdir -p "$2"
    fi
    install -v -m 755 ${zzexe} "$2"
}


function install_to_pkgdir()
{
    if [ -d "${pkgdir}" ] ; then
        rm -rf ${pkgdir}
    fi
    mkdir -p ${pkgdir}
    cmd_echo _make DESTDIR=${pkgdir} install
}


function check_installed_file() # [file] (otherwise use ${PKGDIR_FILE})
{
	if [ -n "$FORCE_BUILD" ] ; then #-f
		return 0
	fi
	local xxfile
	local xxtype=INSTALLED
	xxfile2=
	xxfile3=
	#--
	if [ "$PKGDIR_FILE" ] ; then
		# no need check /var/wcross ... $pkgdir is different
		xxfile=${INSTALL_DIR}/${PKGDIR_FILE}
		xxfile2=${INSTALL_DIR}/usr/${PKGDIR_FILE}
		xxfile3=${INSTALL_DIR}/${PKGDIR_FILE}.exe
	elif [ "$TOOLCHAIN_FILE" ] ; then
		if [ "$BUILD_TYPE" != "chroot" ] ; then
			if [ ! -f ${TOOLCHAIN_ROOT}/var/wcross/${pkgname}-${pkgver}-r${pkgrel} ] ; then
				# file is missing, must compile, it's a different version/revision
				return 0
			fi
		fi
		xxfile=${TOOLCHAIN_ROOT}/${TOOLCHAIN_FILE}
		xxfile2=${TOOLCHAIN_ROOT}/usr/${TOOLCHAIN_FILE}
		xxfile3=${TOOLCHAIN_ROOT}/${PKGDIR_FILE}.exe
		xxtype=TOOLCHAIN
	elif [ "$1" ] ; then
		xxfile=${INSTALL_DIR}/${1}
	else
		exit_error "check_installed_file: no file to check, empty PKGDIR_FILE or TOOLCHAIN_FILE or \$1"
	fi
	#--
	# WTH: sometimes -e "$xxfile" doesn't work, but it works without quotes. WTH
	if [ -e "$xxfile" ] || [ -e $xxfile ] ; then
		exit_ok "${xxtype}: $xxfile"
	fi
	if [ -e "$xxfile2" ] || [ -e $xxfile2 ] ; then
		exit_ok "${xxtype}: $xxfile2"
	fi
	case ${TARGET_TRIPLET} in *mingw*)
		if [ -e "$xxfile3" ] || [ -e $xxfile3 ] ; then
			exit_ok "${xxtype}: $xxfile3"
		fi
	esac
}


function standard_cleanup()
{
	if [ -z "${SRC_DIR}" ] ; then
		exit_error "(standard_cleanup) \${SRC_DIR} is empty"
	fi
	if [ -d ${BUILDTMP}/${SRC_DIR} ] ; then
		echo "rm -rf ${BUILDTMP}/${SRC_DIR}"
		rm -rf ${BUILDTMP}/${SRC_DIR}
	fi
}


function strip_all_binaries() # [dir] otherwise current dir
{
	# applies to current dir, currently only ELF binaries
	currentdirX=${PWD}
	if [ "$1" ] ; then
		currentdirX=$1
	fi
	for exe in `find "$currentdirX" -type f -executable`
	do
		info=$(file $exe)
		case $info in
			*ELF*) _strip $exe
		esac
	done

}


function fix_pkgconfig_for_toolchain()  # $1=<dir_or_files>
{
	unset xpcfilesx
	if [ -d "$1" ] ; then
		currentdirX="$1"
	elif [ -f "$1" ] ; then
		xpcfilesx="$@"
	else
		exit_error "$1 is not a file or a directory"
	fi
	if [ -z "$xpcfilesx" ] ; then
		xpcfilesx=$(find "$1" -type f -name '*.pc' -or -name '*.la' -or -name '*-config')
	fi
	#--"/usr"
	if [ -n "${xpcfilesx}" ] && [ -n "${PC_FILES_BACKUP_DIR}" ] ; then
		cp -a ${xpcfilesx} ${PC_FILES_BACKUP_DIR}/
	fi
	for pc in ${xpcfilesx}
	do
		if [ -L "$pc" ] ; then
			continue # ignore symlinks
		fi
		echo "fix_pkgconfig_for_toolchain: $pc"
		sed -i \
			-e "s%/usr/local%${TOOLCHAIN_ROOT}%g" \
			-e "s%/usr/%${TOOLCHAIN_ROOT}/%" \
			-e "s%=/usr%=${TOOLCHAIN_ROOT}%" \
			-e "s% /usr% ${TOOLCHAIN_ROOT}%g" \
			-e "s%\"/usr\"%\"${TOOLCHAIN_ROOT}\"%" \
			-e "s%'/usr'%'${TOOLCHAIN_ROOT}'%" \
			${pc}
		case $pc in *-config)
			#force static libs
			sed -i 's%${libs}%${all_libs}%' ${pc}
			;;
		esac
	done
}


function _dist_binary() # exe1 exe2
{
	# copy files to ${MWD}/xxx-${pkgver}-${WTARGET}[.exe]
	if [ -z "$DIST_BINARY" ] ; then # set by *.sbuild
		return
	fi
	local destdir=${MWD}/out_w/dist_binary
	local basename="" zzfile=""
	mkdir -p ${destdir}
	XARCH=${WTARGET}
    case ${WTARGET} in
        i686*) [ "$STATIC_LINK" = "yes" ] && XARCH="x86" ;;
        x86_64*) XARCH="x86_64" ;;
    esac
	for onebinary in ${DIST_BINARY}
	do
		basename=$(basename $onebinary .exe)
		zzfile=$(find ${INSTALL_DIR} -type f -name "${onebinary}" -or -name "${onebinary}.exe" | grep bin/)
		if [ ! -f "$zzfile" ] ; then
			exit_error "_dist_binary() : cannot find $onebinary"
		fi
		case ${TARGET_TRIPLET} in
			*mingw*) name=${basename}-${pkgver}-${XARCH}.exe  ;;
			*freebsd*|*openbsd*|*netbsd*) name=${basename}-${pkgver}-${XARCH}  ;;
			*) name=${basename}-${pkgver}-linux-${XARCH} ;;
		esac
		cp -av --remove-destination ${zzfile} ${destdir}/${name}
	done
	if [ $(id -u) -eq 0 ] ; then
		chown nobody ${destdir}/${name}
	fi
	case ${TARGET_TRIPLET} in *mingw*|*linux*)
		if [ "$CPU_ARCH" = "i686" ] || [ "$CPU_ARCH" = "x86_64" ] ; then
			cmd_echo2 upx ${destdir}/${name}
			return 0
		fi
		;;
	esac
	case ${TARGET_TRIPLET} in
		*mingw*) ( cd ${destdir} ; zip ${name}.zip ${name} ) ;;
		*) cmd_echo2 lzip -f -k ${destdir}/${name} ;;
	esac
}


function update_config_sub () # update_config_guess
{
    config_sub=${WDOWNLOAD_DIR}/config.sub
    config_guess=${WDOWNLOAD_DIR}/config.guess
    if ! [ -f "$config_sub" ] ; then
        download_file https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.sub
    fi
    if ! [ -f "$config_guess" ] ; then
        download_file https://raw.githubusercontent.com/gcc-mirror/gcc/master/config.guess
    fi
    find . -maxdepth 2 -name config.sub | \
        while read f ; do cp -fv ${config_sub} ${f} ; done
    find . -maxdepth 2 -name config.guess | \
        while read f ; do cp -fv ${config_guess} ${f} ; done
}

function patch_pkg()   #[$1:file]
{
	# patch package
	file2patch="$1"
	pkg2patch="$pkgname"
	wpatch_dir=''
	if [ -n "$pkgver" ] ; then
		# support applying patches to specific versions
		if [ -d ${MWD}/pkg_patches/${pkg2patch}/${pkgver} ] ; then
			wpatch_dir=${MWD}/pkg_patches/${pkg2patch}/${pkgver}
		fi
	fi
	if [ -z "$wpatch_dir" ] ; then
		wpatch_dir=${MWD}/pkg_patches/${pkg2patch}
	fi
	if [ ! -d ${wpatch_dir} ] ; then
		return 0
	fi
	#-
	if [ -n "$file2patch" ] ; then
		# want to patch a single file, it shouldn't have a file extension
		if [ -n "$patch_args" ] ; then
			cmd_echo patch ${patch_args} -i ${wpatch_dir}/${file2patch}
		else
			cmd_echo patch -p1 -i ${wpatch_dir}/${file2patch}
		fi
		return 0
	fi
	# generic patches that should apply to all targets
	apply_patches_from_dir ${wpatch_dir}
	# XXX_TOOLCHAIN, usually set in targets/z_...
	if [ "$MUSL_TOOLCHAIN" ] && [ -d ${wpatch_dir}/musl ] ; then
		apply_patches_from_dir ${wpatch_dir}/musl
	elif [ "$MINGW_TOOLCHAIN" ] && [ -d ${wpatch_dir}/mingw ] ; then
		apply_patches_from_dir ${wpatch_dir}/mingw
	elif [ "$GLIBC_TOOLCHAIN" ] && [ -d ${wpatch_dir}/glibc ] ; then
		apply_patches_from_dir ${wpatch_dir}/glibc
	elif [ "$FREEBSD_TOOLCHAIN" ] && [ -d ${wpatch_dir}/freebsd ] ; then
		apply_patches_from_dir ${wpatch_dir}/freebsd
	#elif   TODO: more toolchains
	fi
	# special
	if [ "$STATIC_LINK" = "yes" ] && [ -f ${wpatch_dir}/static_link ] ; then
		cmd_echo patch -p1 -i ${wpatch_dir}/static_link
	fi
	if [ -d ${wpatch_dir}/copy ] ; then
		cp -a --remove-destination ${wpatch_dir}/copy/* .
	fi
}


function install_system_app_if_missing()
{
    local app="$1"
    shift
    local params="$@"
    case ${TARGET_TRIPLET} in # only linux cross compiles
        *linux*) ok=1;;
        *) return 0 ;;
    esac
    if command -v ${app} >/dev/null ; then
        # app already there
        return 0;
    fi
    if [ -z "$params" ] ; then
        # no params, use $CPU_ARCH
        if [ "$OS_ARCH" = "$CPU_ARCH" ] ; then
            install -v -m 755 ./${app} /usr/local/bin
        fi
    else
        # params, test and copy if return value = 0
        if ./${app} ${params} 1>/dev/null 2>/dev/null ; then
            install -v -m 755 ./${app} /usr/local/bin
        fi
    fi
}


apkbuild_check_sum()
{
	# checksums that include files - APKBUILD compat
	# this is different from arch, void, etc
	# the *sums vars have been set by manually or by a sourced script
	if [ "$sha512sums" ] ; then
		wsums="$sha512sums"
		wchksum='sha512sum -c'
	elif [ "$sha256sums" ] ; then
		wsums="$sha256sums"
		wchksum='sha256sum -c'
	elif [ "$md5sums" ] ; then
		wsums="$md5sums"
		wchksum='md5sum -c'
	else
		return 0  #no checksums, return silently
	fi
	xcurdirx=$(pwd)
	cd ${WDOWNLOAD_DIR}
	#			 remove empty lines
	echo "$wsums" | sed -e '/^$/d' | ${wchksum}
	if [ $? -ne 0 ] ; then
		exit_error
	fi
	cd ${xcurdirx}
	#unset sha512sums sha256sums md5sums
}


function enforce_cross_compiler()   # [$1:bindir]
{
	#sometimes there is no way to cross-compile
	if [ -z "$XCOMPILER" ] ; then
		return
	fi
	if [ "$1" ] ; then
		wbindir=${1}
	else
		wbindir=${XPATH}/bin
	fi
	for oneapp in $(ls ${wbindir}/${TARGET_TRIPLET}-*)
	do
		ln -sv ${oneapp} ${wbindir}/${oneapp##*-}
	done
}

function unenforce_cross_compiler()   # [$1:bindir]
{
	if [ -z "$XCOMPILER" ] ; then
		return
	fi
	if [ "$1" ] ; then
		wbindir=${1}
	else
		wbindir=${XPATH}/bin
	fi
	if [ ! -e ${wbindir}/${TARGET_TRIPLET}-gcc ] && [ ! -e ${wbindir}/${TARGET_TRIPLET}-ar ] ; then
		# nothing to unenforce
		return 0
	fi
	if [ ! -L ${wbindir}/as ] ; then
		# as is not symlink, nothing to do
		return 0
	fi
	for oneapp in $(ls ${wbindir}/${TARGET_TRIPLET}-*)
	do
		rm -fv ${wbindir}/${oneapp##*-}
	done
}


standard_autotools()
{
	. ${MWD}/pkg/0standard_autotools || exit_error
}

standard_cmake()
{
	. ${MWD}/pkg/0standard_cmake || exit_error
}

standard_meson()
{
	. ${MWD}/pkg/0standard_meson || exit_error
}


remove_wcflags() {  #<cflag1> [cflag2]...
	for i in $@
	do
		WMK_CFLAGS=${WMK_CFLAGS//${i}/}
	done
}

replace_wcflag() {  #$1:<cflag> $2:<new_cflag>
	WMK_CFLAGS=${WMK_CFLAGS//${1}/${2}}
}

remove_wldflags() {  #<ldflag1> [ldflag2]...
	for i in $@
	do
		WMK_LDFLAGS=${WMK_LDFLAGS//${i}/}
	done
}

replace_wldflag() {  #$1:<ldflag> $2:<new_ldflag>
	WMK_LDFLAGS=${WMK_LDFLAGS//${1}/${2}}
}


woptimize_flag() {
	woptim='-O2'
	if [ -n "$1" ] ; then
		woptim="$1"
	fi
	case ${WMK_CFLAGS} in
		*-ggdb3*) return ;; # don't optimize
		*" -g") return ;; # don't optimize
		*" -g "*) return ;; # don't optimize
	esac
	if [ -z "$WMK_CFLAGS" ] ; then
		WMK_CFLAGS="$woptim"
	else
		WMK_CFLAGS="$WMK_CFLAGS $woptim"
	fi
}

### END ###
