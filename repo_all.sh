#!/bin/ksh
#
# generate all packages, in both datastream and zap formats, from
# an illumos build
#
# these ought to be args, but must match repo2svr4.sh
#
THOME=/packages/localsrc/Tribblix
GATEDIR=/export/home/ptribble/Illumos/illumos-gate

REPODIR=${GATEDIR}/packages/`uname -p`/nightly-nd/repo.redist

CMD=${THOME}/tribblix-build/repo2svr4.sh
PNAME=${THOME}/tribblix-build/pkg_name.sh
PKG2ZAP=${THOME}/tribblix-build/pkg2zap

cd $REPODIR/pkg

for file in *
do
    echo $CMD $file `$PNAME $file`
    $CMD $file `$PNAME $file`
done

#
# convert the SVR4 pkg to zap format
# create an md5 checksum for the catalog
# optionally sign if we have a signing passphrase
#
for file in /var/tmp/illumos-pkgs/pkgs/*.pkg
do
    $PKG2ZAP $file /var/tmp/illumos-pkgs/pkgs
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
