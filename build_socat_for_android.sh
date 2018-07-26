#!/bin/bash
# build socat for android
# g0, 2018

if [ "$1" = "-h" -o "$1" = "-help" ]
  then
    echo -e "\t $0 arch api_version rmbuild verbose stip"
    echo -e "\t example: $0 arm64 24 rmbuild"
    echo -e "\t with no arguments, it will  attempt to build socat for the android seen over adb"
    echo ""
    exit 0
fi

COLORS=1
DEFAULT_ARCH='arm'
DEFAULT_SDKV='23'

SDKV=$(adb shell getprop ro.build.version.sdk 2>/dev/null)
[ -z "$SDKV" ] && SDKV=$DEFAULT_SDKV

ARCH=$(adb shell getprop ro.product.cpu.abi 2>/dev/null)
[ -z "$ARCH" ] && ARCH=$DEFAULT_ARCH
[[ "$ARCH" = *"-"* ]] && ARCH=$(echo "$ARCH" |awk -F '-' '{print $1}')

_not_in_archs(){
  archs=(arm arm64 mips mips64 x86 x86_64)
  for arch in ${archs[*]}
    do
      [ "$arch" = "$1" ] && return 1
  done
  echo "$1 is not a supported arch."
  return 0
}

if _not_in_archs $ARCH; then
   ARCH=$DEFAULT_ARCH
fi

[ "$COLORS" -eq "1" ] && ESC8='\033['
[ "$COLORS" -eq "1" ] && GREEN=${ESC8}"01;32m"
[ "$COLORS" -eq "1" ] && RED=${ESC8}"31;01m"
[ "$COLORS" -eq "1" ] && RESET=${ESC8}"00m"
STATUS=0

_die(){
  printf "${RED}%s${RESET}\n" "${1}"
  STATUS=$((STATUS+1))
  exit $STATUS
}

_say(){
  printf "${GREEN}%s${RESET}\n" "${1}"
}

# ARCH='arm64'
# SDKV='26'
# OP3='rmbuild'
# OP4='verbose'
# OP5='strip'
[ $# -ge 1 ] && ARCH=$1
[ $# -ge 2 ] && SDKV=$2
[ $# -ge 3 ] && OP3=$3
[ $# -ge 4 ] && OP4=$4
[ $# -ge 5 ] && OP5=$5

_say "Building socat for Architecture:$ARCH, Android SDK API version:$SDKV"

ROOT=`pwd`
BUILD="${ROOT}/builds/${ARCH}_${SDKV}"
mkdir -p $BUILD

HOST='arm-linux-androideabi'
TCDIR="${BUILD}/toolchain_${ARCH}${SDKV}"
SYSROOT="${BUILD}/toolchain_${ARCH}${SDKV}/sysroot"

[[ "$ARCH" = 'arm' ]] && HOST='arm-linux-androideabi'
[[ "$ARCH" = 'arm64' ]] && HOST='aarch64-linux-android'
[[ "$ARCH" = 'x86' ]] && HOST='i686-linux-android'
[[ "$ARCH" = 'x86_64' ]] && HOST='x86_64-linux-android'
[[ "$ARCH" = 'mips' ]] && HOST='mipsel-linux-android'
[[ "$ARCH" = 'mips64' ]] && HOST='mips64el-linux-android'

CC="$TCDIR/bin/$HOST-clang --sysroot=$SYSROOT"
LD="$TCDIR/bin/$HOST-ld"
AR="$TCDIR/bin/$HOST-ar"
RANLIB="$TCDIR/bin/$HOST-ranlib"
STRIP="$TCDIR/bin/$HOST-strip"
# CLIBS="-lm -lefence"
# LIBS="-static"

CFLAGS="-fPIE -fPIC"
# CFLAGS="-fPIE -fPIC -fno-debug-info-for-profiling -fno-debug-macro"
[[ "$OP4" = 'verbose' ]] && CFLAGS="$CFLAGS -v"

LDFLAGS="-fPIE -pie"
# LDFLAGS="-fPIE -pie -static"
[[ "$OP4" = 'verbose' ]] && LDFLAGS="$LDFLAGS -v"

_say "HOST: $HOST"
_say "CC: $CC"
_say "CFLAGS: $CFLAGS"
_say "LD: $LD"
_say "LDFLAGS: $LDFLAGS"
_say "AR: $AR"
_say "RANLIB: $RANLIB"
# _say "CLIBS: $CLIBS"
# _say "LIBS: $LIBS"

export RANLIB="$RANLIB"
export AR="$AR"
# export CLIBS="$CLIBS"
# export LIBS="$LIBS"

rm -rf $TCDIR
V=''
[[ "$OP4" = 'verbose' ]] && V="-v"
make_standalone_toolchain.py ${V} --arch $ARCH --api $SDKV --install-dir $TCDIR --force

# Create configure script
cd ${ROOT}
autoconf || _die "autoconf failed"

# config.h and Makefile
cd ${BUILD}
${ROOT}/configure \
--disable-openssl \
--host=$HOST \
CC="$CC" \
LD="$LD" \
CFLAGS="$CFLAGS" \
LDFLAGS="$LDFLAGS" \
RANLIB="$RANLIB" \
AR="$AR" \
|| _die "configure failed"

# Replace misconfigured values in config.h and enable PTY functions
mv config.h config.old
# | sed 's/\/\* #undef WITH_OPENSSL \*\//#define WITH_OPENSSL 1/' \
cat config.old \
 | sed 's/CRDLY_SHIFT.*/CRDLY_SHIFT 9/' \
 | sed 's/TABDLY_SHIFT.*/TABDLY_SHIFT 11/' \
 | sed 's/CSIZE_SHIFT.*/CSIZE_SHIFT 4/' \
 | sed 's/\/\* #undef HAVE_OPENPTY \*\//#define HAVE_OPENPTY 1/' \
 | sed 's/\/\* #undef HAVE_GRANTPT \*\//#define HAVE_GRANTPT 1/' \
 | sed 's/#define HAVE_RESOLV_H 1/\/\* #undef HAVE_RESOLV_H \*\//' \
 > config.h


# Enable openpty() in Makefile
mv Makefile Makefile.old
cat Makefile.old | sed 's/error.c/error.c openpty.c/' > Makefile

# Provide openpty.c
cat >openpty.c <<EOF
/* Copyright (C) 1998, 1999, 2004 Free Software Foundation, Inc.
   This file is part of the GNU C Library.
   Contributed by Zack Weinberg <zack@rabi.phys.columbia.edu>, 1998.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
   02111-1307 USA.  */

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/ioctl.h>

#define _PATH_DEVPTMX "/dev/ptmx"

int openpty (int *amaster, int *aslave, char *name, struct termios *termp,
    struct winsize *winp)
{
  char buf[PATH_MAX];
  int master, slave;

  master = open(_PATH_DEVPTMX, O_RDWR);
  if (master == -1)
    return -1;

  if (grantpt(master))
    goto fail;

  if (unlockpt(master))
    goto fail;

  if (ptsname_r(master, buf, sizeof buf))
    goto fail;

  slave = open(buf, O_RDWR | O_NOCTTY);
  if (slave == -1)
    goto fail;

  /* XXX Should we ignore errors here?  */
  if (termp)
    tcsetattr(slave, TCSAFLUSH, termp);
  if (winp)
    ioctl(slave, TIOCSWINSZ, winp);

  *amaster = master;
  *aslave = slave;
  if (name != NULL)
    strcpy(name, buf);

  return 0;

fail:
  close(master);
  return -1;
}
EOF

_handle_bin(){
  if [ -e "${BUILD}/${1}" ]
    then
      mkdir -p ${ROOT}/binaries/${ARCH}/${SDKV}
      cp ${BUILD}/socat ${ROOT}/binaries/${ARCH}/${SDKV}/${1}
      [[ "$OP5" = 'strip' ]] && $STRIP ${ROOT}/binaries/${ARCH}/${SDKV}/${1}

      _say "Build finished, ${1} has been generated successfuly in ${ROOT}/binaries/$ARCH/$SDKV/${1}"
  else
      STATUS=$((STATUS+1))
      printf "${RED}%s${RESET}\n" "${1} was not made"
  fi
}

MAKE='make'
J=$(sysctl -n hw.ncpu)
[ "$J" -ge 2 -a "$J" -le 16 ] && MAKE="make -j${J}"
_say "$MAKE"

$MAKE socat || _die "make failed"
_say "Build finished, socat has been generated successfuly in $BUILD/socat"

$MAKE filan
$MAKE procan

_handle_bin "socat"
_handle_bin "filan"
_handle_bin "procan"

if [ "$OP3" = 'rmbuild' -a -d "$BUILD" ]
  then
    rm -r ${BUILD}
    [ ! -d "$BUILD" ] && _say "deleted $BUILD"
fi

exit $STATUS
