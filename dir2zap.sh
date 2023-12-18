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
# convert a directory full of packages in SVR4 datastream format to zap
#
# 7z is inordinately slow on a coolthreads sparc box, so it's much
# quicker to build the .pkg files there and do the zap conversion
# elsewhere
#
THOME=${THOME:-/packages/localsrc/Tribblix}
PKG2ZAP=${THOME}/tribblix-build/pkg2zap

case $# in
    1)
	PDIR="$1"
	;;
    *)
	echo "Usage: $0 dir_name"
	exit 1
	;;
esac

if [ ! -d $PDIR ]; then
    echo "Error: cannot find $PDIR"
    exit 1
fi

cd $PDIR
# reset PDIR to be absolute
PDIR=`pwd`

#
# convert the SVR4 pkg to zap format
#
for file in *.pkg
do
    $PKG2ZAP $file $PDIR
done
