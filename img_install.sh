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
# Copyright 2025 Peter Tribble
#

#
# This script allows you to install a copy of Tribblix into an existing
# zfs pool. Unlike over_install, which assumes you're booted into the
# live environment, this script assumes you're running an alternative
# illumos instance in normal mode
#
# ./img_install.sh [-B] [-N] rpool [overlays ...]
#
# You need to specify the name of the pool, usually rpool.
# You can specify overlays just like the normal install.
# We install a new bootloader to the pool, to be sure it's consistent
# with the bits we install. With -B, also update the MBR.
#
# While the menu will only show this new instance of Tribblix, any
# old BEs will still be present. Due to the change in bootloader they
# cannot be activated with beadm, but can be accessed manually
#
# We may copy account details (group, passwd, shadow) and the system ssh keys
# from the existing BE. Any existing ZFS file systems will automatically
# transfer across unchanged. All other customizations are left to the user.
# With -N, don't copy any details from the old BE
#

#
# these properties are available for customization
#
ROOTPOOL="rpool"
BFLAG=""
REBOOT="no"
OVERLAYS=""
NODENAME=""
TIMEZONE=""
DOMAINNAME=""
BEGIN_SCRIPT=""
FINISH_SCRIPT=""
FIRSTBOOT_SCRIPT=""
RELEASE="m37"
DLHOST="https://pkgs.tribblix.org"
NFLAG=""

PKGLOC="/.cdrom/pkgs"
# this will be relocated to the image later
SMFREPODIR="/usr/lib/zap"
ALTROOT="/a"

WCLIENT=/usr/bin/curl
WARGS="-f -s -S --retry 6 -o"
if [ ! -x $WCLIENT ]; then
    WCLIENT=/usr/bin/wget
    WARGS="-q --tries=6 --retry-connrefused --waitretry=2 -O"
fi

bail() {
    echo "ERROR: $1"
    exit 1
}

#
# read an external configuration file, if supplied
#
IPROFILE=$(/sbin/devprop install_profile)
if [ -n "$IPROFILE" ]; then
REBOOT="yes"
case $IPROFILE in
nfs*)
	TMPMNT="/tmp/mnt1"
	mkdir -p ${TMPMNT}
	IPROFDIR=${IPROFILE%/*}
	IPROFNAME=${IPROFILE##*/}
	mount "$IPROFDIR" $TMPMNT
	if [ -f "${TMPMNT}/${IPROFNAME}" ]; then
	    . "${TMPMNT}/${IPROFNAME}"
	fi
	umount ${TMPMNT}
	rmdir ${TMPMNT}
	;;
http*)
	TMPF="/tmp/profile.$$"
	DELAY=0
	while [ ! -f "$TMPF" ]
	do
	    sleep $DELAY
	    DELAY=$((DELAY+1))
	    ${WCLIENT} ${WARGS} $TMPF "$IPROFILE"
	done
	. $TMPF
	rm -fr $TMPF
	;;
esac
fi

#
# begin script handling
# the begin script is run and its output saved
# then we source the output, this allows you to
# dynamically create install settings
#
if [ -n "$BEGIN_SCRIPT" ]; then
BEGINF="/tmp/begin.$$"
case $BEGIN_SCRIPT in
nfs*)
	TMPMNT="/tmp/mnt1"
	mkdir -p ${TMPMNT}
	IPROFDIR=${BEGIN_SCRIPT%/*}
	IPROFNAME=${BEGIN_SCRIPT##*/}
	mount "$IPROFDIR" $TMPMNT
	if [ -f "${TMPMNT}/${IPROFNAME}" ]; then
	    "${TMPMNT}/${IPROFNAME}" > $BEGINF
	fi
	umount ${TMPMNT}
	rmdir ${TMPMNT}
	;;
http*)
	TMPF="/tmp/profile.$$"
	${WCLIENT} ${WARGS} $TMPF "$BEGIN_SCRIPT"
	if [ -s "$TMPF" ]; then
	    chmod a+x $TMPF
	    $TMPF > $BEGINF
	fi
	rm -f $TMPF
	;;
esac
if [ -s "$BEGINF" ]; then
    . $BEGINF
fi
rm -f $BEGINF
fi

#
# interactive argument handling
#
while getopts "BNn:r:t:" opt; do
    case $opt in
        B)
	    BFLAG="-M"
	    ;;
        N)
	    NFLAG="no"
	    ;;
        n)
	    NODENAME="$OPTARG"
	    ;;
        r)
	    RELEASE="$OPTARG"
	    ;;
        t)
	    TIMEZONE="$OPTARG"
	    ;;
    esac
done
shift $((OPTIND-1))

#
# now we know which release is requested, map that to an image
#
NEWBE="tribblix-${RELEASE}"
IMGTMP="/var/tmp/${NEWBE}.archive"
IMGSRC="${DLHOST}/${RELEASE}/platform/i86pc/boot_archive"
case $RELEASE in
    m35)
	IMGSUM="75248c7be915bcca5e08c31030e5c1474f5dbc13"
	;;
    m35lx)
	IMGSUM="c2c1763adc2046b07b0653d45f4f2f3d447aaab3"
	;;
    m36)
	IMGSUM="22afdba0bbb35175509b27145a559aedd3d41adf"
	;;
    m36lx)
	IMGSUM="297392ead67f64e722de287e0cc35b1fa1509474"
	;;
    m36.1)
	IMGSUM="464fee4a318643625c271327dceae5b5b1b9d40c"
	;;
    m36lx.1)
	IMGSUM="feae950a0f20ca3934e1bd4c71b194a80ba2d030"
	;;
    m37)
	IMGSUM="22834138619d61a7d1544d17fbc0f391a3da420f"
	;;
    m37lx)
	IMGSUM="c72bd7fcdd29f03f29145df4e1e7833a4075d88f"
	;;
    *)
	bail "Unrecognised release"
	;;
esac

#
# the first remaining argument is a pool to install to
#
case $# in
0)
	echo "ERROR: You must specify an existing pool to install to"
	echo "Usage: $0 [-B] [-N] [-r release] old_pool [overlay ... ]"
	echo "  with -B, replace mbr"
	echo "  with -N, don't transfer anything from old system"
	exit 1
	;;
*)
	ROOTPOOL=$1
	shift
	;;
esac

#
# if we get to this point we shouldn't have any arguments
#
case $1 in
-*)
	bail "unexpected argument $* (expecting overlays)"
	;;
esac

#
# everything else is an overlay
#
OVERLAYS="$OVERLAYS $*"

#
# end interactive argument handling
#

#
# first download the image
#
if [ ! -f "$IMGTMP" ]; then
    ${WCLIENT} ${WARGS} "$IMGTMP" "$IMGSRC"
    if [ ! -f "$IMGTMP" ]; then
	bail "Download failed, stopping"
    fi
fi
DLSUM=$(openssl sha1 "$IMGTMP" | awk '{print $NF}')
if [ "X${IMGSUM}" != "X${DLSUM}" ]; then
    bail "Download has wrong checksum, stopping"
fi
#
# now we have an image, mount it up and verify
# the check might need adjusting for other images
#
AFDEV=$(/usr/sbin/lofiadm -a "$IMGTMP")
AFMNT="/mnt.${NEWBE}"
mkdir "$AFMNT"
/usr/sbin/mount -Fufs -o ro "$AFDEV" "$AFMNT"
if [ ! -f "${AFMNT}/usr/bin/ls" ]; then
    echo "Image downloaded is unsuitable, no /usr/bin/ls"
    echo "Cleaning up and stopping"
    /usr/sbin/umount "$AFMNT"
    /usr/sbin/lofiadm -d "$AFDEV"
    rmdir "$AFMNT"
    exit 1
fi
#
# at this point we should have a valid image
#
SMFREPODIR="${AFMNT}/usr/lib/zap"

#
# use the existing pool
#
/usr/bin/mkdir -p ${ALTROOT}

#
# this is what the original boot file system was set to
# we mount it later to recover specific data
#
OLDBE=$(/usr/sbin/zpool get -Hp -o value bootfs "${ROOTPOOL}")
if [ -z "$OLDBE" ]; then
    echo "Pool ${ROOTPOOL} has no bootfs property, cannot use."
    /usr/sbin/umount "$AFMNT"
    /usr/sbin/lofiadm -d "$AFDEV"
    rmdir "$AFMNT"
    exit 1
fi

echo "Creating filesystems"
/usr/sbin/zfs create -o mountpoint=${ALTROOT} "${ROOTPOOL}/ROOT/${NEWBE}"
/usr/sbin/zpool set bootfs="${ROOTPOOL}/ROOT/${NEWBE}" "${ROOTPOOL}"

#
# we copy from the image here, not from / as on the live system
#
echo "Copying main filesystems"
cd "$AFMNT" || bail "cd to image failed"
ZONELIB=""
if [ -d zonelib ]; then
    ZONELIB="zonelib"
fi
/usr/bin/find boot kernel lib platform root sbin usr etc var opt ${ZONELIB} -print -depth | cpio -pdm ${ALTROOT}
echo "Copying other filesystems"
/usr/bin/find boot -print -depth | cpio -pdm /"${ROOTPOOL}"

#
# this gives the BE a UUID, necessary for 'beadm list -H'
# to not show null, and for zone uninstall to work
#
/usr/sbin/zfs set org.opensolaris.libbe:uuid=$(${ALTROOT}/usr/lib/zap/generate-uuid) "${ROOTPOOL}/ROOT/${NEWBE}"

#
echo "Adding extra directories"
cd ${ALTROOT} || bail "cd to alternate root failed"
/usr/bin/ln -s ./usr/bin .
/usr/bin/mkdir -m 1777 tmp
/usr/bin/mkdir -p system/contract system/object system/boot proc mnt dev devices/pseudo
/usr/bin/mkdir -p dev/fd dev/rmt dev/swap dev/dsk dev/rdsk dev/net dev/ipnet
/usr/bin/mkdir -p dev/sad dev/pts dev/term dev/vt dev/zcons
/usr/bin/chgrp -R sys dev devices mnt
/usr/bin/chmod 555 system system/* proc
cd dev || bail "cd to dev in alternate root failed"
/usr/bin/ln -s ./fd/2 stderr
/usr/bin/ln -s ./fd/1 stdout
/usr/bin/ln -s ./fd/0 stdin
/usr/bin/ln -s ../devices/pseudo/dld@0:ctl dld
cd /

#
# the man pages might be compressed to save space
#
if [ -f ${ALTROOT}/usr/share/liveman.tar.bz2 ] ; then
    cd ${ALTROOT}/usr/share || bail "cd to usr/share in alternate root failed"
    bzcat liveman.tar.bz2 | tar xf -
    rm -f liveman.tar.bz2
    cd /
fi

#
# delete mkisofs from the installed image, we have an unpackaged copy
# on the bootable /usr which we use to optimize boot archive creation
#
/usr/bin/rm -f ${ALTROOT}/usr/bin/mkisofs

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
swap -a "/dev/zvol/dsk/${ROOTPOOL}/swap"
LOGFILE="${ALTROOT}/var/sadm/install/logs/initial.log"
echo "Installing overlays" | tee $LOGFILE
/usr/bin/date | tee -a $LOGFILE
TMPDIR=/tmp
export TMPDIR
echo "${ALTROOT}/var/zap/cache" > /etc/zap/cache_dir
if [ -d ${PKGLOC} ]; then
    for overlay in base $OVERLAYS
    do
	echo "Installing $overlay overlay" | tee -a $LOGFILE
	/usr/lib/zap/install-overlay -R ${ALTROOT} -s ${PKGLOC} "$overlay" | tee -a $LOGFILE
    done
else
    echo "No local packages found, trying to install overlays from the network"
    echo "Installing base overlay" | tee -a $LOGFILE
    /usr/lib/zap/install-overlay -R ${ALTROOT} base | tee -a $LOGFILE
    # only try other overlays if base worked, to minimize wasteage
    if [ -f ${ALTROOT}/var/sadm/overlays/installed/base ]; then
	for overlay in $OVERLAYS
	do
	    echo "Installing $overlay overlay" | tee -a $LOGFILE
	    /usr/lib/zap/install-overlay -R ${ALTROOT} "$overlay" | tee -a $LOGFILE
	done
    else
	echo "Ignoring overlay installation due to failure" | tee -a $LOGFILE
    fi
fi
echo "Overlay installation complete" | tee -a $LOGFILE
/usr/bin/date | tee -a $LOGFILE

echo "Deleting live package" | tee -a $LOGFILE
#/usr/bin/zap uninstall -R ${ALTROOT} TRIBsys-install-media-internal
/usr/sbin/pkgrm -n -a ${ALTROOT}/usr/lib/zap/pkg.force -R ${ALTROOT} TRIBsys-install-media-internal

#
# use a prebuilt repository if available
#
/usr/bin/rm ${ALTROOT}/etc/svc/repository.db
if [ -f "${SMFREPODIR}/repository-installed.db.gz" ]; then
    /usr/bin/cp -p "${SMFREPODIR}/repository-installed.db.gz" ${ALTROOT}/etc/svc/repository.db.gz
    /usr/bin/gunzip ${ALTROOT}/etc/svc/repository.db.gz
else
    /usr/bin/cp -p ${ALTROOT}/lib/svc/seed/global.db ${ALTROOT}/etc/svc/repository.db
fi
#
# We have an x11 version because we have to enable hal
#
if [ -f ${ALTROOT}/var/sadm/overlays/installed/x11 ]; then
    if [ -f "${SMFREPODIR}/repository-x11.db.gz" ]; then
	/usr/bin/rm ${ALTROOT}/etc/svc/repository.db
	/usr/bin/cp -p "${SMFREPODIR}/repository-x11.db.gz" ${ALTROOT}/etc/svc/repository.db.gz
	/usr/bin/gunzip ${ALTROOT}/etc/svc/repository.db.gz
    fi
fi
if [ -f ${ALTROOT}/var/sadm/overlays/installed/kitchen-sink ]; then
    if [ -f "${SMFREPODIR}/repository-kitchen-sink.db.gz" ]; then
	/usr/bin/rm ${ALTROOT}/etc/svc/repository.db
	/usr/bin/cp -p "${SMFREPODIR}/repository-kitchen-sink.db.gz" ${ALTROOT}/etc/svc/repository.db.gz
	/usr/bin/gunzip ${ALTROOT}/etc/svc/repository.db.gz
    fi
fi

#
# reset the SMF profile from the live image to regular
#
/usr/bin/rm ${ALTROOT}/etc/svc/profile/generic.xml
/usr/bin/ln -s generic_limited_net.xml ${ALTROOT}/etc/svc/profile/generic.xml

#
# shut down pkgserv, as it blocks the unmount of the target filesystem
#
pkgadm sync -R ${ALTROOT} -q

echo "Configuring devices"
${ALTROOT}/usr/sbin/devfsadm -r ${ALTROOT}
touch ${ALTROOT}/reconfigure

echo "Setting up boot"

# new loader
/usr/bin/cat > /"${ROOTPOOL}"/boot/menu.lst << _EOF
title Tribblix ${RELEASE}
bootfs ${ROOTPOOL}/ROOT/${NEWBE}
_EOF

#
# set nodename if requested
#
if [ -n "$NODENAME" ]; then
    echo "$NODENAME" > ${ALTROOT}/etc/nodename
fi

#
# set domain name if requested
#
if [ -n "$DOMAINNAME" ]; then
    echo "$DOMAINNAME" > ${ALTROOT}/etc/defaultdomain
fi

#
# set timezone if requested
#
if [ -n "$TIMEZONE" ]; then
    /usr/bin/sed -i s:PST8PDT:"${TIMEZONE}": ${ALTROOT}/etc/default/init
fi

#
# enable swap
#
/bin/echo "/dev/zvol/dsk/${ROOTPOOL}/swap\t-\t-\tswap\t-\tno\t-" >> ${ALTROOT}/etc/vfstab

#
# Copy /jack to the installed system
#
cd "$AFMNT" || bail "cd to image failed"
find jack -print | cpio -pmud ${ALTROOT}
/usr/bin/rm -f ${ALTROOT}/jack/.bash_history

#
# this is to fix a 3s delay in xterm startup
#
echo "*openIm: false" > ${ALTROOT}/jack/.Xdefaults
/usr/bin/chown -hR 123:10 ${ALTROOT}/jack

#
# if specified, run a finish script
# the new root directory is passed as the only argument
#
if [ -n "$FINISH_SCRIPT" ]; then
case $FINISH_SCRIPT in
nfs*)
	TMPMNT="/tmp/mnt1"
	mkdir -p ${TMPMNT}
	IPROFDIR=${FINISH_SCRIPT%/*}
	IPROFNAME=${FINISH_SCRIPT##*/}
	mount "$IPROFDIR" $TMPMNT
	if [ -f "${TMPMNT}/${IPROFNAME}" ]; then
	    "${TMPMNT}/${IPROFNAME}" ${ALTROOT}
	fi
	umount ${TMPMNT}
	rmdir ${TMPMNT}
	;;
http*)
	TMPF="/tmp/profile.$$"
	${WCLIENT} ${WARGS} $TMPF "$FINISH_SCRIPT"
	if [ -s "$TMPF" ]; then
	    chmod a+x $TMPF
	    $TMPF ${ALTROOT}
	fi
	rm -f $TMPF
	;;
esac
fi

#
# remove the autoinstall startup script
#
/bin/rm -f ${ALTROOT}/etc/rc2.d/S99auto_install
sync
sleep 2

#
# if specified, enable a first-boot script
#
if [ -n "$FIRSTBOOT_SCRIPT" ]; then
FIRSTDIR="${ALTROOT}/etc/tribblix"
FIRSTF="${FIRSTDIR}/firstboot"
mkdir ${FIRSTDIR}
case $FIRSTBOOT_SCRIPT in
nfs*)
	TMPMNT="/tmp/mnt1"
	mkdir -p ${TMPMNT}
	IPROFDIR=${FIRSTBOOT_SCRIPT%/*}
	IPROFNAME=${FIRSTBOOT_SCRIPT##*/}
	mount "$IPROFDIR" $TMPMNT
	if [ -f "${TMPMNT}/${IPROFNAME}" ]; then
	    cp "${TMPMNT}/${IPROFNAME}" ${FIRSTF}
	fi
	umount ${TMPMNT}
	rmdir ${TMPMNT}
	;;
http*)
	TMPF="/tmp/profile.$$"
	${WCLIENT} ${WARGS} $TMPF "$FIRSTBOOT_SCRIPT"
	if [ -s "$TMPF" ]; then
	    cp $TMPF $FIRSTF
	fi
	rm -f $TMPF
	;;
esac
if [ -s "${FIRSTF}" ]; then
    chmod a+x $FIRSTF
cat >> ${ALTROOT}/etc/rc3.d/S99firstboot <<EOF
#!/bin/sh
if [ -f /etc/tribblix/firstboot ]; then
mv /etc/tribblix/firstboot /etc/tribblix/firstboot.run
/etc/tribblix/firstboot.run
rm /etc/tribblix/firstboot.run
fi
rm /etc/rc3.d/S99firstboot
EOF
    chmod a+x ${ALTROOT}/etc/rc3.d/S99firstboot
fi
fi

#
# copy selected keyboard type to installed system
#
KLAYOUT=$(/usr/bin/kbd -l | /usr/bin/awk -F'[= ]' '{if ($1 == "layout") print $2}')
if [ -n "${KLAYOUT}" ]; then
  NLAYOUT=$(/usr/bin/awk -v ntyp="${KLAYOUT}" -F= '{if ($2 == ntyp) print $1}' /usr/share/lib/keytables/type_6/kbd_layouts)
  if [ -n "${NLAYOUT}" ]; then
    /usr/bin/grep -v keyboard-layout ${ALTROOT}/boot/solaris/bootenv.rc > ${ALTROOT}/boot/solaris/bootenv.rc.tmp
    echo "setprop keyboard-layout ${NLAYOUT}" >> ${ALTROOT}/boot/solaris/bootenv.rc.tmp
    /usr/bin/mv ${ALTROOT}/boot/solaris/bootenv.rc.tmp ${ALTROOT}/boot/solaris/bootenv.rc
    /usr/bin/rm -f /tmp/keymap-set
    echo "repository ${ALTROOT}/etc/svc/repository.db" > /tmp/keymap-set
    echo "select keymap:default" >> /tmp/keymap-set
    echo "setprop keymap/layout=${NLAYOUT}"  >> /tmp/keymap-set
    /usr/sbin/svccfg -f /tmp/keymap-set
    /usr/bin/rm -f /tmp/keymap-set
  fi
fi

#
# we can copy some stuff off the existing system,
# just basic identity
# not the ssh config files because of sunssh vs openssh differences
# copying disabled with -N
#
# you can still mount the old BE later to retrieve data if you need to
#
if [ -z "$NFLAG" ]; then
    /usr/bin/cp -p /etc/passwd ${ALTROOT}/etc/passwd
    /usr/bin/cp -p /etc/group ${ALTROOT}/etc/group
    /usr/bin/cp -p /etc/shadow ${ALTROOT}/etc/shadow
    /usr/bin/cp -p /etc/ssh/ssh_host* ${ALTROOT}/etc/ssh
    if [ -z "$NODENAME" ]; then
	/usr/bin/cp -p /etc/nodename ${ALTROOT}/etc/nodename
    fi
fi
#
# this is separate, we always copy any root authorized keys as they're
# needed on AWS
#
if [ -f /root/.ssh/authorized-keys ]; then
    /usr/bin/mkdir -p ${ALTROOT}/root/.ssh
    /usr/bin/chmod 0700 ${ALTROOT}/root/.ssh
    /usr/bin/cp -p /root/.ssh/authorized-keys ${ALTROOT}/root/.ssh
    /usr/bin/sed -i 's:PermitRootLogin no:PermitRootLogin without-password:' ${ALTROOT}/etc/ssh/sshd_config
fi
/usr/sbin/zfs set canmount=noauto "${OLDBE}"

#
# moved later, must be done after we change any files such as bootenv.rc
#
echo "Updating boot archive"
/usr/bin/mkdir -p ${ALTROOT}/platform/i86pc/amd64
/sbin/bootadm update-archive -R ${ALTROOT}

#
# remount zfs filesystem in the right place for next boot
#
echo "The mount error below is expected"
/usr/sbin/zfs set canmount=noauto "${ROOTPOOL}/ROOT/${NEWBE}"
/usr/sbin/zfs set mountpoint=/ "${ROOTPOOL}/ROOT/${NEWBE}"

#
# we need to install our bootloader to be sure we have one
# that is compatible
# we overwrite the MBR if -B was passed
#
/sbin/bootadm install-bootloader ${BFLAG} -f -P "${ROOTPOOL}"

#
# if specified, reboot
#
case $REBOOT in
yes)
	echo "Install complete, rebooting"
	/sbin/sync
	/usr/sbin/reboot -p
	;;
esac

#
# welcome
#
echo ""
echo "Welcome to Tribblix"
echo "Any feedback will be gratefully received at tribblix@gmail.com"
echo ""
