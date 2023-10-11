#!/bin/sh
#
# build the gfx-drm packages
#

THOME=${THOME:-/packages/localsrc/Tribblix}

if [ ! -f /opt/onbld/bin/validate_pkg ]; then
    echo "Unable to find validate_pkg"
    echo "Is the illumos-build overlay installed?"
    exit 1
fi
if [ ! -f ${THOME}/tribblix-build/gfx-drm/0001-Fix-manual-for-IPD4.patch ]; then
    echo "Unable to find the required patch"
    echo "Is the tribblix-build repo checked out?"
    exit 1
fi

#
# check out the source
#
if [ -d gfx-drm ]; then
    echo "Existing checkout exists, bailing out"
fi

git clone https://github.com/illumos/gfx-drm
cd gfx-drm
gpatch -p1 < ${THOME}/tribblix-build/gfx-drm/0001-Fix-manual-for-IPD4.patch
gpatch -p1 < ${THOME}/tribblix-build/gfx-drm/sparc-fixes.patch
#
# set the build env
#
sed -i s:DCFlnpr:Cnpr: myenv.sh
echo "export SUPPRESSPKGDEP=true" >> myenv.sh
case $(uname -p) in
    sparc)
	echo "export GNUC_ROOT=/usr/versions/gcc-7" >> myenv.sh
	;;
    *)
	echo "export GNUC_ROOT=/opt/gcc/7.5.0" >> myenv.sh
	;;
esac
#
# need validate_pkg for the packaging to work
#
sed -i s:@validate_pkg:/opt/onbld/bin/validate_pkg: usr/src/pkg/Makefile
#
# scrap the tests
#
rm usr/src/pkg/manifests/system-test-libdrm.mf
sed -i '/drm-tests/d' usr/src/cmd/Makefile
mv usr/src/cmd/drm-tests usr/src/cmd/drm-tests.not
#
# need a newer fetch
# (originally from oi-userland)
#
cp ${THOME}/tribblix-build/gfx-drm/userland-fetch usr/src/tools
sed -i 's:2.7:3:' usr/src/Makefile.master

#
# now for the build
#
/usr/bin/ksh93 tools/bldenv myenv.sh "cd usr/src ; make setup"
/usr/bin/ksh93 tools/bldenv myenv.sh "cd usr/src ; make install"
/usr/bin/ksh93 tools/bldenv myenv.sh "cd usr/src/pkg ; make install"

#
# and package it
#
${THOME}/tribblix-build/gfx-drm/package.sh
