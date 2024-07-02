The patch here aligns gfx-drm with IPD4

git clone https://github.com/illumos/gfx-drm
cd gfx-drm
gpatch -p1 < ${THOME}/tribblix-build/gfx-drm/0001-Fix-manual-for-IPD4.patch

To build and package gfx-drm, simply cd somewhere and run the
gfx-drm.sh script here, and copy the resulting package files (*.zap
and *.zap.md5) into the same place as your illumos packages.

Typical usage of the script is:

${THOME}/tribblix-build/gfx-drm/gfx-drm.sh -D /tmp/gg -V 0.35

where the argument to -D is where you want the zap packages to be placed,
and the argument to -V is the package version you want.

On intel there will be 2 copies of the packages, one for vanilla Tribblix
and one for OmniTribblix. They will be the same packages with the same
content, but the OmniTribblix version will have the OmniTribblix version
string.
