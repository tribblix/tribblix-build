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
