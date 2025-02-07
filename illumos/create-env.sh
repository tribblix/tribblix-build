#!/bin/sh
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
# Copyright 2023 Peter Tribble
#

#
# this creates env files from a template
#
# currently x86, creates both vanilla and lx
#

THOME=${THOME:-/packages/localsrc/Tribblix}
export THOME

IYEAR=""
IMONTH=""
IRELEASE=""

BUILDHOME=${BUILDHOME:-${HOME}/Illumos}
#
# by default we put the env files into the build area
# rather than back into the repo
#
DESTDIR=${BUILDHOME}

while getopts "d:m:y:" opt; do
    case $opt in
	d)
	    DESTDIR="$OPTARG"
	    ;;
	m)
	    IMONTH="$OPTARG"
	    ;;
	y)
	    IYEAR="$OPTARG"
	    ;;
    esac
done
shift $((OPTIND-1))

#
# what's left has to be the release
#
case $# in
    1)
	IRELEASE="$1"
	;;
    *)
	echo "Usage: $0 [-d destdir] [-y year] [-m month] release"
	exit 1
	;;
esac

#
# sanity check, and we need to find the template
#
TFILE="${THOME}/tribblix-build/illumos/illumos.sh.template"
if [ ! -f "${TFILE}" ]; then
    echo "ERROR: cannot find template"
    exit 1
fi
if [ ! -d "${DESTDIR}" ]; then
    echo "ERROR: destination does not exist"
    exit 1
fi
if [ -f "${DESTDIR}/illumos.sh.${IRELEASE}" ]; then
    echo "ERROR: illumos.sh.${IRELEASE} already exists"
    exit 1
fi
if [ -f "${DESTDIR}/illumos.sh.${IRELEASE}lx" ]; then
    echo "ERROR: illumos.sh.${IRELEASE}lx already exists"
    exit 1
fi

#
# if values not supplied, fill them in
#
if [ -z "${IYEAR}" ]; then
    IYEAR=$(date +%Y)
fi
if [ -z "${IMONTH}" ]; then
    IMONTH=$(date +%B)
fi

#
# the version used in the filename for the LX variant has the lx in the middle
#
case $IRELEASE in
    *.*)
	LRELEASE=${IRELEASE/./lx.}
	;;
    *)
	LRELEASE=${IRELEASE}lx
	;;
esac

#
# create the template, substituting values
#
cat $TFILE | sed -e s:@iyear@:${IYEAR}:g -e s:@imonth@:${IMONTH}:g -e s:@irelease@:${IRELEASE}:g -e s:@iname@:tribblix: > ${DESTDIR}/illumos.sh.${IRELEASE}
cat $TFILE | sed -e s:@iyear@:${IYEAR}:g -e s:@imonth@:${IMONTH}:g -e s:@irelease@:${IRELEASE}:g -e s:@iname@:omnitribblix: > ${DESTDIR}/illumos.sh.${LRELEASE}

#
# and tell the user what we've done
#
echo "Created illumos.sh.${IRELEASE} and illumos.sh.${LRELEASE}"
echo "in ${DESTDIR}"
