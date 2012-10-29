<<<<<<< HEAD
Tribblix Build
==============

These are the scripts to build a Tribblix image. It's assumed that
you've created all the SVR4 packages already.

The first step is to create a distribution area and run install-pkgs
to install the base. The list of packages in the minimal system is in
the pkg-list file. Installation is interactive (and you can see that
the created packages have one or two minor errors).

The area you drop the build into ought to contain a 'dist' directory, a
'save' directory, and a 'prebuilt' directory.

Once you've booted up the live image successfully, and have the
services running correctly, copy off /etc/svc/repository.db into the
prebuilt directory and you'll avoid manifest import from then
on. Likewise after a successful install (without overlays) into
repository-installed.db and you'll avoid manifest import at first
boot. The generic_live.xml here is the profile used for the live boot.

You'll need to create pkgs.zlib and put it int the root of the dist
area. The mk-pkgs-zlib script here will create one based on the
overlays it finds.

Then just run build_iso to create the iso.

The live_install.sh script is what gets put onto the live CD and used
to install Tribblix to a hard disk.
=======
ips2svr4
========

Conversion scripts for taking IPS packages (either from an installed
system or from the repo created from an Illumos build) and creating an
equivalent SCR4 package.

pkg_name.sh - an ugly way to translate IPS package names to SVR4 names

ips2svr4.sh - script to convert a package from an installed system
repo2svr4.sh - script to convert a package from an Illumos build

repo_all.sh, mk_all.sh - wrappers to create all packages

Thes have my own build locations hardcoded, which will need fixing -
search for "ptribble" and "/var/tmp" in the scripts and put in whatever
makes sense for your own system
>>>>>>> ead55b0b1690807527a525198d153d7ebd2d25f9

Known issues
============

<<<<<<< HEAD
The scripts have way too many paths hard-coded for my own build server.
=======
Not all package attributes are handled correctly.

Editable files aren't handled as such.
>>>>>>> ead55b0b1690807527a525198d153d7ebd2d25f9
