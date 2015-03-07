#!/bin/sh
#
# create a report of illumos packages. They're either
#  - LIVE installed on the live image
#  - PKGS pkgs shipped on the iso
#  - UNUSED not on the iso at all
# FIXME: report if they're in some other overlay 
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
    echo "ERROR: $TARGET doesn't look like a build area"
    usage
fi
PKGS="${TARGET}/pkgs"
PDIR="${TARGET}/var/sadm/pkg"
OVDIR="${TARGET}/var/sadm/overlays"

cat $CATALOG | awk -F'|' '{print $1,$2}' | while read pkg ver
do
    if [ -d ${PDIR}/$pkg ]; then
	echo "LIVE $pkg"
    elif [ -f ${PKGS}/${pkg}.${ver}.zap ]; then
	echo "PKGS $pkg"
    else
	INOVL=`cat ${OVDIR}/*.pkgs | grep '^'$pkg'$'`
	if [ -n "$INOVL" ]; then
	    echo "OVERLAY $pkg"
	else
	    echo "UNUSED $pkg"
	fi
    fi
done
