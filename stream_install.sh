#!/bin/sh
#

#
# these properties are available for customization
#
ROOTPOOL="rpool"
DRIVELIST=""
SWAPSIZE="2g"
DUMPSIZE=""
ZFSARGS=""
ZPOOLARGS=""
COMPRESSARGS="-O compression=lz4"
BFLAG=""
GFLAG=""
REBOOT="no"
NODENAME=""
TIMEZONE=""
DOMAINNAME=""
BEGIN_SCRIPT=""
FINISH_SCRIPT=""
FIRSTBOOT_SCRIPT=""
NEWBE="tribblix"

FSTYPE="ZFS"
DRIVE1=""
DRIVE2=""
PKGLOC="/.cdrom/pkgs"
SMFREPODIR="/usr/lib/zap"
ALTROOT="/a"

WCLIENT=/usr/bin/curl
WARGS="-f -s -S --retry 6 -o"
if [ ! -x $WCLIENT ]; then
    WCLIENT=/usr/bin/wget
    WARGS="-q --tries=6 --retry-connrefused --waitretry=2 -O"
fi

#
# read an external configuration file, if supplied
#
IPROFILE=`/sbin/devprop install_profile`
if [ ! -z "$IPROFILE" ]; then
REBOOT="yes"
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
	DELAY=0
	while [ ! -f "$TMPF" ]
	do
	    sleep $DELAY
	    DELAY=$(($DELAY+1))
	    ${WCLIENT} ${WARGS} $TMPF $IPROFILE
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
	mount $IPROFDIR $TMPMNT
	if [ -f ${TMPMNT}/${IPROFNAME} ]; then
	    ${TMPMNT}/${IPROFNAME} > $BEGINF
	fi
	umount ${TMPMNT}
	rmdir ${TMPMNT}
	;;
http*)
	TMPF="/tmp/profile.$$"
	${WCLIENT} ${WARGS} $TMPF $BEGIN_SCRIPT
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
# legacy -B now means the same as -G
# -b is the old -B escape hatch
#
while getopts "bBCd:Gm:n:P:s:t:z:Z:" opt; do
    case $opt in
        b)
	    BFLAG="-B"
	    ;;
        C)
	    COMPRESSARGS="-O compression=lz4"
	    ;;
        B)
	    GFLAG="-G"
	    ZPOOLARGS="-B"
	    ;;
        d)
	    DUMPSIZE="$OPTARG"
	    ;;
        G)
	    GFLAG="-G"
	    ZPOOLARGS="-B"
	    ;;
        m)
	    ZFSARGS="mirror"
	    DRIVE2="$OPTARG"
	    ;;
        n)
	    NODENAME="$OPTARG"
	    ;;
        P)
	    ROOTPOOL="$OPTARG"
	    ;;
        s)
	    SWAPSIZE="$OPTARG"
	    ;;
        t)
	    TIMEZONE="$OPTARG"
	    ;;
        z)
	    ZFSARGS="raidz1"
	    DRIVELIST="$OPTARG"
	    ;;
        Z)
	    ZFSARGS="raidz2"
	    DRIVELIST="$OPTARG"
	    ;;
    esac
done
shift $((OPTIND-1))

#
# the first remaining argument is a drive to install to
#
case $# in
0)
	printf ""
	;;
*)
	DRIVE1=$1
	shift
	;;
esac

#
# if we get to this point we shouldn't have any arguments
#
case $1 in
-*)
	echo "ERROR: unexpected argument $*"
	echo "(expecting an image)"
	exit 1
	;;
esac

#
# we should have 1 argument left, and it should either be an image
# filename or, in future, refer to a logical image name
#
case $# in
1)
    IMAGEFILE="$1"
    ;;
*)
    echo "Installation image not specified"
    exit 1
    ;;
esac

#
# verify we can actually find the image
#
if [ -f ${PKGLOC}/${IMAGEFILE} ]; then
    IMAGEFILE=${PKGLOC}/${IMAGEFILE}
else
    echo "Cannot find image"
    exit 1
fi

#
# end interactive argument handling
#

#
# cannot specify both -b and -G
#
if [ -n "${BFLAG}" -a -n "${GFLAG}" ]; then
    echo "ERROR: specify only one of -b and -G"
    exit 1
fi

#
# if we have a drive list at this point, it must be from cardigan or raidz, 
# so check the list for validity
#
if [ -n "$DRIVELIST" ]; then
  for TDRIVE in $DRIVELIST
  do
    if [ ! -e /dev/dsk/$TDRIVE ]; then
      if [ ! -e /dev/dsk/${TDRIVE}s0 ]; then
        echo "ERROR: Unable to find supplied device $TDRIVE"
        exit 1
      fi
    fi
  done
fi

#
# verify drives are valid
#

if [ -n "$DRIVE1" ]; then
    if [ ! -e /dev/dsk/$DRIVE1 ]; then
	if [ -e /dev/dsk/${DRIVE1}s0 ]; then
	    DRIVE1="${DRIVE1}s0"
	else
	    echo "ERROR: Unable to find device $DRIVE1"
	    exit 1
	fi
    fi
    DRIVELIST="$DRIVELIST $DRIVE1"
fi
if [ -n "$DRIVE2" ]; then
    if [ ! -e /dev/dsk/$DRIVE2 ]; then
	if [ -e /dev/dsk/${DRIVE2}s0 ]; then
	    DRIVE2="${DRIVE2}s0"
	else
	    echo "ERROR: Unable to find device $DRIVE2"
	    exit 1
	fi
    fi
    DRIVELIST="$DRIVELIST $DRIVE2"
fi

#
# if no drives are listed to install to, exit now
#
if [ -z "$DRIVELIST" ]; then
    echo "ERROR: no installation drives specified or found"
    echo "Usage: $0 [-G] [-n hostname] [-t timezone] [-m mirror_device] device image_file"
    exit 1
fi

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
# if we were asked for GPT, normalize names
#
case $GFLAG in
-G)
FDRIVELIST=""
for FDRIVE in $DRIVELIST
do
# normalize drive name, strip slice
case $FDRIVE in
*s?)
    NDRIVE=`echo $FDRIVE | /usr/bin/sed 's:s.$::'`
    ;;
*)
    NDRIVE="${FDRIVE}"
esac
    FDRIVELIST="$FDRIVELIST $NDRIVE"
done
DRIVELIST="$FDRIVELIST"
;;
esac

#
/usr/bin/mkdir -p ${ALTROOT}
echo "Creating root pool"
/usr/sbin/zpool create -f ${ZPOOLARGS} -o failmode=continue ${COMPRESSARGS} ${ROOTPOOL} $ZFSARGS $DRIVELIST

echo "Creating filesystems"
/usr/sbin/zfs create -o mountpoint=legacy ${ROOTPOOL}/ROOT
/usr/sbin/zfs create -o mountpoint=${ALTROOT} ${ROOTPOOL}/ROOT/${NEWBE}
/usr/sbin/zpool set bootfs=${ROOTPOOL}/ROOT/${NEWBE} ${ROOTPOOL}
#
# create swap area unless it's been explicitly disabled by setting
# SWAPSIZE to the empty string
#
if [ -n "${SWAPSIZE}" ]; then
    /usr/sbin/zfs create -V ${SWAPSIZE} -b 4k ${ROOTPOOL}/swap
fi
#
# only create dump device if DUMPSIZE has a value
# configure it now as well, so that the configuration will
# be copied to the installed system
#
if [ -n "${DUMPSIZE}" ]; then
    /usr/sbin/zfs create -V ${DUMPSIZE} ${ROOTPOOL}/dump
    /usr/sbin/dumpadm -c kernel -d /dev/zvol/dsk/${ROOTPOOL}/dump -y
fi

#
# this gives the BE a UUID, necessary for 'beadm list -H'
# to not show null, and for zone uninstall to work
#
/usr/sbin/zfs set org.opensolaris.libbe:uuid=`/usr/lib/zap/generate-uuid` ${ROOTPOOL}/ROOT/${NEWBE}

#
# this is where we send the image
#
GZCAT="/usr/bin/gzcat"
BZCAT="/usr/bin/bzcat"
XZCAT="/usr/bin/xz"
if [ -x /usr/bin/pbzcat ]; then
    BZCAT="/usr/bin/pbzcat"
fi
#
# OK, we're good to go
# need -F to send into an existing dataset
#
echo "Laying down image"
MYDSET="${ROOTPOOL}/ROOT/${NEWBE}"
case $IMAGEFILE in
    *.zfs)
	cat $IMAGEFILE | /usr/sbin/zfs recv -F $MYDSET
	;;
    *.zfs.gz)
	${GZCAT} $IMAGEFILE | /usr/sbin/zfs recv -F $MYDSET
	;;
    *.zfs.bz2)
	${BZCAT} $IMAGEFILE | /usr/sbin/zfs recv -F $MYDSET
	;;
    *.zfs.xz)
	${XZCAT} -d -c $IMAGEFILE | /usr/sbin/zfs recv -F $MYDSET
	;;
    *.tar)
	cd $ALTROOT
	cat $IMAGEFILE | /usr/sbin/tar xf -
	cd
	;;
    *.tar.gz)
	cd $ALTROOT
	${GZCAT} $IMAGEFILE | /usr/sbin/tar xf -
	cd
	;;
    *.tar.bz2)
	cd $ALTROOT
	${BZCAT} $IMAGEFILE | /usr/sbin/tar xf -
	cd
	;;
    *.tar.xz)
	cd $ALTROOT
	${XZCAT} -d -c $IMAGEFILE | /usr/sbin/tar xf -
	cd
	;;
    *)
	echo "Unrecognized file format $IMAGEFILE"
	exit 1
	;;
esac

#
# create export later, as mounting it blocks the zfs recv above
#
ls ${ALTROOT}
/usr/sbin/zfs create -o mountpoint=${ALTROOT}/export ${ROOTPOOL}/export
/usr/sbin/zfs create ${ROOTPOOL}/export/home

#
echo "Installing boot loader"
/sbin/bootadm install-bootloader -f -M -P ${ROOTPOOL}

echo "Configuring devices"
${ALTROOT}/usr/sbin/devfsadm -r ${ALTROOT}
touch ${ALTROOT}/reconfigure

#
# copy any console settings to the running system
#
BCONSOLE=""
ICONSOLE=`/sbin/devprop console`
if [ ! -z "$ICONSOLE" ]; then
  BCONSOLE=",console=${ICONSOLE},input-device=${ICONSOLE},output-device=${ICONSOLE}"
fi

echo "Setting up boot"

# new loader
/usr/bin/cat > /${ROOTPOOL}/boot/menu.lst << _EOF
title Tribblix 0.27
bootfs ${ROOTPOOL}/ROOT/${NEWBE}
_EOF

#
# set nodename if requested
#
if [ -n "$NODENAME" ]; then
    echo $NODENAME > ${ALTROOT}/etc/nodename
fi

#
# set domain name if requested
#
if [ -n "$DOMAINNAME" ]; then
    echo $DOMAINNAME > ${ALTROOT}/etc/defaultdomain
fi

#
# set timezone if requested
#
if [ -n "$TIMEZONE" ]; then
    mv ${ALTROOT}/etc/default/init ${ALTROOT}/etc/default/init.pre
    cat ${ALTROOT}/etc/default/init.pre | /usr/bin/sed s:PST8PDT:${TIMEZONE}: > ${ALTROOT}/etc/default/init
    rm ${ALTROOT}/etc/default/init.pre
fi

#
# enable swap
#
if [ -n "${SWAPSIZE}" ]; then
    /bin/echo "/dev/zvol/dsk/${ROOTPOOL}/swap\t-\t-\tswap\t-\tno\t-" >> ${ALTROOT}/etc/vfstab
fi

#
# if root has no password set, set it to a blank one
# Note: a blank password is not the same as a blank field in shadow
# this taken from Kayak
#
chmod u+w ${ALTROOT}/etc/shadow
ROOTPW='$5$kr1VgdIt$OUiUAyZCDogH/uaxH71rMeQxvpDEY2yX.x0ZQRnmeb9'
sed -i -e 's%^root::%root:'$ROOTPW':%' ${ALTROOT}/etc/shadow
chmod u-w ${ALTROOT}/etc/shadow

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
	mount $IPROFDIR $TMPMNT
	if [ -f ${TMPMNT}/${IPROFNAME} ]; then
	    ${TMPMNT}/${IPROFNAME} ${ALTROOT}
	fi
	umount ${TMPMNT}
	rmdir ${TMPMNT}
	;;
http*)
	TMPF="/tmp/profile.$$"
	${WCLIENT} ${WARGS} $TMPF $FINISH_SCRIPT
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
	mount $IPROFDIR $TMPMNT
	if [ -f ${TMPMNT}/${IPROFNAME} ]; then
	    cp ${TMPMNT}/${IPROFNAME} ${FIRSTF}
	fi
	umount ${TMPMNT}
	rmdir ${TMPMNT}
	;;
http*)
	TMPF="/tmp/profile.$$"
	${WCLIENT} ${WARGS} $TMPF $FIRSTBOOT_SCRIPT
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
KLAYOUT=`/usr/bin/kbd -l | /usr/bin/grep layout= | /usr/bin/awk -F= '{print $2}' | /usr/bin/awk '{print $1}'`
if [ -n "${KLAYOUT}" ]; then
  NLAYOUT=`/usr/bin/nawk -v ntyp=${KLAYOUT} -F= '{if ($2 == ntyp) print $1}' /usr/share/lib/keytables/type_6/kbd_layouts`
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
# moved later, must be done after we change any files such as bootenv.rc
#
echo "Updating boot archive"
/usr/bin/mkdir -p ${ALTROOT}/platform/i86pc/amd64
/sbin/bootadm update-archive -R ${ALTROOT}

#
# remount zfs filesystem in the right place for next boot
#
echo "The mount error below is expected"
/usr/sbin/zfs set mountpoint=/export ${ROOTPOOL}/export
/usr/sbin/zfs set canmount=noauto ${ROOTPOOL}/ROOT/${NEWBE}
/usr/sbin/zfs set mountpoint=/ ${ROOTPOOL}/ROOT/${NEWBE}

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
