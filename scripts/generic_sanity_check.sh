#!/bin/sh
#
# - this is sourced, must not exit unless it's an error
# - cross compiler is x86_64
# - cross compiler is not statically linked
#

# this is sourced by build.sh or func

if [ -z "$XPATH" ] ; then
    echo "\$XPATH is empty"
    exit 1
fi

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

if [ -n "$COMPILER_SYMLINK" ] ; then # set by targets/xxx
    if [ ! -e "$COMPILER_SYMLINK" ] ; then
        mkdir -p $(dirname ${COMPILER_SYMLINK})
        ln -snfv ${XPATH} ${COMPILER_SYMLINK}
    fi
fi

# extra sanity checks scripts
if [ -n "$SANITY_CHECK" ] ; then
    . ${SANITY_CHECK}    # script / set by targets/xxx
elif [ -n "$SANITY_CHECK_FUNC" ] ; then
    ${SANITY_CHECK_FUNC} # exported function / set by targets/xxx
elif [ -f "${XPATH}/sanity_check.sh" ] ; then
    . ${XPATH}/sanity_check.sh
fi
