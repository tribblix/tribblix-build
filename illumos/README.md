Illumos build files
===================

These are the files necessary to build illumos on Tribblix.

The illumos.sh-XXX files are the illumos.sh for version XXX of Tribblix

The changes for Tribblix are at the bottom, and are largely about what
version of python/perl/java comes with Tribblix and where it's installed.
From release to release, normally only the VERSION string would change.

You'll also need to replace usr/src/cmd/auditrecord/Makefile with the
Makefile.auditrecord file from here, again because perl on Tribblix is
slightly different.

There are 2 patches for Tribblix:

0003-5709-Add-binary-compatibility-with-Solaris-10-update.patch
is what it says, and is pretty much a definite commitment

0001-add-zone-brand.patch
is similar to the openindiana patch, but adds my brands not theirs
this one is more experimental

Both are against illumos-gate. The S10 compatibility isn't needed for
omnitribblix, as illumos-omnios already includes that fix. The zone brand
patch won't apply on illumos-omnios, so I just copy a patched
usr/src/lib/libbe/common/libbe_priv.h from my illumos-gate into the
omnitribblix build.
