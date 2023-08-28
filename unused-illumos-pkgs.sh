#!/bin/ksh
#
# create a report of illumos packages. They're either
#  - LIVE installed on the live image
#  - MEDIAPKGS pkgs shipped on the iso
#  - OVERLAY listed in an overlay
#  - UNUSED not used anywhere at all
#
# naming such that if you pipe the output to sort then you get
# the status listed in a sensible preference order
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
    echo "ERROR: $TARGET doesn't look like a distribution area"
    usage
fi
PKGS="${TARGET}/pkgs"
PDIR="${TARGET}/var/sadm/pkg"
OVDIR="${TARGET}/var/sadm/overlays"

awk -F'|' '{print $1,$2}' "$CATALOG" | while read -r pkg ver
do
    if [ -d "${PDIR}/$pkg" ]; then
	echo "LIVE $pkg"
    elif [ -f "${PKGS}/${pkg}.${ver}.zap" ]; then
	echo "MEDIAPKGS $pkg"
    else
	INOVL=$(grep -h '^'$pkg'$' ${OVDIR}/*.pkgs)
	if [ -n "$INOVL" ]; then
	    echo "OVERLAY $pkg"
	else
	    echo "UNUSED $pkg"
	fi
    fi
done
