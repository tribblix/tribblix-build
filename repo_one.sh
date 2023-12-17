#!/bin/ksh
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
# Copyright 2023 Peter Tribble
#

#
# generate all packages, in both datastream and zap formats, from
# an illumos build
#
# these ought to be args
#
PKG_VERSION="0.33"
THOME=${THOME:-/packages/localsrc/Tribblix}
GATEDIR=/export/home/ptribble/Illumos/illumos-gate
DSTDIR=/var/tmp/illumos-pkgs
MYREPO="redist"
QFLAG=""

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

#
# verify signing - the cert and key must exist
# if they don't, exit early
#
FINDELF=${GATEDIR}/usr/src/tools/scripts/find_elf
if [ -n "$SIGNCERT" ]; then
    if [ -r "${SIGNCERT}.key" -a -r "${SIGNCERT}.crt" ]; then
	:
    else
	echo "Error: invalid cert specified"
	exit 1
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="${GATEDIR}/usr/src/tools/find_elf/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="/opt/onbld/bin/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="/opt/onbld/bin/`uname -p`/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	echo "Cannot sign, find_elf missing"
	exit 1
    fi
    if [ ! -x /usr/bin/elfsign ]; then
	echo "Cannot sign, elfsign missing"
	echo "  (is TRIBdev-linker installed?)"
	exit 1
    fi
else
    echo "Error: a signing certificate is required"
    exit 1
fi

REPODIR=${GATEDIR}/packages/`uname -p`/nightly-nd/repo.${MYREPO}
if [ ! -d ${REPODIR} ]; then
    REPODIR=${GATEDIR}/packages/`uname -p`/nightly/repo.${MYREPO}
fi
if [ ! -d ${REPODIR} ]; then
    echo "Error: cannot find package repo in ${GATEDIR}"
    exit 1
fi

CMD=${THOME}/tribblix-build/repo2svr4.sh
PNAME=${THOME}/tribblix-build/pkg_name.sh
PKG2ZAP=${THOME}/tribblix-build/pkg2zap

mkdir -p ${DSTDIR}
cd $REPODIR/pkg

for file in $*
do
    echo Packaging $file as `$PNAME $file`
    if [ -n "$SIGNCERT" ]; then
	$CMD ${QFLAG} -T $THOME -V $PKG_VERSION -G $GATEDIR -D $DSTDIR -R $MYREPO -S $SIGNCERT $file `$PNAME $file`
    else
	$CMD ${QFLAG} -T $THOME -V $PKG_VERSION -G $GATEDIR -D $DSTDIR -R $MYREPO $file `$PNAME $file`
    fi
done

if [ "x${QFLAG}" = "x-Q" ]; then
    exit 0
fi

#
# convert the SVR4 pkg to zap format
# create an md5 checksum for the catalog
# optionally sign if we have a signing passphrase
#
for file in ${DSTDIR}/pkgs/*.pkg
do
    $PKG2ZAP $file ${DSTDIR}/pkgs
    openssl md5 ${file%.pkg}.zap | /usr/bin/awk '{print $NF}' > ${file%.pkg}.zap.md5
    if [ -f ${HOME}/Tribblix/Sign.phrase ]; then
	echo ""
	echo "Signing package."
	echo ""
	gpg --detach-sign --no-secmem-warning --passphrase-file ${HOME}/Tribblix/Sign.phrase ${file%.pkg}.zap
	if [ -f ${file%.pkg}.zap.sig ]; then
	    echo "Package signed successfully."
	    echo ""
	fi
    fi
done
