#!/bin/ksh
#
# SPDX-License-Identifier: CDDL-1.0
#
# {{{ CDDL HEADER
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source. A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#
# }}}
#
# Copyright 2025 Peter Tribble
#

#
# generate all packages, in both datastream and zap formats, from
# an illumos build
#
# these ought to be args
#
PKG_VERSION="0.37"
THOME=${THOME:-/packages/localsrc/Tribblix}
GATEDIR=/export/home/ptribble/Illumos/illumos-gate
DSTDIR=/var/tmp/illumos-pkgs
MYREPO="redist"
QFLAG=""

bail() {
    echo "ERROR: $1"
    exit 1
}

#
# locations and variables should be passed as arguments
#
while getopts "QV:T:G:D:M:R:S:" opt; do
    case $opt in
        Q)
	    QFLAG="-Q"
	    ;;
        V)
	    PKG_VERSION="$OPTARG"
	    ;;
        T)
	    THOME="$OPTARG"
	    ;;
        G)
	    GATEDIR="$OPTARG"
	    ;;
        D)
	    DSTDIR="$OPTARG"
	    ;;
        R)
	    MYREPO="$OPTARG"
	    ;;
        S)
	    SIGNCERT="$OPTARG"
	    ;;
    esac
done
shift $((OPTIND-1))

ARCH32=$(uname -p)
#
# verify signing - the cert and key must exist
# if they don't, exit early
#
FINDELF=${GATEDIR}/usr/src/tools/scripts/find_elf
if [ -n "$SIGNCERT" ]; then
    if [ -r "${SIGNCERT}.key" -a -r "${SIGNCERT}.crt" ]; then
	:
    else
	bail "invalid cert specified"
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="${GATEDIR}/usr/src/tools/find_elf/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="/opt/onbld/bin/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="/opt/onbld/bin/${ARCH32}/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	bail "Cannot sign, find_elf missing"
    fi
    if [ ! -x /usr/bin/elfsign ]; then
	bail "Cannot sign, elfsign missing (is TRIBdev-linker installed?)"
    fi
else
    bail "a signing certificate is required"
fi

REPODIR=${GATEDIR}/packages/${ARCH32}/nightly-nd/repo.${MYREPO}
if [ ! -d "${REPODIR}" ]; then
    REPODIR=${GATEDIR}/packages/${ARCH32}/nightly/repo.${MYREPO}
fi
if [ ! -d "${REPODIR}" ]; then
    bail "cannot find package repo in ${GATEDIR}"
fi

CMD=${THOME}/tribblix-build/repo2svr4.sh
PNAME=${THOME}/tribblix-build/pkg_name.sh
PKG2ZAP=${THOME}/tribblix-build/pkg2zap

mkdir -p "${DSTDIR}"
cd "$REPODIR/pkg" || bail "cannot cd"

for file in *
do
    npkgname=$($PNAME "$file")
    echo "Packaging $file as $npkgname"
    if [ -n "$SIGNCERT" ]; then
	$CMD ${QFLAG} -T "$THOME" -V "$PKG_VERSION" -G "$GATEDIR" -D "$DSTDIR" -R "$MYREPO" -S "$SIGNCERT" "$file" "$npkgname"
    else
	$CMD ${QFLAG} -T "$THOME" -V "$PKG_VERSION" -G "$GATEDIR" -D "$DSTDIR" -R "$MYREPO" "$file" "$npkgname"
    fi
done

if [ "${QFLAG}" = "-Q" ]; then
    exit 0
fi

#
# convert the SVR4 pkg to zap format
#
for file in "${DSTDIR}"/pkgs/*.pkg
do
    $PKG2ZAP "$file" "${DSTDIR}/pkgs"
done
