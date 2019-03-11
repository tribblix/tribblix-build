#!/bin/ksh
#
# generate all packages, in both datastream and zap formats, from
# an illumos build
#
# these ought to be args
#
PKG_VERSION="0.20lx.6"
THOME=${THOME:-/packages/localsrc/Tribblix}
GATEDIR=/export/home/ptribble/Illumos/omnitribblix
DSTDIR=/var/tmp/omni-pkgs

#
# locations and variables should be passed as arguments
#
while getopts "V:T:G:D:M:S:" opt; do
    case $opt in
        V)
	    PKG_VERSION="$OPTARG"
	    ;;
        T)
	    THOME="$OPTARG"
	    ;;
        G)
	    GATEDIR="$OPTARG"
	    ;;
        D)
	    DSTDIR="$OPTARG"
	    ;;
        S)
	    SIGNCERT="$OPTARG"
	    ;;
    esac
done
shift $((OPTIND-1))

#
# verify signing - the cert and key must exist
# if they don't, exit early
#
if [ -n "$SIGNCERT" ]; then
    if [ -r "${SIGNCERT}.key" -a -r "${SIGNCERT}.crt" ]; then
	:
    else
	echo "Error: invalid cert specified"
	exit 1
    fi
    if [ ! -x "${GATEDIR}/usr/src/tools/scripts/find_elf" ]; then
	echo "Cannot sign, find_elf missing"
	exit 1
    fi
    if [ ! -x /usr/bin/elfsign ]; then
	echo "Cannot sign, elfsign missing"
	echo "  (is TRIBdev-linker installed?)"
	exit 1
    fi
else
    echo "Error: a signing certificate is required"
    exit 1
fi

REPODIR=${GATEDIR}/packages/`uname -p`/nightly-nd/repo.redist

CMD=${THOME}/tribblix-build/repo2svr4.sh
PNAME=${THOME}/tribblix-build/pkg_name.sh
PKG2ZAP=${THOME}/tribblix-build/pkg2zap

mkdir -p ${DSTDIR}
cd $REPODIR/pkg

for file in *
do
    echo Packaging $file as `$PNAME $file`
    if [ -n "$SIGNCERT" ]; then
	$CMD -T $THOME -V $PKG_VERSION -G $GATEDIR -D $DSTDIR -S $SIGNCERT $file `$PNAME $file`
    else
	$CMD -T $THOME -V $PKG_VERSION -G $GATEDIR -D $DSTDIR $file `$PNAME $file`
    fi
done

#
# convert the SVR4 pkg to zap format
# create an md5 checksum for the catalog
# optionally sign if we have a signing passphrase
#
for file in ${DSTDIR}/pkgs/*.pkg
do
    $PKG2ZAP $file ${DSTDIR}/pkgs
    openssl md5 ${file%.pkg}.zap | /usr/bin/awk '{print $NF}' > ${file%.pkg}.zap.md5
    if [ -f ${HOME}/Tribblix/Sign.phrase ]; then
	echo ""
	echo "Signing package."
	echo ""
	gpg --detach-sign --no-secmem-warning --passphrase-file ${HOME}/Tribblix/Sign.phrase ${file%.pkg}.zap
	if [ -f ${file%.pkg}.zap.sig ]; then
	    echo "Package signed successfully."
	    echo ""
	fi
    fi
done
