Tribblix Build
==============

These are the scripts to build a Tribblix image. It's assumed that
you've built the gate and created all the SVR4 packages already, see
below.

A lot of the scripts assume you've set a variable THOME to the directory
where all the relevant Tribblix repos are checked out.

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

The ufs_install.sh script is a script that allows install to ufs
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


img_install
===========

The img_install.sh script was designed to install a copy of Tribblix into
a new BE (boot environment) on an existing illumos system. Specifically,
it has been run on the OmniOS EC2 AMI to install Tribblix to a new BE
(using the same image as is used for iPXE boot); rebooting that instance
then boots up into Tribblix, allowing you to delete the OmniOS BE and
create a pure Tribblix AMI.

While it's specific to that particular case, it's really a variant of the
over_install.sh script, and it could easily be modified to do the same trick
with other images. (To see how to unpack some of the other distros, look at
my alien zones brand which knows how to unpack various distros into a zone
filesystem.)


building illumos
================

To build illumos-gate and illumos-omnios, you'll need a zone with
the develop, java, and illumos-build overlays installed.

zap create-zone -z illumos-build -t whole -i 172.xxx.xxx.xxx \
-o develop -O java -O illumos-build -U ptribble

then check out illumos-gate and illumos-omnios, with the following
naming scheme (so they're siblings with similar names)

m28-gate
m28lx-gate

cd /path/to/m28-gate
${THOME}/tribblix-build/illumos/releasebuild m28

cd /path/to/m28lx-gate
${THOME}/tribblix-build/illumos/omnibuild m28lx

The argument to releasebuild and omnibuild is used to pick an
illumos.sh env file (with the given name as the suffix) out of
the illumos directory in this repo.

You'll also need to build and package gfx-drm; see the notes and scripts
in the gfx-drm directory.

ips2svr4
========

Conversion scripts for creating SVR4 packages from an IPS repo created by
an Illumos build.

pkg_name.sh - an ugly way to translate IPS package names to SVR4 names

repo2svr4.sh - script to convert a package from an Illumos build

repo_all.sh - wrapper to create all packages

repo_one.sh - wrapper to create a specific package

These also depend on the tribblix-transforms repo on github, which
applies a number of modifications at the packaging stage (rather than
having to fix the illumos build).

You need a signing certificate. The Tribblix one is created with the
following command:

openssl req -x509 -newkey rsa:2048 -nodes \
-subj "/O=Tribblix/CN=tribblix.org" \
-keyout elfcert.key -out elfcert.crt -days 3650

The certificate (not the key, obviously) needs to end up in the
/etc/crypto/certs directory (with any name) in order for elfsign
to be able to verify signed binaries.

Then, to build packages from a gate build called m28-gate, with package
version 0.28.0, ending up in /var/tmp/m28-pkgs and signed with the above

/path/to/tribblix-build/repo_all.sh \
  -G /path/to/my/builds/m28-gate \
  -V "0.28.0" \
  -D /var/tmp/m28-pkgs \
  -S /path/to/elfcert >& /var/tmp/m28.log


Known issues
============

The scripts have way too many paths hard-coded for my own build server.

Not all package attributes are handled correctly.

Editable files aren't handled as such.
