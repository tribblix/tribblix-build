#!/bin/sh
#

case $# in
0)
	echo "Usage: $0 [-B] [ -m device ] device [overlay ... ]"
	exit 1
	;;
esac

#
# these properties are available for customization
#
DRIVELIST=""
SWAPSIZE="2g"
FSTYPE="ZFS"
ZFSARGS=""
BFLAG=""

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

#
# interactive argument handling
#

#
# if requested, format the drive
#
case $1 in
-B)
	shift
	BFLAG="-B"
	;;
esac

#
# handle zfs mirrors
#
case $1 in
-m)
	shift
	DRIVE1=$1
	shift
	if [ ! -e /dev/dsk/$DRIVE1 ]; then
	    if [ -e /dev/dsk/${DRIVE1}s0 ]; then
		DRIVE1="${DRIVE1}s0"
	    else
		echo "ERROR: Unable to find device $DRIVE1"
		exit 1
	    fi
	fi
	ZFSARGS="mirror"
	DRIVELIST="$DRIVE1"
	;;
-*)
	echo "Usage: $0 [-B] [ -m device ] device [overlay ... ]"
	exit 1
	;;
esac

case $# in
0)
	echo "Usage: $0 [-B] [ -m device ] device [overlay ... ]"
	exit 1
	;;
esac

DRIVE2=$1
shift

if [ ! -e /dev/dsk/$DRIVE2 ]; then
    if [ -e /dev/dsk/${DRIVE2}s0 ]; then
	DRIVE2="${DRIVE2}s0"
    else
	echo "ERROR: Unable to find device $DRIVE2"
	exit 1
    fi
fi
DRIVELIST="$DRIVELIST $DRIVE2"

#
# end interactive argument handling
#

#
# if we were asked to fdisk the drive, do so
#
case $BFLAG in
-B)
FDRIVELIST=""
for FDRIVE in $DRIVELIST
do
# normalize drive name, replace slice by slice2 for fdisk and by s0 for zpool
case $FDRIVE in
*s?)
    NDRIVE=`echo $FDRIVE | /usr/bin/sed 's:s.$:s2:'`
    FDRIVE=$NDRIVE
    NDRIVE=`echo $FDRIVE | /usr/bin/sed 's:s.$:s0:'`
    ;;
*)
    NDRIVE="${FDRIVE}s0"
    FDRIVE="${FDRIVE}s2"
esac
    FDRIVELIST="$FDRIVELIST $NDRIVE"
    /root/format-a-disk.sh -B $FDRIVE
done
DRIVELIST="$FDRIVELIST"
;;
esac

#
# FIXME allow ufs
# FIXME allow svm
#
/usr/bin/mkdir -p /a
echo "Creating root pool"
/usr/sbin/zpool create -f -o failmode=continue rpool $ZFSARGS $DRIVELIST

echo "Creating filesystems"
/usr/sbin/zfs create -o mountpoint=legacy rpool/ROOT
/usr/sbin/zfs create -o mountpoint=/a rpool/ROOT/tribblix
/usr/sbin/zpool set bootfs=rpool/ROOT/tribblix rpool
/usr/sbin/zfs create -o mountpoint=/a/export rpool/export
/usr/sbin/zfs create rpool/export/home
/usr/sbin/zfs create -V ${SWAPSIZE} -b 4k rpool/swap
/usr/sbin/zfs create -V ${SWAPSIZE} rpool/dump

#
# this gives the initial BE a UUID, necessary for 'beadm list -H'
# to not show null, and for zone uninstall to work
#
/usr/sbin/zfs set org.opensolaris.libbe:uuid=`/usr/lib/zap/generate-uuid` rpool/ROOT/tribblix

echo "Copying main filesystems"
cd /
/usr/bin/find boot kernel lib platform root sbin usr etc var opt zonelib -print -depth | cpio -pdm /a
echo "Copying other filesystems"
/usr/bin/find boot -print -depth | cpio -pdm /rpool

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
/usr/bin/mkdir -p /rpool/boot/grub/bootsign /rpool/etc
touch /rpool/boot/grub/bootsign/pool_rpool
echo "pool_rpool" > /rpool/etc/bootsign

#
# copy any console settings to the running system
#
BCONSOLE=""
ICONSOLE=`/sbin/devprop console`
if [ ! -z "$ICONSOLE" ]; then
  BCONSOLE=",console=${ICONSOLE},input-device=${ICONSOLE},output-device=${ICONSOLE}"
fi

/usr/bin/cat > /rpool/boot/grub/menu.lst << _EOF
default 0
timeout 10
title Tribblix 0.9
findroot (pool_rpool,0,a)
bootfs rpool/ROOT/tribblix
kernel\$ /platform/i86pc/kernel/\$ISADIR/unix -B \$ZFS-BOOTFS${BCONSOLE}
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
sleep 2

#
# enable swap
#
/bin/echo "/dev/zvol/dsk/rpool/swap\t-\t-\tswap\t-\tno\t-" >> /a/etc/vfstab

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

/usr/sbin/fuser -c /a
#
# remount zfs filesystem in the right place for next boot
#
/usr/sbin/zfs set mountpoint=/export rpool/export
/usr/sbin/zfs set mountpoint=/ rpool/ROOT/tribblix
