#!/bin/sh
#
# checks that the environment is suitable for building the gate
#

#
# hold the status here
# we run all checks, so as to report all errors
#
STATUS=0

#
# basic sanity, this will only work on Tribblix
#
if [ ! -d /usr/lib/zap ]; then
    echo "ERROR: is this really Tribblix?"
    STATUS=1
fi

#
# check for installed overlays
# we need develop and illumos-build
# we need java or java11
#
ODIR=/var/sadm/overlays/installed/
if [ ! -f ${ODIR}/develop ]; then
    echo "ERROR: the develop overlay must be installed"
    echo "As root, run the command"
    echo "zap install-overlay develop"
    STATUS=1
fi
if [ ! -f ${ODIR}/illumos-build ]; then
    echo "ERROR: the illumos-build overlay must be installed"
    echo "As root, run the command"
    echo "zap install-overlay illumos-build"
    STATUS=1
fi
if [ ! -f ${ODIR}/java ]; then
    if [ ! -f ${ODIR}/java11 ]; then
	echo "ERROR: the java or java11 overlay must be installed"
	echo "As root, run the command"
	echo "zap install-overlay java11"
	STATUS=1
    fi
fi

#
# /usr/bin/cpp must be deleted
#
if [ -f /usr/bin/cpp ]; then
    echo "ERROR: /usr/bin/cpp should not be present"
    echo "As root, run the command"
    echo "rm -f /usr/bin/cpp"
    STATUS=1
fi

#
# /usr/bin/gxgettext must exist
#
if [ ! -f /usr/bin/gxgettext ]; then
    echo "ERROR: /usr/bin/gxgettext should be present"
    echo "As root, run the command"
    echo "ln -s ../gnu/bin/xgettext /usr/bin/gxgettext"
    STATUS=1
fi

#
# if tests fail, we exit with an error to alert our caller
#

exit $STATUS
