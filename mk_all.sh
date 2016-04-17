#!/bin/ksh
#
# generate all packages, from an installed system
#
# these ought to be args, but must match ips2svr4.sh
#
THOME=/packages/localsrc/Tribblix

CMD=${THOME}/tribblix-build/ips2svr4.sh
PNAME=${THOME}/tribblix-build/pkg_name.sh
PKG2ZAP=${THOME}/tribblix-build/pkg2zap

cd /var/pkg/publisher/openindiana.org/pkg

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
for file in /var/tmp/created-pkgs/pkgs/*.pkg
do
    $PKG2ZAP $file /var/tmp/created-pkgs/pkgs
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
