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

for file in /var/tmp/illumos-pkgs/pkgs/*
do
    $PKG2ZAP $file /var/tmp/illumos-pkgs/pkgs
done
