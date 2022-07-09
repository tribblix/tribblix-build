The patch here aligns gfx-drm with IPD4

git clone https://github.com/illumos/gfx-drm
cd gfx-drm
gpatch -p1 < ${THOME}/tribblix-build/gfx-drm/0001-Fix-manual-for-IPD4.patch

To build and package gfx-drm, simply cd somewhere and run the
gfx-drm.sh script here, and copy the resulting package files (*.zap
and *.zap.md5) into the same place as your illumos packages.
