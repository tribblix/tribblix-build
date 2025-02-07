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
# create the UEFI bootblock
#
echo "Creating UEFI bootblock"

case $# in
    1)
	DISTDIR="$1"
	;;
    *)
	echo "Usage: $0 dist_dir"
	exit 1
	;;
esac

if [ ! -d $DISTDIR ]; then
    echo "Cannot find dist dir $DISTDIR"
    exit 1
fi

if [ ! -d ${DISTDIR}/boot ]; then
    echo "Dist dir $DISTDIR has no boot directory"
    exit 1
fi

mkfile 4M ${DISTDIR}/boot/efiboot.img
chmod o-t ${DISTDIR}/boot/efiboot.img
NLOFIDEV=`lofiadm -a ${DISTDIR}/boot/efiboot.img`
NLOFINUM=`echo $NLOFIDEV|awk -F/ '{print $NF}'`
echo "y" | env NOINUSE_CHECK=1 /usr/sbin/mkfs -F pcfs -o b=System,nofdisk,size=8800 /dev/rlofi/$NLOFINUM
NBFS=/tmp/nbefi.$$
mkdir $NBFS
mount -F pcfs $NLOFIDEV $NBFS
mkdir -p ${NBFS}/efi/boot

# cp messes with permissions and truncates the files
cat ${DISTDIR}/boot/loader32.efi > ${NBFS}/efi/boot/bootia32.efi
cat ${DISTDIR}/boot/loader64.efi > ${NBFS}/efi/boot/bootx64.efi

diff ${DISTDIR}/boot/loader32.efi ${NBFS}/efi/boot/bootia32.efi
diff ${DISTDIR}/boot/loader64.efi ${NBFS}/efi/boot/bootx64.efi

df -h ${NBFS}
umount $NBFS
lofiadm -d /dev/lofi/$NLOFINUM
rmdir $NBFS
ls -l ${DISTDIR}/boot/efiboot.img
