#!/bin/sh
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
# package the gfx-drm build
#

PKG_VERSION="0.33"
THOME=${THOME:-/packages/localsrc/Tribblix}
GATE="${HOME}/Illumos/gfx-drm"
DESTTOP="/var/tmp"
SIGNCERT=${HOME}/f/elfcert

usage() {
    echo "$0 [-G build_directory] [-V pkg_version] [-T tribblix_home]"
    echo "   [-D destination_dir] [-S signing_cert]"
    exit 1
}

while getopts "G:V:T:D:S:" opt; do
    case $opt in
        G)
	    GATE="$OPTARG"
	    ;;
        V)
	    PKG_VERSION="$OPTARG"
	    ;;
        T)
	    THOME="$OPTARG"
	    ;;
        D)
	    DESTTOP="$OPTARG"
	    ;;
        S)
	    SIGNCERT="$OPTARG"
	    ;;
        *)
	    usage
	    ;;
    esac
done
shift $((OPTIND-1))

if [ ! -d "${DESTTOP}" ]; then
    echo "Destination ${DESTTOP} not found"
    usage
fi
if [ ! -d "${GATE}" ]; then
    echo "Source tree ${GATE} not found"
    usage
fi
if [ ! -f "${THOME}/tribblix-build/repo_all.sh" ]; then
    echo "Packaging script not found"
    usage
fi
if [ ! -f "${SIGNCERT}.crt" ]; then
    echo "Signing cert not found"
    usage
fi

#
# package for the variants separately as the package version
# is different
#
"${THOME}/tribblix-build/repo_all.sh" \
  -G "${GATE}" \
  -D "${DESTTOP}/gfx-pkgs" \
  -V "${PKG_VERSION}" \
  -R drm \
  -S "${SIGNCERT}" > /var/tmp/gfx.log 2>&1
#
# don't need lx on sparc
#
case $(uname -p) in
i386)
  "${THOME}/tribblix-build/repo_all.sh" \
  -G "${GATE}" \
  -D "${DESTTOP}/omni-gfx-pkgs" \
  -V "${PKG_VERSION}lx" \
  -R drm \
  -S "${SIGNCERT}" > /var/tmp/omni-gfx.log 2>&1
  ;;
esac
