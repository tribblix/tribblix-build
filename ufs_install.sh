#!/bin/sh
#
# FIXME: do fdisk and partitions first
#
# This installs to ufs. On a physical partition, not SVM (yet).
#
# The assumption is that root=s0 swap=s1
#

case $# in
0)
	echo "Usage: $0 device [overlay ... ]"
	exit 1
	;;
esac

DRIVELIST=""

case $# in
0)
	echo "Usage: $0 device [overlay ... ]"
	exit 1
	;;
esac

DRIVE2=$1
shift
DRIVELIST="$DRIVE2"

if [ ! -e /dev/dsk/$DRIVE2 ]; then
    echo "ERROR: Unable to find device $DRIVE2"
    exit 1
fi

case $DRIVE2 in
*s0)
	SWAPDEV=`echo $DRIVE2 | sed 's:s0$:s1:'`
	;;
*)
	echo "ERROR: Root slice must be slice 0"
	exit 1
	;;
esac

#
# FIXME allow svm
#
/usr/bin/mkdir /a
echo "Creating root file system"
/usr/sbin/newfs /dev/rdsk/$DRIVE2
/usr/sbin/mount /dev/dsk/$DRIVE2 /a
mkdir -p /a/export/home

echo "Copying main filesystems"
cd /
/usr/bin/find boot kernel lib platform root sbin usr etc var opt zonelib -print -depth | cpio -pdm /a
echo "Copying other filesystems"
cd /.cdrom
/usr/bin/find boot -print -depth | cpio -pdm /a

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
# add overlays, from the pkgs directory on the iso
#
#
# give ourselves some swap to avoid /tmp exhaustion
# only necessary if we add packages which use /tmp for unpacking
# also, do it after copying the main OS as it changes the dump settings
#
if [ $# -gt 0 ]; then
  swap -a /dev/dsk/$SWAPDEV
  LOGFILE="/a/var/sadm/install/logs/initial.log"
  echo "Installing overlays" | tee $LOGFILE
  /usr/bin/date | tee -a $LOGFILE
  if [ -d /.cdrom/pkgs ]; then
    TMPDIR=/tmp
    export TMPDIR
    for overlay in $*
    do
      echo "Installing $overlay overlay" | tee -a $LOGFILE
      /var/sadm/overlays/install-overlay -R /a -s /.cdrom/pkgs $overlay | tee -a $LOGFILE
    done
  else
    echo "No packages found, unable to install overlays"
  fi
  echo "Overlay installation complete" | tee -a $LOGFILE
  /usr/bin/date | tee -a $LOGFILE
fi

echo "Deleting live packages"
/usr/sbin/pkgrm -n -a /var/sadm/overlays/pkg.force -R /a TRIBsys-install-media-internal
#
# use a prebuilt repository if available
#
/usr/bin/rm /a/etc/svc/repository.db
if [ -f /.cdrom/repository-installed.db ]; then
    /usr/bin/cp -p /.cdrom/repository-installed.db /a/etc/svc/repository.db
elif [ -f /.cdrom/repository-installed.db.gz ]; then
    /usr/bin/cp -p /.cdrom/repository-installed.db.gz /a/etc/svc/repository.db.gz
    /usr/bin/gunzip /a/etc/svc/repository.db.gz
else
    /usr/bin/cp -p /lib/svc/seed/global.db /a/etc/svc/repository.db
fi
if [ -f /a/var/sadm/overlays/installed/kitchen-sink ]; then
    if [ -f /.cdrom/repository-kitchen-sink.db.gz ]; then
	/usr/bin/rm /a/etc/svc/repository.db
	/usr/bin/cp -p /.cdrom/repository-kitchen-sink.db.gz /a/etc/svc/repository.db.gz
	/usr/bin/gunzip /a/etc/svc/repository.db.gz
    fi
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
for DRIVE in $DRIVELIST
do
    /sbin/installgrub -fm /.cdrom/boot/grub/stage1 /.cdrom/boot/grub/stage2 /dev/rdsk/$DRIVE
done

echo "Configuring devices"
/a/usr/sbin/devfsadm -r /a
touch /a/reconfigure

echo "Setting up boot"
/usr/bin/mkdir -p /a/boot/grub/bootsign /a/etc
touch /a/boot/grub/bootsign/tribblix_07
echo "tribblix_07" > /a/etc/bootsign

/usr/bin/cat > /a/boot/grub/menu.lst << _EOF
title Tribblix 0.7
findroot (tribblix_07,0,a)
kernel\$ /platform/i86pc/kernel/\$ISADIR/unix
module\$ /platform/i86pc/\$ISADIR/boot_archive
_EOF

#
# mount / at boot and enable swap
#
/bin/echo "/dev/dsk/$DRIVE2\t/dev/rdsk/$DRIVE2\t/\tufs\t1\tno\tlogging" >> /a/etc/vfstab
/bin/echo "/dev/dsk/$SWAPDEV\t-\t-\tswap\t-\tno\t-" >> /a/etc/vfstab

#
# need to put the device path of the root slice into bootenv.rc so
# the boot can find it
#
BOOTDEV=`/bin/ls -l /dev/dsk/$DRIVE2 | awk '{print $NF}' | sed s:../../devices::'`
echo "setprop bootpath $BOOTDEV" >> /a/boot/solaris/bootenv.rc

#
# FIXME: why is this so much larger than a regular system?
# FIXME and why does it take so long - it's half the install budget
#
echo "Updating boot archive"
/usr/bin/mkdir -p /a/platform/i86pc/amd64
/sbin/bootadm update-archive -R /a
/usr/bin/sync
sleep 2

#
# Copy /jack to the installed system
#
cd /
find jack -print | cpio -pmud /a
/usr/bin/rm -f /a/jack/.bash_history
sync
#
# this is to fix a 3s delay in xterm startup
#
echo "*openIm: false" > /a/jack/.Xdefaults
/usr/bin/chown jack:staff /a/jack/.Xdefaults
