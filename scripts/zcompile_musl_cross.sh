#!/bin/bash
# Public Domain
#
# compile cross-compiler with musl-cross-make
#

SCRIPT_DIR=$(pwd)

if [ $LOG ] ; then
	exec &>${0##*/}.log
fi

#
# 2018-03-06
#
# The following is a non-exhaustive list of $(TARGET) tuples that are believed to work:
#	aarch64[_be]-linux-musl
#	arm[eb]-linux-musleabi[hf]
#	i*86-linux-musl
#	microblaze[el]-linux-musl
#	mips-linux-musl
#	mips[el]-linux-musl[sf]
#	mips64[el]-linux-musl[n32][sf]
#	powerpc-linux-musl[sf]
#	powerpc64[le]-linux-musl
#	s390x-linux-musl
#	sh*[eb]-linux-musl[fdpic][sf]
#	x86_64-linux-musl[x32]
#

TARGETS_32BIT='
armv6-linux-musleabihf
i686-linux-musl
'
TARGETS_64BIT='
x86_64-linux-musl
aarch64-linux-musl
'
ALL_SUPPORTED_TARGETS="
$TARGETS_32BIT
$TARGETS_64BIT
"

case $(uname -m) in
	*64*) ALL_TARGETS="$ALL_SUPPORTED_TARGETS" ;;
	*)    ALL_TARGETS="$TARGETS_32BIT" ; TARGETS_64BIT='' ;;
esac

for app in gcc make zip ; do
	if ! $app --version &>/dev/null ; then
		echo -e "\033[1;31m""$app is not installed""\033[0m"
		exit 1
	fi
done

#---

OPT=$1

if [ "$OPT" = "auto" -o "$OPT" = "all" ] ; then
	TARGETS=${ALL_TARGETS}
elif [ "$OPT" = "32" ] ; then
	TARGETS=${TARGETS_32BIT}
elif [ "$OPT" = "64" ] ; then
	TARGETS=${TARGETS_64BIT}
elif [ "$OPT" ] ; then
	for i in $ALL_TARGETS ; do
		case $i in
			"$OPT"*) TARGETS=$i ; break;;
		esac
	done
fi

if [ -z "$TARGETS" ] ; then
	echo "Need a target:"
	echo "$ALL_TARGETS"
	exit 1
fi

echo "TARGETS: $TARGETS"

#-------------------

#git clone git://github.com/richfelker/musl-cross-make.git musl-cross-make

if [ ! -f musl-cross-make.zip ] ; then
	wget -c -O musl-cross-make.zip https://github.com/richfelker/musl-cross-make/archive/master.zip
	[ $? -ne 0 ] && exit 1
fi

if [ ! -d musl-cross-make-master/litecross ] ; then
	zip -T musl-cross-make.zip || exit 1
	unzip musl-cross-make.zip || exit 1
fi

if ! [ -d musl-cross-make-master/litecross ] ; then
	exit 1
fi

if [ ! -f musl-cross-make-master/config.mak ] ; then
	cat > musl-cross-make-master/config.mak <<EOF
# There is no default TARGET; you must select one here or on the make
# command line. Some examples:

# By default, cross compilers are installed to ./output under the top-level
# musl-cross-make directory and can later be moved wherever you want them.
# To install directly to a specific location, set it here. Multiple targets
# can safely be installed in the same location. Some examples:

# OUTPUT = /opt/cross
# OUTPUT = /usr/local

# By default, latest supported release versions of musl and the toolchain
# components are used. You can override those here, but the version selected
# must be supported (under hashes/ and patches/) to work. For musl, you
# can use "git-refname" (e.g. git-master) instead of a release. Setting a
# blank version for gmp, mpc, mpfr and isl will suppress download and
# in-tree build of these libraries and instead depend on pre-installed
# libraries when available (isl is optional and not set by default).
# Setting a blank version for linux will suppress installation of kernel
# headers, which are not needed unless compiling programs that use them.

# BINUTILS_VER = 2.25.1
# GCC_VER = 5.2.0
# MUSL_VER = git-master
# GMP_VER =
# MPC_VER =
# MPFR_VER =
# ISL_VER =
# LINUX_VER =

# By default source archives are downloaded with wget. curl is also an option.

 DL_CMD = wget --no-check-certificate -c -O

# Recommended options for smaller build for deploying binaries:

 COMMON_CONFIG += CFLAGS="-static --static -g0 -Os" CXXFLAGS="-static --static -g0 -Os" LDFLAGS="-s"

# Recommended options for faster/simpler build:

 COMMON_CONFIG += --disable-nls --disable-doc --disable-man
 GCC_CONFIG += --enable-languages=c,c++
 #GCC_CONFIG += --disable-libquadmath --disable-decimal-float
 GCC_CONFIG += --disable-multilib

EOF
fi

#-----------------

for TG in $TARGETS
do

	cd "$SCRIPT_DIR"

	echo -----------------------------------------
	echo $TG
	echo -----------------------------------------

	DATE=$(date "+%Y%m%d")
	TARCH=$(echo $TG | cut -f1 -d '-')
	CC_DIR=${TG}-cross-${DATE}
	CC_PKG=${CC_DIR}.tar.xz

	#echo $CC_DIR
	#echo $CC_PKG

	cd musl-cross-make-master

	INSTALL_DIR=$(pwd)/${CC_DIR}
	rm -rf $INSTALL_DIR
	mkdir -p $INSTALL_DIR

	make clean

	cat > make-cc.sh <<EOF
	export MAKEFLAGS="-j \$(grep -c ^processor /proc/cpuinfo)"
	make OUTPUT="$INSTALL_DIR" TARGET="$TG" install
	if [ \$? -eq 0 ] ; then
		(
			date "+%Y-%m-%d"
			echo
			ls -d *-* | grep -vE 'cross-|make-cc|\-linux-musl'
		) > ${INSTALL_DIR}/specs
		echo "Creating $CC_PKG"
		tar -Jcf "$CC_PKG" "$CC_DIR"
	else
		echo 'ERROR...'
		exit 1
	fi

	mkdir -p ../0sources
	mv -fv "$CC_PKG" ../0sources

	echo "Done !"
	exit 0
EOF

	sh make-cc.sh
	if [ $? -ne 0 ] ; then
		echo "Failed to build cross-compiler, exiting"
		exit 1
	fi

done

### END ###
