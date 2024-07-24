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
# Copyright 2024 Peter Tribble
#

#
# this generates the equivalent of the driver database used by the ddu tool
# specifically, it maps device IDs to the name of the package that provides
# the driver for those IDs
#

THOME=${THOME:-/packages/localsrc/Tribblix}
GATEDIR=/export/home/ptribble/Illumos/illumos-gate
MYREPO="redist"
PNAME=${THOME}/tribblix-build/pkg_name.sh

#
# locations and variables should be passed as arguments
#
while getopts "T:G:R:" opt; do
    case $opt in
        T)
	    THOME="$OPTARG"
	    ;;
        G)
	    GATEDIR="$OPTARG"
	    ;;
        R)
	    MYREPO="$OPTARG"
	    ;;
    esac
done
shift $((OPTIND-1))

usage() {
    echo "Usage: $0 input_pkg [svr4_name]"
    exit 1
}


#
# parse a driver line in the manifest
#
handle_driver() {
DNAME=""
ALIASES=""
CLASS=""
EXTRA_CLASSES=""
for frag in "$@"
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
name)
    DNAME="$value"
    ;;
alias)
    if [ "x${ALIASES}" = "x" ]; then
	ALIASES="$value"
    else
	ALIASES="${ALIASES} $value"
    fi
    ;;
class)
    if [ "x${CLASS}" = "x" ]; then
	CLASS="$value"
    else
	EXTRA_CLASSES="${EXTRA_CLASSES} $value"
    fi
    ;;
*)
    :
    ;;
esac
done
#
# ddi_pseudo confuses the parser, override where it breaks
#
if [ "x${INPKG}" = "xdriver%2Fx11%2Fxsvc" ]; then
    DNAME="xsvc"
fi
if [ "x${INPKG}" = "xdriver%2Fstorage%2Fcpqary3" ]; then
    DNAME="cpqary3"
fi
if [ "x${INPKG}" = "xdriver%2Fcrypto%2Ftpm" ]; then
    DNAME="tpm"
fi
if [ "x${DNAME}" != "x" ]; then
    for ALIAS in $ALIASES
    do
	echo "${ALIAS}|${DNAME}|${CLASS}|${OUTPKG}"
    done
fi
}

case $# in
2)
    INPKG=$1
    OUTPKG=$2
    ;;
1)
    INPKG=$1
    OUTPKG=`$PNAME $INPKG`
    ;;
*)
    usage
    ;;
esac

ARCH=$(uname -p)
#
# these ought to be args
#
REPODIR="${GATEDIR}/packages/${ARCH}/nightly-nd/repo.${MYREPO}"
if [ ! -d "${REPODIR}" ]; then
    REPODIR="${GATEDIR}/packages/${ARCH}/nightly/repo.${MYREPO}"
fi
if [ ! -d "${REPODIR}" ]; then
    echo "ERROR: Missing repo"
    exit 1
fi
#
# find the input manifest
#
PDIR="${REPODIR}/pkg/${INPKG}"
if [ ! -d "${PDIR}" ]; then
    echo "ERROR: cannot find ${PDIR}"
    exit 1
fi
#
# skip packages marked as deleted
#
if [ -f "${TRANSDIR}/deleted/${OUTPKG}" ]; then
    exit 0
fi
if [ -f "${TRANSDIR}/deleted/${OUTPKG}.${ARCH}" ]; then
    exit 0
fi

MANIFEST=$(echo ${PDIR}/*)
if [ ! -f "$MANIFEST" ]; then
    exit 0
fi

#
# read the manifest, line by line
#
while read -r directive line
do
    case $directive in
	driver)
	    # the eval is some funky magic to pass quoted arguments
	    eval handle_driver $line
	    ;;
    esac
done < "$MANIFEST"
