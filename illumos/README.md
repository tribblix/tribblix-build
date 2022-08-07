Illumos build files
===================

These are the files necessary to build illumos on Tribblix.

The illumos.sh.XXX files are the illumos.sh for version XXX of Tribblix

The changes for Tribblix are largely about what version of python/perl/java
comes with Tribblix and where it's installed.  From release to release,
normally only the VERSION string would change.

You'll also need to replace usr/src/cmd/auditrecord/Makefile with the
Makefile.auditrecord file from here, again because perl on Tribblix is
slightly different.

It's best to use the releasebuild, omnibuild, and debugbuild scripts, as
they largely automate all the build tasks for you, and attempt to protect
you from common mistakes.


There are some patches for Tribblix:

0001-add-zone-brand.patch
is similar to the openindiana patch, but adds my brands not theirs
this one is more experimental (this is a case where all the distros
have different needs so this file can't be the same for all distros)

mdb-makefile.patch
mdb-packaging.patch
These fix up the fact that the gate assumes a python different from that
now shipped by Tribblix, so the python dmod no longer builds. As a
workaround, turn off the build of that component entirely.

The zone brand patch won't apply on illumos-omnios, so I just copy a patched
usr/src/lib/libbe/common/libbe_priv.h from my illumos-gate into the
omnitribblix build.

GFX-DRM

The gfx-drm pieces now live in a separate github repo. These need to be
built separately and then combined with the bits you created from the
gate builds. See gfx-drm.txt for details.


Patches no longer required:

0003-5709-Add-binary-compatibility-with-Solaris-10-update.patch
has been integrated into the gate.
