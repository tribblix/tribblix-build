#!/bin/ksh
#
# generate all packages, from an installed system
#
# these ought to be args, but must match ips2svr4.sh
#

CMD=/home/ptribble/Tribblix/ips2svr4.sh
PNAME=/home/ptribble/Tribblix/pkg_name.sh

cd /var/pkg/publisher/openindiana.org/pkg

for file in *
do
    echo $CMD $file `$PNAME $file`
    $CMD $file `$PNAME $file`
done
