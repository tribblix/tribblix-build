#!/bin/sh
#
# FIXME: do fdisk and partitions first
#

case $# in
0)
	echo "Usage: $0 device [overlay]"
	exit 1
	;;
*)
	DRIVE=$1
	shift
	;;
esac

if [ ! -e /dev/dsk/$DRIVE ]; then
    echo "Unable to find device $DRIVE"
    exit 1
fi

#
# FIXME allow mirrors
# FIXME allow ufs
# FIXME allow svm
#
/usr/bin/mkdir /a
echo "Creating root pool"
/usr/sbin/zpool create -f -o failmode=continue rpool $DRIVE

echo "Creating filesystems"
/usr/sbin/zfs create -o mountpoint=legacy rpool/ROOT
/usr/sbin/zfs create -o mountpoint=/a rpool/ROOT/tribblix
/usr/sbin/zpool set bootfs=rpool/ROOT/tribblix rpool
/usr/sbin/zfs create -o mountpoint=/a/export rpool/export
/usr/sbin/zfs create rpool/export/home
/usr/sbin/zfs create -V 2g -b 8k rpool/swap
/usr/sbin/zfs create -V 2g rpool/dump

echo "Copying main filesystems"
cd /
/usr/bin/find boot kernel lib platform root sbin usr etc var opt -print -depth | cpio -pdm /a
echo "Copying other filesystems"
cd /.cdrom
/usr/bin/find boot -print -depth | cpio -pdm /a
/usr/bin/find boot -print -depth | cpio -pdm /rpool

#
# FIXME: maybe have a pre-packaged dev tree on the cd
#
echo "Adding extra directories"
cd /a
/usr/bin/ln -s ./usr/bin .
/usr/bin/mkdir -m 1777 tmp
/usr/bin/mkdir -p system/contract system/object proc mnt dev devices/pseudo
/usr/bin/mkdir -p dev/fd dev/rmt dev/swap dev/dsk dev/rdsk dev/net dev/ipnet
/usr/bin/mkdir -p dev/sad dev/pts dev/term dev/vt dev/zcons
/usr/bin/chgrp -R sys dev devices
cd dev
/usr/bin/ln -s ./fd/2 stderr
/usr/bin/ln -s ./fd/1 stdout
/usr/bin/ln -s ./fd/0 stdin
/usr/bin/ln -s ../devices/pseudo/dld@0:ctl dld
cd /

#
# add overlays
#
# FIXME don't try and mount the pkgs if already mounted
#
if [ $# -gt 0 ]; then
  if [ -f /.cdrom/pkgs.zlib ]; then
    TMPDIR=/tmp
    export TMPDIR
    pkgs_lofi_dev=`/usr/sbin/lofiadm -a /.cdrom/pkgs.zlib`
    /sbin/mount -F hsfs -o ro ${pkgs_lofi_dev} /mnt/pkgs
    for overlay in $*
    do
      /var/sadm/overlays/install-overlay -R /a -s /mnt/pkgs $overlay
    done
  else
    echo "No pkgs.zlib, unable to install overlays"
  fi
fi

echo "Deleting live packages"
/usr/sbin/pkgrm -n -a /var/sadm/overlays/pkg.force -R /a TRIBsys-install-media-internal
#
# use a prebuilt repository if available
#
if [ -f /.cdrom/repository-installed.db ]; then
    /usr/bin/cp -p /.cdrom/repository-installed.db /a/etc/svc/repository.db
else
    /usr/bin/cp -p /lib/svc/seed/global.db /a/etc/svc/repository.db
fi

#
# reset the SMF profile from the live image to regular
#
/usr/bin/rm /a/etc/svc/profile/generic.xml
/usr/bin/ln -s generic_limited_net.xml /a/etc/svc/profile/generic.xml

#
# try and kill any copies of pkgserv, as they block the unmount of the
# target filesystem
#
pkill pkgserv

#
# /boot/grub is on the iso, but not necessarily in the ramdisk
#
echo "Installing GRUB"
/sbin/installgrub -fm /.cdrom/boot/grub/stage1 /.cdrom/boot/grub/stage2 /dev/rdsk/$DRIVE

echo "Configuring devices"
/a/usr/sbin/devfsadm -r /a
touch /a/reconfigure

echo "Setting up boot"
/usr/bin/mkdir -p /rpool/boot/grub/bootsign /rpool/etc
touch /rpool/boot/grub/bootsign/pool_rpool
echo "pool_rpool" > /rpool/etc/bootsign

/usr/bin/cat > /rpool/boot/grub/menu.lst << _EOF
title Tribblix 0.1
findroot (pool_rpool,0,a)
bootfs rpool/ROOT/tribblix
kernel\$ /platform/i86pc/kernel/\$ISADIR/unix -B \$ZFS-BOOTFS
module\$ /platform/i86pc/\$ISADIR/boot_archive
_EOF

#
# FIXME: why is this so much larger than a regular system?
# FIXME and why does it take so long - it's half the install budget
#
echo "Updating boot archive"
/usr/bin/mkdir -p /a/platform/i86pc/amd64
/sbin/bootadm update-archive -R /a
/usr/bin/sync
sleep 5

#
# Copy /jack to the installed system
#
# FIXME copy live or off the cd?
#
cd /.cdrom
find jack -print | cpio -pmud /a
sync
#
# this is to fix a 3s delay in xterm startup
#
echo "*openIm: false" > /a/jack/.Xdefaults
/usr/bin/chown jack:staff /a/jack/.Xdefaults

/usr/sbin/fuser -c /a
#
# remount zfs filesystem in the right place for next boot
#
/usr/sbin/zfs set mountpoint=/export rpool/export
/usr/sbin/zfs set mountpoint=/ rpool/ROOT/tribblix
