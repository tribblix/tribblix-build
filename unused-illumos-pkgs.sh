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
# Create a report of the usage of illumos packages for a given release.
# This is based on the ISO image for that release, so is accurate and
# reproducible for a given point in time. Different ISO variants will
# differ in whether a given package is installed in the image, present
# as a package on the ISO, or referenced in an overlay, but will not
# differ in which packages are marked as unused.
#
# As this is based on the ISO image, it will work correctly for the
# sparc and lx images too, as it uses the metadata laid down in the
# image which will always match.
#
# They're either
#  - LIVE installed on the live image
#  - MEDIAPKGS pkgs shipped on the iso
#  - OVERLAY listed in an overlay
#  - UNUSED not used anywhere at all
#
# naming such that if you pipe the output to sort then you get
# the status listed in a sensible preference order
#

usage() {
    echo "Usage: $0 target_dir"
    exit 1
}

case $# in
1)
	TARGET=$1
	;;
*)
	usage
	;;
esac

if [ ! -d "$TARGET" ]; then
    echo "ERROR: no such directory $TARGET"
    usage
fi

#
# this is the catalog
#
CATALOG="${TARGET}/etc/zap/repositories/illumos.catalog"
if [ ! -f "$CATALOG" ]; then
    echo "ERROR: $TARGET doesn't look like a distribution area"
    usage
fi
PKGS="${TARGET}/pkgs"
PDIR="${TARGET}/var/sadm/pkg"
OVDIR="${TARGET}/var/sadm/overlays"

awk -F'|' '{print $1,$2}' "$CATALOG" | while read -r pkg ver
do
    if [ -d "${PDIR}/$pkg" ]; then
	echo "LIVE $pkg"
    elif [ -f "${PKGS}/${pkg}.${ver}.zap" ]; then
	echo "MEDIAPKGS $pkg"
    else
	INOVL=$(grep -h '^'"$pkg"'$' "${OVDIR}"/*.pkgs)
	if [ -n "$INOVL" ]; then
	    echo "OVERLAY $pkg"
	else
	    echo "UNUSED $pkg"
	fi
    fi
done
