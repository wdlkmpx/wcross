#!/bin/bash
#
# Public Domain
#
# somewhat generic functions that can be used by build systems and other scripts
# only Linux is supported
#
# exit_error must be defined by the script that sources this
# example:
#   exit_error() { echo -e "$@" ; exit 1 ; }
# 
# variables used by some functions:
# - WDOWNLOAD_DIR (where files download/check are located)
# - WSUMFILES_DIR [optional] (where to store checksums)

#=====================================================================

cmd_echo ()
{ # this assumes that var=value contains a value without spaces, otherwise this breaks
    echo "# $@"
    "$@" || exit_error
}

cmd_echo2 ()
{
    echo "# $@"
    "$@"
}

exit_ok()
{
    [ "$1" ] && echo "$@"
    exit 0
}


hl_echo()
{
	echo
	echo '------------------------------'
	echo "$@"
	echo '------------------------------'
	echo
}


abort_if_app_is_missing()  #app1 app2 app3
{
	for oneapp in "$@" ; do
		if ! command -v "$oneapp" >/dev/null ; then
			exit_error "$oneapp is missing"
		fi
	done
}

#=====================================================================

install_linux_headers()     # $1:<TARGET> $2:<INSTALL_DIR>
{
    # current dir = linux src dir
    case $1 in # TARGET can be a triplet or a specific arch
        *-*-*) LARCH=$(echo ${1} | cut -f1 -d '-') ;;
        *)     LARCH=${1} ;;
    esac
    LINUX_INSTALL_DIR="$2"
    LARCH_MANGLED=${LARCH}
    case ${LARCH} in
        i?86|x86_64) LARCH_MANGLED='x86'      ;;
        aarch64)     LARCH_MANGLED='arm64'    ;;
        arm*)        LARCH_MANGLED='arm'      ;;
        powerpc*)    LARCH_MANGLED='powerpc'  ;;
        ppc*)        LARCH_MANGLED='powerpc'  ;;
        sparc*)      LARCH_MANGLED='sparc'    ;;
        or1k)        LARCH_MANGLED='openrisc' ;;
        s390*)       LARCH_MANGLED='s390'     ;;
        microblaze*) LARCH_MANGLED='microblaze' ;;
        risc*)       LARCH_MANGLED='riscv'    ;;
        mips*)       LARCH_MANGLED='mips'     ;;
        sparc*)      LARCH_MANGLED='sparc'    ;;
    esac
    if   [ -d arch/${LARCH} ] ; then
        LINUX_ARCH=${LARCH}
    elif [ -d arch/${LARCH_MANGLED} ] ; then
        LINUX_ARCH=${LARCH_MANGLED}
    elif [ -d ${LARCH} ] ; then
        LINUX_ARCH=${LARCH}  # sabotage linux headers
    elif [ -d ${LARCH_MANGLED} ] ; then
        LINUX_ARCH=${LARCH_MANGLED}  # sabotage linux headers
    else
        echo "ERROR: (FIXME) cannot identify a suitable linux arch to install headers"
        echo "       or maybe the selected linux version doesn't support $1"
        exit 1
    fi
    #echo "LARCH = ${LARCH}"
    #echo "LARCH_MANGLED = ${LARCH_MANGLED}"
    #echo "LINUX_ARCH = ${LINUX_ARCH}"
    if [ -d Documentation ] ; then
        # Delete the current configuration, and all generated files
        # only do this with the full linux sources, it fails with the cutdown sources
        cmd_echo make ARCH=${LINUX_ARCH} mrproper
    fi
    # Install headers
    mkdir -p ${LINUX_INSTALL_DIR}
    cmd_echo make \
        ARCH=${LINUX_ARCH} \
        INSTALL_HDR_PATH=${LINUX_INSTALL_DIR} \
        headers_install
}


set_linux_url()  # $1:<linux_version>
{
    # set LINUX_URL with a valid URL or exit 1
    if [ -z "$LINUX_SITE" ] ; then
        LINUX_SITE=https://cdn.kernel.org/pub/linux/kernel
    fi
    if [ -z "$LINUX_HEADERS_SITE" ] ; then
        LINUX_HEADERS_SITE=https://sourceforge.net/projects/wdl/files/wcross/linux-headers
    fi
    LINUX_URL=''
    case ${1} in
        3.*) LINUX_URL=${LINUX_SITE}/v3.x/linux-${1}.tar.xz ;;
        4.*) LINUX_URL=${LINUX_SITE}/v4.x/linux-${1}.tar.xz ;;
        5.*) LINUX_URL=${LINUX_SITE}/v5.x/linux-${1}.tar.xz ;;
        6.*) LINUX_URL=${LINUX_SITE}/v6.x/linux-${1}.tar.xz ;;
        headers*) LINUX_URL=${LINUX_HEADERS_SITE}/linux-${1}.tar.xz ;;
        *) echo "Unsupported kernel version: ${1}" ; exit 1 ;;
    esac
    LINUX_TARBALL=${LINUX_URL##*/}
}


dedup_toolchain_apps()  #$1:<target_triplet>
{
	# GCC - DEDUPLICATE BINUTILS
	# - working in current directory (use a subshell and cd to the desired dir)
	#bin/i686-linux-musl-ar -> ../../bin/${TRIPLET}-ar
	if [ -n "$1" ] && [ -L ./${1}/bin/ar ] ; then
		if [ -e ./${1}/bin/ar ] ; then
			return 0 # already processed
		fi
		#oops, broken symlink, it was processed in a bad way
	elif [ ! -e ./${1}/bin/ar ] ; then
		return 0 # probably an llvm toolchain or something is wrong
	fi
	#--
	app_triplet=1
	if [ ! -e ./bin/${1}-gcc ] && [ ! -e ./bin/${1}-ar ] ; then
		if [ -e ./bin/gcc ] || [ -e ./bin/ar ] ; then
			# app don't have triplet- prefixed
			app_triplet=
		else
			return 0 # invalid dir, should probably print a msg?
		fi
	fi
	#--
	if [ "$app_triplet" ] ; then
		# problem with aliased `ls`, use `command ls` to avoid that (or maybe `busybox ls`)
		for app1 in $(command ls ./${1}/bin)
		do
			# ln -snfv ../../bin/i686-linux-musl-ar i686-linux-musl/bin/ar
			ln -snfv ../../bin/${1}-${app1} ./${1}/bin/${app1}
		done
	else
		for app1 in $(command ls ./${1}/bin) ; do
			ln -snfv ../../bin/${app1} ./${1}/bin/${app1}
		done
	fi
	return 0
}


function fn_export_autoconf_vars()   #$1:[TARGET_TRIPLET]
{
	# autootols: speed up some tests
	if [ -n "$ac_cv_header_stdc" ] ; then
		return
	fi
	# GCC (and clang?) + at least C99
	export ac_cv_header_stdc=yes
	export ac_cv_func_malloc_0_nonnull=yes   #fixes [rpl_malloc]  / AC_FUNC_MALLOC  (configure.ac)
	export ac_cv_func_realloc_0_nonnull=yes  #fixes [rpl_realloc] / AC_FUNC_REALLOC (configure.ac)
	export ac_cv_func_calloc_0_nonnull=yes   #fixes [rpl_calloc]  / AC_FUNC_CALLOC  (configure.ac)
	export ac_cv_func_timegm=yes
	export ac_cv_prog_cc_g=yes
	export am_cv_prog_cc_c_o=yes
	export ac_cv_prog_cxx_g=yess
	export ac_cv_c_const=yes
	#export ac_cv_c_compiler_gnu=yes
	export lt_cv_prog_compiler_c_o=yes
	#export lt_cv_prog_gnu_ld=yes
	export ac_cv_lib_z_compressBound=yes
	export ac_cv_lib_bz2_BZ2_bzCompressInit=yes
	export ac_cv_lib_jte_libjte_set_checksum_algorithm=yes
	#export ac_cv_lib_m_cos=yes
	#export ac_cv_lib_rt_clock_gettime=yes
	export ac_cv_lib_acl_adcl_to_text=yes
	export ac_cv_lib_attr_getxattr=yes
	export ac_cv_type_signal=void
	export gl_cv_warn_c__Werror=yes
	#--
	export ac_cv_sizeof_int16_t=2
	export ac_cv_sizeof_uint16_t=2
	export ac_cv_sizeof_u_int16_t=2
	export ac_cv_sizeof_int32_t=4
	export ac_cv_sizeof_uint32_t=4
	export ac_cv_sizeof_u_int32_t=4
	export ac_cv_sizeof_int64_t=8
	export ac_cv_sizeof_uint64_t=8
	export ac_cv_sizeof___int16=2
	export ac_cv_sizeof___int32=4
	export ac_cv_sizeof___int64=8
	export ac_cv_sizeof_short=2
	export ac_cv_sizeof_unsigned_short=2
	export ac_cv_sizeof_int=4
	export ac_cv_sizeof_unsigned_int=4
	#export ac_cv_sizeof_int=4
	#-- header C99+
	export ac_cv_header_assert_h=yes
	export ac_cv_header_ctype_h=yes
	export ac_cv_header_errno_h=yes
	export ac_cv_header_fenv_h=yes
	export ac_cv_header_float_h=yes
	export ac_cv_header_inttypes_h=yes
	export ac_cv_header_stdarg_h=yes
	export ac_cv_header_stdbool_h=yes
	export ac_cv_header_stddef_h=yes
	export ac_cv_header_stdint_h=yes
	export ac_cv_header_stdio_h=yes
	export ac_cv_header_stdlib_h=yes
	export ac_cv_header_string_h=yes
	export ac_cv_header_wchar_h=yes
	export ac_cv_header_wctype_h=yes
	#export ac_cv_header_...=yes
	#--
	export ac_cv_type_size_t=yes
	export ac_cv_type_int8_t=yes
	export ac_cv_type_int16_t=yes
	export ac_cv_type_int32_t=yes
	export ac_cv_type_int64_t=yes
	export ac_cv_type_uint8_t=yes
	export ac_cv_type_uint16_t=yes
	export ac_cv_type_uint32_t=yes
	export ac_cv_type_uint64_t=yes
	#export ac_cv_type_uintptr_t=yes
	export ac_cv_c_int8_t=yes
	export ac_cv_c_uint8_t=yes
	export ac_cv_c_int16_t=yes
	export ac_cv_c_uint16_t=yes
	export ac_cv_c_int32_t=yes
	export ac_cv_c_uint32_t=yes
	export ac_cv_c_int64_t=yes
	export ac_cv_c_uint64_t=yes
	#--
	export gt_cv_locale_fr=none
	export gt_cv_locale_fr_utf8=none
	export gt_cv_locale_ja=none
	export gt_cv_locale_zh_CN=none
	export gt_cv_locale_tr_utf8=none
	#--
	c_funcs='
###ctype.h
isalpha
isascii
isblank
###stdio
remove
rename
tmpfile
tmpnam
vscanf
vfscanf
vsscanf
vsnprintf
snprintf
###stdlib
atof
atoi
atol
atoll
strtod
strtof
strtol
strtold
strtoll
strtoul
strtoull
getenv
system
atexit
qsort
bsearch
realloc
###string.h
memcpy
memcmp
memmove
memset
strchr
strdup
strlen
strnlen
strstr
strrchr
strerror
###time.h
mktime
gmtime
difftime
strftime
localtime
'
	for i in ${c_funcs}
	do
		case $i in '#'*)
			continue ;;
		esac
		export ac_cv_have_decl_${i}=yes
		export ac_cv_func_${i}=yes
	done
	#-----------
	#posix
	case ${1} in *linux*|*bsd*)
		export ac_cv_header_dirent_h=yes
		export ac_cv_header_fnmatch_h=yes
		export ac_cv_header_minix_config_h=no
		export ac_cv_header_limits_h=yes
		export ac_cv_header_setjmp_h=yes
		export ac_cv_header_signal_h=yes
		export ac_cv_header_sys_socket_h=yes
		export ac_cv_header_sys_stat_h=yes
		export ac_cv_header_sys_time_h=yes
		export ac_cv_header_sys_types_h=yes
		export ac_cv_header_time_h=yes
		export ac_cv_header_ulimit_h=yes
		export ac_cv_header_unistd_h=yes
		export ac_cv_header_utime_h=yes
		#--
		export ac_cv_func_fnmatch_works=yes # fixes [rpl_fnmatch] / AC_FUNC_FNMATCH (configure.ac)
		posix_funcs="
fnmatch
utime
open
read
close
getc_unlocked
getchar_unlocked
putc_unlocked
putchar_unlocked
"
		for i in ${posix_funcs} ; do
			export ac_cv_have_decl_${i}=yes
			export ac_cv_func_${i}=yes
		done
		;;
	esac
	#-----------
	#linux
	case ${1} in
	*linux*)
		export ac_cv_header_arpa_inet_h=yes
		export ac_cv_header_cpuid_h=yes
		export ac_cv_header_fcntl_h=yes
		export ac_cv_header_dlfcn_h=yes
		export ac_cv_header_getopt_h=yes
		export ac_cv_header_glob_h=yes
		export ac_cv_header_langinfo_h=yes
		export ac_cv_header_linux_cdrom_h=yes
		export ac_cv_header_linux_fd_h=yes
		export ac_cv_header_linux_hdreg_h=yes
		export ac_cv_header_linux_loop_h=yes
		export ac_cv_header_linux_major_h=yes
		export ac_cv_header_linux_version_h=yes
		export ac_cv_header_memory_h=yes
		export ac_cv_header_mntent_h=yes
		export ac_cv_header_netdb_h=yes
		export ac_cv_header_pthread_h=yes
		export ac_cv_header_strings_h=yes
		export ac_cv_header_sys_ioctl_h=yes
		export ac_cv_header_sys_param_h=yes
		export ac_cv_header_sys_select_h=yes
		export ac_cv_header_termios_h=yes
		export ac_cv_header_wchar_h=yes
		#--
		export ac_cv_type_pid_t=yes
		export ac_cv_type_off_t=yes
		export ac_cv_type_ssize_t=yes
		#--
		linux_funcs="
access
getopt_long
fsync
geteuid
getgid
getmntent
getuid
setmntent
chmod
chown
lstat
mkdir
rmdir
umask
usleep
readlink
realpath
setenv
unsetenv
fallocate
ftruncate
fstat
strcasecmp
strncasecmp
strndup
popen
nl_langinfo
mbsinit
mbrtowc
getcwd
towlower
clearerr_unlocked
feof_unlocked
ferror_unlocked
fflush_unlocked
fgetc_unlocked
fgets_unlocked
fputc_unlocked
fputs_unlocked
fread_unlocked
fwrite_unlocked
fileno_unlocked
fgetwc_unlocked
getwc_unlocked
getwchar_unlocked
fputwc_unlocked
putwc_unlocked
putwchar_unlocked
fgetws_unlocked
fputws_unlocked
"
		for i in ${linux_funcs} ; do
			export ac_cv_have_decl_${i}=yes
			export ac_cv_func_${i}=yes
		done
		;;
	#*freebsd*)
	#*openbsd*)
	#*netbsd*)
	#*mingw*)
	esac
	#--
	if [ "$GLIBC_TOOLCHAIN" ] ; then
		export ac_cv_header_sched_h=yes
		export ac_cv_header_argp_h=yes
		export ac_cv_header_fts_h=yes
		export ac_cv_header_obstack_h=yes
		export ac_cv_header_error_h=yes
		glibc_funcs="
strerror_r
obstack_printf
posix_spawn
fcloseall
"
		for i in ${glibc_funcs} ; do
			export ac_cv_have_decl_${i}=yes
			export ac_cv_func_${i}=yes
		done
	fi
	#=== running_os - LINUX
	if [ -z "$RUNNING_OS" ] ; then
		export RUNNING_OS="$(uname -s)"
	fi
	if [ "$RUNNING_OS" = "Linux" ] ; then
		# GNU-LINUX - build system
		export ac_cv_path_mkdir=$(command -v mkdir)
		export MKDIR_P="${ac_cv_path_mkdir} -p"
		export ac_cv_path_install="$(command -v install) -c"
		export ac_cv_prog_AWK=awk
		export AWK=awk
		export GREP=grep
		export EGREP="$GREP -E"
		export FGREP="$GREP -F"
		export ac_cv_path_GREP=${GREP}
		export ac_cv_path_EGREP=${EGREP}
		export ac_cv_path_FGREP=${FGREP}
		export SED=sed
		export ac_cv_path_SED=sed
		export am_cv_make_support_nested_variables=yes
		export LN_S="ln -s"
		export am_cv_xargs_n_works=yes
	fi
}


check_sum_file_by_ext() # $1:file (determine by extension)
{
    # optional vars: $WDOWNLOAD_DIR
    #  $WSUMFILES_DIR - if $file is not a full path, prepend $WSUMFILES_DIR
    local file=$1
    case ${file} in
        *.sha512|*.SHA512) wchksum='sha512sum -c' ;;
        *.sha256|*.SHA256) wchksum='sha256sum -c' ;;
        *.sha1|*.SHA1)     wchksum='sha1sum -c'   ;;
        *.md5|*.MD5)       wchksum='md5sum -c'    ;;
        *) exit_error "$file: unknown checksum file extension..." ;;
    esac
    case ${file} in
        /*) wok=1 ;; #full path
        *) [ -n "$WSUMFILES_DIR" ] && file=${WSUMFILES_DIR}/${file} ;;
    esac
    if [ -n "$WDOWNLOAD_DIR" ] ; then
        xcurdirx=$(pwd)
        cmd_echo cd ${WDOWNLOAD_DIR}
        cmd_echo ${wchksum} "${file}"
        cmd_echo cd ${xcurdirx}
    else
        cmd_echo ${wchksum} "${file}"
    fi
}


extract_archive()   #$1:<archive> $2:[already_extracted_file]
{
	if [ ! "$WDOWNLOAD_DIR" ] ; then
		exit_error "extract_archive(): \$WDOWNLOAD_DIR has not been set"
	fi
	LAST_EXTRACTED_FILE=  #flag var
	#--
	if [ "$2" ] && [ -e "$2" ] ; then
		# file/dir is already extracted and we don't want to extract again
		echo "[extract] $2 already exists"
		return 0
	fi
	if [ -f "$1" ] ; then
		tfile="$1"
	elif [ -f "${WDOWNLOAD_DIR}/$1" ] ; then
		tfile="${WDOWNLOAD_DIR}/$1"
	else
		exit_error "extract_archive(): No such file: $1"
	fi
	case ${tfile} in
		*.tar.*|*.tgz|*.txz)
			cmd_echo tar ${WTAR_OPTS} -xf ${tfile}
			;;
		*.deb)
			xxdir=$(basename "$tfile" .deb)
			mkdir "$xxdir"
			if command -v undeb.sh >/dev/null 2>/dev/null ; then
				cmd_echo undeb.sh ${tfile} "$xxdir"
			else
				cmd_echo dpkg-deb -x ${tfile} "$xxdir"
			fi
			;;
		*) exit_error "extract_archive(): [FIXME] can't recognize extension of: $tfile"
			;;
	esac
	if [ $? -ne 0 ] ; then
		rm -fv ${tfile}
		exit_error
	fi
	LAST_EXTRACTED_FILE=${tfile}
}


download_file()   # $1:<URL> $2:[outfile]
{
    if [ -z "$1" ] ; then
        exit_error "download_file() called without arguments"
    fi
    if [ -z "$DL_CMD" ] ; then
        if command -v wget >/dev/null 2>&1 ; then
           DL_CMD='wget --no-check-certificate -c -O'
        elif command -v curl >/dev/null 2>&1 ; then
            DL_CMD='curl -k -C -L -o'
        else
            exit_error "curl and wget are missing"
        fi
    fi
    LAST_RETRIEVED_FILE= # flag var for the calling script to determine if a file was actually downloaded...
    local URL=${1}         # full url
    local OUTNAME=${1##*/} # basename
    if [ -n "$2" ] ; then
        OUTNAME=${2}
    fi
    #--
    xoutfilex="${WDOWNLOAD_DIR}/${OUTNAME}"
    ZZDL=1
    if [ -f "$xoutfilex" ] ; then
        ZZDL=0
        if [ ! -s "$xoutfilex" ] ; then
            ZZDL=1 # empty file , must redownload
            rm -fv "$xoutfilex"
        fi
    fi
    #--
    if [ $ZZDL -eq 0 ] ; then
        if [ "$DLD_ONLY" = "yes" ] ; then
            echo "Already downloaded ${OUTNAME}"
        fi
        return 0
    fi
    #--
    echo "Downloading ${URL}"
    ${DL_CMD} ${xoutfilex} "${URL}"
    if [ $? -ne 0 ] ; then
        rm -fv ${xoutfilex}
        exit_error
    fi
    LAST_RETRIEVED_FILE=${OUTNAME}
}


sysroot_remove_docs()  # $1:<sysroot_dir>
{
    wsrdir="$1"
    if [ ! -d "$wsrdir" ] ; then
        echo "sysroot_remove_docs: '$wsrdir' is not a directory "
        return -1
    fi
    for zdir in info man doc usr/man usr/doc \
        share/info share/man share/doc share/gtk-doc \
        usr/share/info usr/share/man usr/share/doc usr/share/gtk-doc
    do
        if [ -d ${wsrdir}/${zdir} ] ; then
            rm -rfv ${wsrdir}/${zdir}
        fi
    done
    # locales (should probably be moved to other func)
    for zdir in share/locale usr/share/locale
    do
        if [ -d ${wsrdir}/${zdir} ] ; then
            find ${wsrdir}/${zdir} -name '*.mo' -delete
        fi
    done
    # sometimes only an empty /usr/share remains...
    rmdir ${wsrdir}/usr/share 2>/dev/null
    return 0 #rmdir is allowed to fail
}



check_sum() # $1:type $2:sum $3:file
{
	local sumtype=$1
	local sum=$2
	local file=$3
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		exit_error "check_sum(): missing param(s)"
	fi
	if [ "$sumtype" = "sha512" ] ; then
		wchksum='sha512sum -c'
	elif [ "$sumtype" = "sha256" ] ; then
		wchksum='sha256sum -c'
	elif [ "$sumtype" = "sha1" ] ; then
		wchksum='sha1sum -c'
	elif [ "$sumtype" = "md5" ] ; then
		wchksum='md5sum -c'
	else
		exit_error "check_sum(): invalid checksum type"
	fi
	if [ -n "$WDOWNLOAD_DIR" ] ; then
		xcurdirx=$(pwd)
		cmd_echo cd ${WDOWNLOAD_DIR}
	fi
	echo "# echo \"$sum  $file\" | ${wchksum}"
	echo "$sum  $file" | ${wchksum}
	if [ $? -ne 0 ] ; then
		exit_error
	fi
	if [ -n "$WDOWNLOAD_DIR" ] ; then
		cd ${xcurdirx}
	fi
}


apply_patches_from_dir()  #$1:<patches_dir>
{
	# apply patches with any extension (files without extension are ignored)
	unset WPATCHES_APPLIED #flag
	if [ ! -d "$1" ] ; then
		exit_error "$1 is not a directory"
	fi
	for onepatch in $(ls ${1}/*.* 2>/dev/null)
	do
		if [ -f ${onepatch} ] ; then
			if [ -n "$patch_args" ] ; then
				cmd_echo patch ${patch_args} -i "${onepatch}"
			else
				cmd_echo patch -p1 -i "${onepatch}"
			fi
			WPATCHES_APPLIED=1
		fi
	done
}


create_pkg_config_file()
{
	xinstall_prefix="$1"
	xnamex="$2"
	xversionx="$3"
	xlibsx="$4"
	xpc_file=${xinstall_prefix}/lib/pkgconfig/${xnamex}.pc
	if [ -f "$xpc_file" ] ; then
		echo "** Overwriting $xpc_file"
	else
		echo "** Creating $xpc_file"
	fi
	mkdir -p $(dirname "$xpc_file")
	#--
	echo 'prefix='${xinstall_prefix}'
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include

Name: '${xnamex}'
Description: '${xnamex}'' > ${xpc_file}
	if [ -n "$xversionx" ] ; then
		echo 'Version: '${xversionx}'' >> ${xpc_file}
	fi
	if [ -n "$xlibsx" ] ; then
		echo 'Libs: -L${libdir} '${xlibsx}'
Cflags: -I${includedir}' >> ${xpc_file}
	fi
}


cc_set_version_vars()  # $1:<CC>
{
	# --help      : both clang & gcc send version in the 1st line, 3rd word
	# -dumpversion: clang may provide a fake version, this cannot be trusted
	unset cc_ver cc_ver_major cc_ver_minor
	unset cc_is_gnu
	if [ -z "$1" ] ; then
		exit_error "cc_set_version_vars: need a param"
	fi
	cc_ver_str="$($1 --version)"
	if [ -z "$cc_ver_str" ] ; then
		exit_error "cc_set_version_vars: $1 didn't produce a version reply"
	fi
	if [ -n "$(echo "$cc_ver_str" | grep "Free Software Foundation")" ] ; then
		cc_is_gnu=1
	fi
	cc_ver=$(echo "$cc_ver_str" | head -n 1 | cut -f 3 -d ' ')
	cc_ver_major=$(echo "$cc_ver" | cut -f 1 -d '.')
	cc_ver_minor=$(echo "$cc_ver" | cut -f 2 -d '.')
	if [ -z "$cc_ver_major" ] ; then
		exit_error "cc_set_version_vars: cannot determine version for $1"
	fi
}


cc_get_max_iso_cxx_properly_supported()
{
	# https://clang.llvm.org/cxx_status.html
	# https://gcc.gnu.org/projects/cxx-status.html
	# Taking library features into account:
	# - https://en.cppreference.com/w/cpp/compiler_support#C.2B.2B20_library_features
	# - https://en.cppreference.com/w/cpp/compiler_support/17#C.2B.2B17_library_features
	# - https://en.cppreference.com/w/cpp/compiler_support/14#C.2B.2B14_library_features
	# - https://en.cppreference.com/w/cpp/compiler_support/11#C.2B.2B11_library_features
	ver_ret=0  # error
	cc_set_version_vars ${1}
	if [ "$cc_is_gnu" ] ; then
		# gcc
		if [ ${cc_ver_major} -ge 11 ] ; then
			# by gcc 11, C++20 support is ok
			ver_ret=20
		elif [ ${cc_ver_major} -ge 9 ] ; then
			# by gcc 9, C++17 support is practically complete
			ver_ret=17
		elif [ ${cc_ver_major} -ge 5 ] ; then
			# by gcc 5, C++14 support is complete
			ver_ret=14
		elif vercmp ${cc_ver} ge 4.8 ; then
			# by gcc 4.8 core C++11 is ok, but not full library support..
			ver_ret=11
		else
			ver_ret=03  #C++ 2003
		fi
	else
		# clang
		if [ ${cc_ver_major} -ge 14 ] ; then
			ver_ret=20
		elif [ ${cc_ver_major} -ge 5 ] ; then
			ver_ret=17
		elif vercmp ${cc_ver} ge 3.3 ; then
			ver_ret=14
		elif vercmp ${cc_ver} ge 3.4 ; then
			ver_ret=11
		else
			ver_ret=03  #C++ 2003
		fi
	fi
	echo ${ver_ret}
	return ${ver_ret}
}


cc_get_max_iso_c_supported()
{
	# https://en.wikipedia.org/wiki/C11_(C_standard_revision)#cite_note-17
	# https://en.wikipedia.org/wiki/C17_(C_standard_revision)
	# https://en.wikipedia.org/wiki/C2x
	# https://gcc.gnu.org/wiki/C11Status
	# https://clang.llvm.org/c_status.html
	ver_ret=0  # error
	cc_set_version_vars ${1}
	if [ "$cc_is_gnu" ] ; then
		# gcc
		if [ ${cc_ver_major} -ge 8 ] ; then
			ver_ret=17
		elif vercmp ${cc_ver} ge 5 ; then
			# gcc 4.9 = complete C11 support, but use 5 as the minimum...
			ver_ret=11
		else
			ver_ret=09  #c99
		fi
	else
		# clang
		if [ ${cc_ver_major} -ge 6 ] ; then
			ver_ret=17
		elif vercmp ${cc_ver} ge 3.3 ; then
			ver_ret=11
		else
			ver_ret=09  #c99
		fi
	fi
	echo ${ver_ret}
	return ${ver_ret}
}


remove_dev_from_dir()
{
	if [ ! -d "$1" ] ; then
		exit_error "$1 is not a directory"
	fi
	rm -fv "${1}"/bin/*-config
	rm -rfv "${1}"/include "${1}"/usr/include
	for i in "${1}"/lib "${1}"/usr/lib
	do
		rm -rf "$i"/pkgconfig
		rm -fv "$i"/*.la "$i"/*.a
		find "$i" -type l -name '*.so' -delete
	done
	rm -rf "${1}"/share/aclocal
}
