Tribblix Build
==============

These are the scripts to build a Tribblix image. It's assumed that
you've created all the SVR4 packages already.

The first step is to create a distribution area. It's named
/export/tribblix by default, and ought to contain a 'dist' directory
and a 'prebuilt' directory. First run install-pkgs to install the
base. The list of packages in the minimal system is the base-iso
overlay.

You'll need to run mk-pkgs-zap to populate the ISO with the additional
packages referenced in the overlays.

Then just run build_iso to create the iso.

The make-dist script is a simple way to run all the above steps.

The live_install.sh script is what gets put onto the live CD and used
to install Tribblix to a hard disk.

The ufs_install.sh script is a test script that allows install to ufs
instead of zfs.

Once you've booted up the live image successfully, and have the
services running correctly, copy off /etc/svc/repository.db into the
prebuilt directory and you'll avoid manifest import from then
on.

Likewise after a successful install (without overlays) into
repository-installed.db and you'll avoid manifest import at first
boot. The generic_live.xml here is the profile used for the live boot.

If you have a commonly installed overlay then you can install that,
copy off the repository from after the first boot, and put that into
the prebuilt directory named as repository-overlay.db, and update the
installation scripts - I do this by default for the kitchen-sink and
x11 overlays. (For the x11 overlay I enable HAL, and the kitchen-sink
has the SLiM login manager enabled as well.)

ips2svr4
========

Conversion scripts for taking IPS packages (either from an installed
system or from the repo created from an Illumos build) and creating an
equivalent SVR4 package.

pkg_name.sh - an ugly way to translate IPS package names to SVR4 names

ips2svr4.sh - script to convert a package from an installed system

repo2svr4.sh - script to convert a package from an Illumos build

repo_all.sh, mk_all.sh - wrappers to create all packages

These also depend on the tribblix-transforms repo on github, which
applies a number of modifications at the packaging stage (rather than
having to fix the illumos build).

These have my own build locations hardcoded, which will need fixing -
search for "ptribble", "/packages", and "/var/tmp" in the scripts and
put in whatever makes sense for your own system.


Known issues
============

The scripts have way too many paths hard-coded for my own build server.

Not all package attributes are handled correctly.

Editable files aren't handled as such.
