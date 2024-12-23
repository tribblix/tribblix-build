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
# generate a map of device alias to driver package name
#
# these ought to be args
#
THOME=${THOME:-/packages/localsrc/Tribblix}
GATEDIR=/export/home/ptribble/Illumos/illumos-gate
MYREPO="redist"

usage() {
    echo "Usage: $0 [-T THOME] [-G date_directory] [-R repo_name]"
    exit 2
}

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
	*)
	    usage
	    ;;
    esac
done
shift $((OPTIND-1))

ARCH=$(uname -p)

REPODIR=${GATEDIR}/packages/${ARCH}/nightly-nd/repo.${MYREPO}
if [ ! -d "${REPODIR}" ]; then
    REPODIR=${GATEDIR}/packages/${ARCH}/nightly/repo.${MYREPO}
fi
if [ ! -d "${REPODIR}/pkg" ]; then
    echo "Error: cannot find package repo in ${GATEDIR}"
    exit 1
fi
cd "$REPODIR/pkg" || exit 1

CMD=${THOME}/tribblix-build/driver-map.sh
PNAME=${THOME}/tribblix-build/pkg_name.sh

for file in *
do
    IPKG=$($PNAME "$file")
    $CMD -T "$THOME" -G "$GATEDIR" -R "$MYREPO" "$file" "${IPKG}"
done
