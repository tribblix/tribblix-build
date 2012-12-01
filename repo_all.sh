#!/bin/ksh
#
# generate all packages, from an illumos build
#
# these ought to be args, but must match repo2svr4.sh
#
REPODIR=/home/ptribble/Illumos/illumos-gate/packages/i386/nightly-nd/repo.redist

CMD=/home/ptribble/Tribblix/repo2svr4.sh
PNAME=/home/ptribble/Tribblix/pkg_name.sh

cd $REPODIR/pkg

for file in *
do
    echo $CMD $file `$PNAME $file`
    $CMD $file `$PNAME $file`
done
