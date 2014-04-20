#!/bin/sh
#
# FIXME: do fdisk and partitions first
#
# This installs to ufs. On a physical partition, not SVM (yet).
#
# The assumption is that root=s0 swap=s1
# and that the drive is already partitioned
#

case $# in
0)
	echo "Usage: $0 device [overlay ... ]"
	exit 1
	;;
esac

#
# these properties are available for customization
#
DRIVELIST=""
FSTYPE="UFS"

PKGLOC="/.cdrom/pkgs"
SMFREPODIR="/usr/lib/zap"

#
# read an external configuration file
#
IPROFILE=`/sbin/devprop install_profile`
if [ ! -z "$IPROFILE" ]; then
case $IPROFILE in
nfs*)
	TMPMNT="/tmp/mnt1"
	mkdir -p ${TMPMNT}
	IPROFDIR=${IPROFILE%/*}
	IPROFNAME=${IPROFILE##*/}
	mount $IPROFDIR $TMPMNT
	if [ -f ${TMPMNT}/${IPROFNAME} ]; then
	    . ${TMPMNT}/${IPROFNAME}
	fi
	umount ${TMPMNT}
	rmdir ${TMPMNT}
	;;
http*)
	TMPF="/tmp/profile.$$"
	/usr/bin/curl -f -s -o $TMPF $IPROFILE
	if [ -f "$TMPF" ]; then
	    . $TMPF
	    rm -fr $TMPF
	fi
	;;
esac
fi

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
/usr/bin/mkdir -p /a
echo "Creating root file system"
/usr/sbin/newfs /dev/rdsk/$DRIVE2
/usr/sbin/mount /dev/dsk/$DRIVE2 /a
mkdir -p /a/export/home

echo "Copying main filesystems"
cd /
/usr/bin/find boot kernel lib platform root sbin usr etc var opt zonelib -print -depth | cpio -pdm /a

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
# or an alternate location supplied by boot
#
# we create a zap config based on boot properties, should we copy that
# to the installed image as the highest priority repo? The problem
# there is that it will block all future updates
#
# give ourselves some swap to avoid /tmp exhaustion
# do it after copying the main OS as it changes the dump settings
#
swap -a /dev/zvol/dsk/rpool/swap
LOGFILE="/a/var/sadm/install/logs/initial.log"
echo "Installing overlays" | tee $LOGFILE
/usr/bin/date | tee -a $LOGFILE
TMPDIR=/tmp
export TMPDIR
PKGMEDIA=`/sbin/devprop install_pkgs`
if [ -d ${PKGLOC} ]; then
    for overlay in base-extras $*
    do
	echo "Installing $overlay overlay" | tee -a $LOGFILE
	/usr/lib/zap/install-overlay -R /a -s ${PKGLOC} $overlay | tee -a $LOGFILE
    done
elif [ -z "$PKGMEDIA" ]; then
    echo "No packages found, unable to install overlays"
else
    echo "/a/var/zap/cache" > /etc/zap/cache_dir
    echo "5 cdrom" >> /etc/zap/repo.list
    echo "NAME=cdrom" > /etc/zap/repositories/cdrom.repo
    echo "DESC=Tribblix packages from CD image" >> /etc/zap/repositories/cdrom.repo
    echo "URL=${PKGMEDIA}" >> /etc/zap/repositories/cdrom.repo
    /usr/lib/zap/refresh-catalog cdrom
    for overlay in base-extras $*
    do
	echo "Installing $overlay overlay" | tee -a $LOGFILE
	/usr/lib/zap/install-overlay -R /a $overlay | tee -a $LOGFILE
    done
fi
echo "Overlay installation complete" | tee -a $LOGFILE
/usr/bin/date | tee -a $LOGFILE

echo "Deleting live package"
/usr/sbin/pkgrm -n -a /usr/lib/zap/pkg.force -R /a TRIBsys-install-media-internal

#
# use a prebuilt repository if available
#
/usr/bin/rm /a/etc/svc/repository.db
if [ -f ${SMFREPODIR}/repository-installed.db ]; then
    /usr/bin/cp -p ${SMFREPODIR}/repository-installed.db /a/etc/svc/repository.db
elif [ -f ${SMFREPODIR}/repository-installed.db.gz ]; then
    /usr/bin/cp -p ${SMFREPODIR}/repository-installed.db.gz /a/etc/svc/repository.db.gz
    /usr/bin/gunzip /a/etc/svc/repository.db.gz
else
    /usr/bin/cp -p /lib/svc/seed/global.db /a/etc/svc/repository.db
fi
if [ -f /a/var/sadm/overlays/installed/kitchen-sink ]; then
    if [ -f ${SMFREPODIR}/repository-kitchen-sink.db.gz ]; then
	/usr/bin/rm /a/etc/svc/repository.db
	/usr/bin/cp -p ${SMFREPODIR}/repository-kitchen-sink.db.gz /a/etc/svc/repository.db.gz
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
echo "Installing GRUB"
for DRIVE in $DRIVELIST
do
    /sbin/installgrub -fm /boot/grub/stage1 /boot/grub/stage2 /dev/rdsk/$DRIVE
done

echo "Configuring devices"
/a/usr/sbin/devfsadm -r /a
touch /a/reconfigure

echo "Setting up boot"
/usr/bin/mkdir -p /a/boot/grub/bootsign /a/etc
touch /a/boot/grub/bootsign/tribblix_09
echo "tribblix_09" > /a/etc/bootsign

#
# copy any console settings to the running system
#
BCONSOLE=""
ICONSOLE=`/sbin/devprop console`
if [ ! -z "$ICONSOLE" ]; then
  BCONSOLE=" -B console=${ICONSOLE},input-device=${ICONSOLE},output-device=${ICONSOLE}"
fi

/usr/bin/cat > /a/boot/grub/menu.lst << _EOF
default 0
timeout 10
title Tribblix 0.9
findroot (tribblix_09,0,a)
kernel\$ /platform/i86pc/kernel/\$ISADIR/unix${BCONSOLE}
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
