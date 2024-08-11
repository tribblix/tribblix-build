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
# Copyright 2024 Peter Tribble
#

#
# given a drive, partitions it with a single large slice 0
# optionally lays down a single fdisk partition
#

#
# we want two slices - 8, and 0, plus slice 2
#

TFILE=/tmp/prtvtoc-input.$$
OFILE=/tmp/prtvtoc-output.$$

case $# in
2)
	BFLAG=$1
	DISKDEV=$2
	;;
1)
	DISKDEV=$1
	;;
*)
	echo "Usage: $0 [-B] disk_device"
	exit 1
	;;
esac

case $DISKDEV in
/*)
	printf ""
	;;
*)
	DISKDEV="/dev/rdsk/$DISKDEV"
	;;
esac

case $DISKDEV in
*s2)
	printf ""
	;;
*)
	DISKDEV="${DISKDEV}s2"
	;;
esac

if [ ! -e "$DISKDEV" ]; then
    echo "Error: unable to find disk device $DISKDEV"
    exit 1
fi

#
# first partition using fdisk, if requested
#
case $BFLAG in
-B)
	FDISKDEV=${DISKDEV%s2}p0
	if [ ! -e "$FDISKDEV" ]; then
	    echo "Error: unable to find disk device $FDISKDEV"
	    exit 1
	fi
	echo "Allocating whole disk $FDISKDEV to Solaris"
	/sbin/fdisk -B "$FDISKDEV"
	;;
esac

/usr/sbin/prtvtoc "$DISKDEV" | /usr/bin/grep -v '^\*' > $TFILE

#
# need to find the start of slice 0, which is the size of slice 8
# then the end should be where slice 2 ends
#
START0=$(/usr/bin/awk '{ if ($1 == "8") print $5}' $TFILE)
END0=$(/usr/bin/awk '{ if ($1 == "2") print $6}' $TFILE)
SIZE0=$((END0-START0))
SIZE0=$((SIZE0+1))

echo "0 2 00 $START0 $SIZE0" > $OFILE
/usr/bin/awk '{ if ($1 == "8") print $1,$2,$3,$4,$5}' $TFILE >> $OFILE

/usr/sbin/fmthard -s $OFILE "$DISKDEV"

/usr/bin/rm -f $TFILE $OFILE
