#!/bin/sh
# Public domain

. ../functions.sh || exit 1

mkdir -p tmp ; cd tmp

if [ -z "$1" ] ; then
	echo "
syntax:
  $0 <linux_version>

Produce a cutdown version of kernel tarball, so that at least this works:
   make ARCH=<arch> INSTALL_HDR_PATH=<installdir> headers_install

The produced tarball has a different name: linux-headers-<linux_version>

Kernel versions that are expanded to x.x.x:
    5.4  5.10  5.15  6.1
"
	exit 1
fi

WGET='wget --no-check-certificate'

LINUX_VER=${1}
case $LINUX_VER in
	5.4)  LINUX_VER=5.4.243  ;;
	5.10) LINUX_VER=5.10.180 ;;
	5.15) LINUX_VER=5.15.112 ;;
	6.1)  LINUX_VER=6.1.29   ;;
esac
echo $LINUX_VER
echo

set_linux_url ${LINUX_VER}

if [ ! -f linux-${LINUX_VER}.tar.xz ] ; then
	cmd_echo ${WGET} "$LINUX_URL"
fi

#=====================================================================

delete_kfiles()
{
	files2delete='
block
certs
CREDITS
crypto
Documentation
drivers
fs
init
ipc
kernel
lib
LICENSES
MAINTAINERS
mm
net
samples
scripts/atomic
scripts/coccinelle
scripts/dtc
scripts/gcc-plugins
scripts/gdb
scripts/genksyms
scripts/ksymoops
scripts/mod
scripts/package
scripts/selinux
scripts/tracing
security
sound
virt
'
	if [ ! -d linux-${LINUX_VER} ] ; then
		cmd_echo tar -xf linux-${LINUX_VER}.tar.xz
	fi

	for f in ${files2delete}
	do
		if [ -e linux-${LINUX_VER}/${f} ] ; then
			#echo "rm -rf linux-${LINUX_VER}/${f}"
			rm -rf linux-${LINUX_VER}/${f}
		fi
	done

	rm -f linux-${LINUX_VER}/.[a-z]*
	rm -f linux-${LINUX_VER}/.[A-Z]*
	rm -f linux-${LINUX_VER}/.[0-9]*

	sed -i 's%uapi-asm-generic archheaders archscripts%uapi-asm-generic archheaders%' \
		linux-${LINUX_VER}/Makefile

	find linux-${LINUX_VER}/arch -name '*.c' -delete
	find linux-${LINUX_VER}/arch -name '*.S' -delete
	find linux-${LINUX_VER}/tools -name '*.c' -delete

	# tools/: only tools/include is required
	find linux-${LINUX_VER}/tools -mindepth 1 -maxdepth 1 -type d | grep -v include | \
		while read dir; do
			cmd_echo rm -rf "$dir"
		done

	find linux-${LINUX_VER}/arch -type d -name 'dts' | \
		while read dir; do
			cmd_echo rm -rf "$dir"
		done
}


#=====================================================================

add_test_install_script()
{
	echo '#!/bin/sh

if [ ! -d arch ] ; then
	echo "arch/ dir is missing"
	exit 1
fi

installdir=$(pwd)/0test_headers_install
ret=0

rm -f zerr.log
rm -rf ${installdir}
mkdir -p ${installdir}

echo
echo "Testing installation of kernel headers"
for arch in $(ls arch)
do
	if [ ! -d arch/${arch} ] ; then
		continue
	fi
	if [ ! -f arch/${arch}/include/uapi/asm/Kbuild ] ; then
		continue # headers not exportable
	fi
	if [ "$arch" = "um" ] ; then
		# https://www.spinics.net/lists/stable/msg591676.html
		# arch/um/include/uapi/asm/Kbuild is empty, make fails
		continue
	fi
	printf " * ${arch}... "
	echo " * ${arch}... " >>zerr.log
	mkdir -p ${installdir}/${arch}
	make ARCH=${arch} INSTALL_HDR_PATH=${installdir}/${arch} headers_install >/dev/null 2>>zerr.log
	if [ $? -eq 0 ] ; then
		echo "OK"
	else
		ret=1
		echo "FAIL"
	fi
done
echo

if [ ${ret} -eq 0 ] ; then
	echo "ALL OK"
else
	echo "WARNING: there were failure(s)"
fi

exit ${ret}
' > linux-${LINUX_VER}/test-headers-install.sh
	chmod +x linux-${LINUX_VER}/test-headers-install.sh
}


#=====================================================================

produce_tarball()
{
	cmd_echo2 mv linux-${LINUX_VER} linux-headers-${LINUX_VER}
	cmd_echo2 tar -Jcf linux-headers-${LINUX_VER}.tar.xz linux-headers-${LINUX_VER}
}


#=====================================================================
# main

delete_kfiles
add_test_install_script
produce_tarball

echo "Done"
