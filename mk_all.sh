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


for file in /var/tmp/created-pkgs/pkgs/*
do
    $PKG2ZAP $file /var/tmp/created-pkgs/pkgs
done
