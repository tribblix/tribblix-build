#!/bin/ksh
#
# SPDX-License-Identifier: CDDL-1.0
#
# {{{ CDDL HEADER
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source. A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#
# }}}
#
# Copyright 2024 Peter Tribble
#

#
# convert an ips package to svr4, from an on-disk repo
#

PKG_VERSION="0.35"
THOME=${THOME:-/packages/localsrc/Tribblix}
GATEDIR=/export/home/ptribble/Illumos/illumos-gate
DSTDIR=/var/tmp/illumos-pkgs
SIGNCERT=""
MYREPO="redist"
QUICKMODE=""
ARCH32=$(uname -p)

#
# find_elf can't find the right elfedit
#
export PATH=/usr/bin:/usr/sbin:/sbin:/usr/gnu/bin

#
# packages should have consistent times
#
TZ=UTC
export TZ

#
# locations and variables should be passed as arguments
#
while getopts "QV:T:G:D:R:S:" opt; do
    case $opt in
        Q)
	    QUICKMODE="Y"
	    ;;
        V)
	    PKG_VERSION="$OPTARG"
	    ;;
        T)
	    THOME="$OPTARG"
	    ;;
        G)
	    GATEDIR="$OPTARG"
	    ;;
        D)
	    DSTDIR="$OPTARG"
	    ;;
        R)
	    MYREPO="$OPTARG"
	    ;;
        S)
	    SIGNCERT="$OPTARG"
	    ;;
    esac
done
shift $((OPTIND-1))

#
# verify signing - the cert and key must exist
# if they don't, exit early
#
FINDELF=${GATEDIR}/usr/src/tools/scripts/find_elf
if [ -n "$SIGNCERT" ]; then
    if [ -r "${SIGNCERT}.key" -a -r "${SIGNCERT}.crt" ]; then
	:
    else
	echo "Error: invalid cert specified"
	exit 1
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="${GATEDIR}/usr/src/tools/find_elf/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="/opt/onbld/bin/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	FINDELF="/opt/onbld/bin/${ARCH32}/find_elf"
    fi
    if [ ! -x "${FINDELF}" ]; then
	echo "Cannot sign, find_elf missing"
	exit 1
    fi
    if [ ! -x /usr/bin/elfsign ]; then
	echo "Cannot sign, elfsign missing"
	echo "  (is TRIBdev-linker installed?)"
	exit 1
    fi
fi

#
# high level strategy:
#
# 1. create a new temporary directory
# 2. parse manifests to build an svr4 proto area
# 3. create the svr4 package
#
# conversion strategy:
#
# 1. construct arch variant list
# 2. create a new directory for each architecture (or common if no arch)
# 3. Copy all relevant files into target directory hierarchy, using
#    manifest to map pathnames and build the prototype file as we go
# 4. create a pkginfo file from manifest or manifest.legacy (if it exists)
# 5. Create install/depend from depend actions in the manifest,
#    ignoring incorporations
# 7. run pkgmk
#

#
# weaknesses of the current implementation
# 1. no attempt at architecture variants
# 2. fixed paths
# 3. need to fully handle set actions
# 4. need to fully handle driver actions
# 5. handle reboot-needed
# 6. Need to handle global/ngz
#

#
# Global variables
#
PKGDIR=/usr/bin
PKGMK="${PKGDIR}/pkgmk"
PKGTRANS="${PKGDIR}/pkgtrans"
PNAME=${THOME}/tribblix-build/pkg_name.sh
TRANSDIR=${THOME}/tribblix-transforms

#
# used for noisaexec
#
case $ARCH32 in
sparc)
  ARCH64="sparcv9"
  ;;
i386)
  ARCH64="amd64"
  ;;
esac

#
# global flags
#
# contains a legacy action
HAS_LEGACY=false
# contains any content
HAS_CONTENT=false
# is marked as renamed or obsolete
IS_GARBAGE=false

usage() {
    echo "Usage: $0 input_pkg output_pkg"
    exit 1
}

bail_out() {
    rm -fr "$BDIR" "$DSTDIR/tmp/${OUTPKG}"
    exit 0
}

#
# some drivers (ata is the only example I know of) claim more than 1 class
# I can't find a way for add_drv to cope with this, so resort to
# fiddling /etc/driver_classes by hand
#
# I assume that init_driver has been called already
#
# first argument is the driver, 2nd the class
#
add_driver_class() {
NDRIVER=$1
NCLASS=$2
cat >>"${BDIR}/install/postinstall" <<EOF
echo "$NDRIVER\t$NCLASS" >> \${BASEDIR}/etc/driver_classes
EOF
cat >>"${BDIR}/install/postremove" <<EOF
cat \${BASEDIR}/etc/driver_classes | /bin/sed '/^${NDRIVER}.*${NCLASS}/d' > /tmp/adc.\$\$
cp /tmp/adc.\$\$ \${BASEDIR}/etc/driver_classes
rm /tmp/adc.\$\$
EOF
}

#
# initialize driver handling by creating the postinstall and postremove
# scripts
#
init_driver() {
mkdir -p "${BDIR}/install"
if [ ! -f "${BDIR}/install/postinstall" ]; then
cat > "${BDIR}/install/postinstall" <<EOF
#!/sbin/sh
#
# SPDX-License-Identifier: CDDL-1.0
#
# Automatically generated driver install script
#
CMD=/usr/sbin/add_drv
if [ "\${BASEDIR}" = "/" ]; then
    BFLAGS=""
else
    BFLAGS="-b \${BASEDIR}"
fi
EOF
cat > "${BDIR}/install/postremove" <<EOF
#!/sbin/sh
#
# SPDX-License-Identifier: CDDL-1.0
#
# Automatically generated driver remove script
#
CMD=/usr/sbin/rem_drv
if [ "\${BASEDIR}" = "/" ]; then
    BFLAGS=""
else
    BFLAGS="-b \${BASEDIR}"
fi
EOF
echo "i postinstall=./install/postinstall" >> "${BDIR}/prototype"
echo "i postremove=./install/postremove" >> "${BDIR}/prototype"
fi
}

#
# class action scripts
#
init_preserve() {
mkdir -p "${BDIR}/install"
if [ ! -f "${BDIR}/install/i.preserve" ]; then
cat > "${BDIR}/install/i.preserve" <<EOF
#!/bin/sh
#
# SPDX-License-Identifier: CDDL-1.0
#
# simplistic class-action script for preserve
# copies the new file iff it doesn't already exist
#
while read src dest
do
  if [ ! -f \$dest ] ; then
    cp \$src \$dest
  fi
done
exit 0
EOF
chmod 555 "${BDIR}/install/i.preserve"
echo "i i.preserve=./install/i.preserve" >> "${BDIR}/prototype"
fi
if [ ! -f "${BDIR}/install/r.preserve" ]; then
cat > "${BDIR}/install/r.preserve" <<EOF
#!/bin/sh
#
# SPDX-License-Identifier: CDDL-1.0
#
# class-action script for preserve
# retains the old file if it's been modified
#
while read dest
do
    # need to strip off the alternate root
    ndest=\${dest/\${PKG_INSTALL_ROOT}/}
    if [ -f "\${PKG_INSTALL_ROOT}/var/sadm/pkg/\${PKGINST}/save/pspool/\${PKGINST}/reloc/\${ndest}" ]; then
        if /usr/bin/cmp -s "\${PKG_INSTALL_ROOT}/var/sadm/pkg/\${PKGINST}/save/pspool/\${PKGINST}/reloc/\${ndest}" "\${dest}"
        then
	    /usr/bin/rm -f \$dest
	else
	    echo Retaining modified \$dest
	fi
    fi
done
exit 0
EOF
chmod 555 "${BDIR}/install/r.preserve"
echo "i r.preserve=./install/r.preserve" >> "${BDIR}/prototype"
fi
}

#
# initialise dependency handling
#
init_depend() {
mkdir -p "${BDIR}/install"
if [ ! -f "${BDIR}/install/depend" ]; then
cat > "${BDIR}/install/depend" <<EOF
# The following dependencies are automatically generated
# from the IPS manifest for this package, with automatic
# generation of SVR4 package names.
#
# No version information is preserved
#
EOF
echo "i depend=./install/depend" >> "${BDIR}/prototype"
fi
}

#
# if there are services that should be restarted, add them to the postinstall
# script
#
handle_restarts() {
if [ -f "${BDIR}/restart_fmri_list" ]; then
mkdir -p "${BDIR}/install"
if [ ! -f "${BDIR}/install/postinstall" ]; then
cat > "${BDIR}/install/postinstall" <<EOF
#!/sbin/sh
#
# SPDX-License-Identifier: CDDL-1.0
#
# Automatically generated service restart script
#
EOF
cat > "${BDIR}/install/postremove" <<EOF
#!/sbin/sh
#
# SPDX-License-Identifier: CDDL-1.0
#
# Automatically generated service restart script
#
EOF
echo "i postinstall=./install/postinstall" >> "${BDIR}/prototype"
echo "i postremove=./install/postremove" >> "${BDIR}/prototype"
fi
#
# this check is so we only actually restart if the install is to the
# current system. If we're installing to an alternate image, then the
# restarts will happen automatically when it boots
#
# FIXME should the restart be -s
#
cat >> "${BDIR}/install/postinstall" <<EOF
if [ "\${BASEDIR}" = "/" ]; then
EOF
cat >> "${BDIR}/install/postremove" <<EOF
if [ "\${BASEDIR}" = "/" ]; then
EOF
sort -u "${BDIR}/restart_fmri_list" | /usr/bin/awk '{print "/usr/sbin/svcadm restart "$1}' >> "${BDIR}/install/postinstall"
sort -u "${BDIR}/restart_fmri_list" | /usr/bin/awk '{print "/usr/sbin/svcadm restart "$1}' >> "${BDIR}/install/postremove"
echo "fi" >> "${BDIR}/install/postinstall"
echo "fi" >> "${BDIR}/install/postremove"
/usr/bin/rm "${BDIR}/restart_fmri_list"
fi
}

#
# parse a driver line in the manifest
# should have name, maybe alias and perms
# FIXME policy privilege
# FIXME aliases perms etc should be emitted with single quotes
#
handle_driver() {
HAS_CONTENT=true
init_driver
CMD_FRAG='${CMD} ${BFLAGS}'
UCMD_FRAG='/usr/sbin/update_drv ${BFLAGS}'
DNAME=""
PERMS=""
POLICY=""
CLONEPERMS=""
ALIASES=""
CLASS=""
EXTRA_CLASSES=""
for frag in "$@"
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
name)
    DNAME="$value"
    ;;
perms)
    if [ "x${PERMS}" = "x" ]; then
	PERMS="-m '$value'"
    else
	PERMS="${PERMS},""'$value'"
    fi
    ;;
policy)
    #
    # there should only be one policy, and it's the whole string
    #
    POLICY="-p '$nval'"
    ;;
alias)
    if [ "x${ALIASES}" = "x" ]; then
	ALIASES="-i '"'"'$value'"'
    else
	ALIASES="${ALIASES} "'"'$value'"'
    fi
    ;;
class)
    if [ "x${CLASS}" = "x" ]; then
	CLASS="-c $value"
    else
	EXTRA_CLASSES="${EXTRA_CLASSES} $value"
    fi
    ;;
*zone*)
    :
    ;;
clone_perms)
    CLONEPERMS="'$value'"
    ;;
*)
    echo "unhandled driver action $frag"
    ;;
esac
done
#
# add any extra driver classes
#
for NCLASS in $EXTRA_CLASSES
do
    add_driver_class $DNAME $NCLASS
done
#
# ddi_pseudo confuses the parser, override where it breaks
#
if [ "x${INPKG}" = "xdriver%2Fx11%2Fxsvc" ]; then
    DNAME="xsvc"
fi
if [ "x${INPKG}" = "xdriver%2Fstorage%2Fcpqary3" ]; then
    DNAME="cpqary3"
fi
if [ "x${INPKG}" = "xdriver%2Fcrypto%2Ftpm" ]; then
    DNAME="tpm"
    PERMS="-m '* 0600 root sys'"
fi
if [ "x${ALIASES}" != "x" ]; then
    ALIASES="${ALIASES}'"
fi
if [ "x${DNAME}" != "x" ]; then
    echo "${CMD_FRAG} ${PERMS} ${POLICY} ${ALIASES} ${CLASS} $DNAME" >> "${BDIR}/install/postinstall"
    echo "${CMD_FRAG} $DNAME" >> "${BDIR}/install/postremove"
fi
if [ "x${CLONEPERMS}" != "x" ]; then
    echo "${UCMD_FRAG} -a -m ${CLONEPERMS} clone" >> "${BDIR}/install/postinstall"
fi
}

#
# parse a directory line in the manifest
# should have group, owner, mode, and path
#
handle_dir() {
HAS_CONTENT=true
for frag in $*
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
*zone*)
    # FIXME zone handling
    :
    ;;
path)
    dirpath=$value
    ;;
mode)
    mode=$value
    ;;
owner)
    owner=$value
    ;;
group)
    group=$value
    ;;
facet*)
    :
    ;;
*)
    echo "unhandled dir attributes $frag"
    ;;
esac
done
mkdir -p -m "$mode" "${BDIR}/${dirpath}"
echo "d none ${dirpath} ${mode} ${owner} ${group}" >> "${BDIR}/prototype"
}

#
# parse a link line in the manifest
# should have path and target
# skip reboot-needed; handle it with the target file
#
handle_link() {
HAS_CONTENT=true
for frag in $*
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
*zone*|reboot-needed)
    # FIXME zone handling
    :
    ;;
path)
    dirpath=$value
    ;;
target)
    target=$value
    ;;
facet*)
    :
    ;;
restart_fmri)
    :
    ;;
*)
    echo "unhandled link attribute $frag"
    ;;
esac
done
echo "s none ${dirpath}=${target}" >> "${BDIR}/prototype"
# create the symlink so that rrmdir works
# the directory containing the symlink must exist
tdir=${dirpath%/*}
if [ ! -d "${BDIR}/${tdir}" ]; then
    mkdir -p "${BDIR}/${tdir}"
fi
ln -s "${target}" "${BDIR}/${dirpath}"
}

#
# parse a hardlink line in the manifest
# should have path and target
#
handle_hardlink() {
HAS_CONTENT=true
for frag in $*
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
*zone*)
    # FIXME zone handling
    :
    ;;
path)
    dirpath=$value
    ;;
target)
    target=$value
    ;;
*)
    echo "unhandled hardlink attribute $frag"
    ;;
esac
done
case ${target} in
*~*)
    echo "WARNING: skipping link to $target"
    ;;
*)
    echo "l none ${dirpath}=${target}" >> "${BDIR}/prototype"
    ;;
esac
}

#
# parse a file line in the manifest
# should have group, owner, mode, and path like a directory
# plus some metadata
# ignore the pkg.size and pkg.csize attributes we don't use them anyway
# ignore chash and elfhash, as we don't use them either
#
# cp -p retains the timestamp; this allows repeated invocations of this
# script to generate identical packages, but if the timestamp is set in
# the manifest we explicitly touch the file to that date
#
handle_file() {
HAS_CONTENT=true
FTYPE="f"
FCLASS="none"
TSTAMP=""
echo $* | read fhash line
fh=`echo $fhash| cut -c1-2`
# file in the repo is ${REPODIR}/file/${fh}/${fhash}
for frag in $line
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
pkg.size*|pkg.csize*|reboot-needed|*zone*|elfarch|elfbits|chash|elfhash|original_name)
    # FIXME reboot, zone handling
    # FIXME should check on elfarch
    :
    ;;
path)
    filepath=$value
    ;;
mode)
    mode=$value
    ;;
owner)
    owner=$value
    ;;
group)
    group=$value
    ;;
timestamp)
    # timestamp=19700101T000000Z
    # touch argument is of the form [[CC]YY]MMDDhhmm[.SS]
    TSTAMP=`echo $value | /usr/bin/awk -FT '{printf("%s%.4s",$1,$2)}'`
    ;;
facet*)
    :
    ;;
pkg.content-hash)
    :
    ;;
restart_fmri)
    touch "${BDIR}/restart_fmri_list"
    echo $value >>"${BDIR}/restart_fmri_list"
    ;;
preserve)
    FTYPE="e"
    FCLASS="preserve"
    init_preserve
    ;;
*)
    echo "unhandled file attribute $frag"
    ;;
esac
done
dpath=`dirname $filepath`
if [ ! -d "${BDIR}/${dpath}" ]; then
    mkdir -p "${BDIR}/${dpath}"
fi
if [ -f "${BDIR}/${filepath}" ]; then
    echo "DBG: parsing $hash $line"
    echo "WARN: path $filepath already exists in $dpath"
fi
/usr/bin/cp -p "${REPODIR}/file/${fh}/${fhash}" "${BDIR}/${filepath}.gz"
/usr/bin/gunzip "${BDIR}/${filepath}.gz"
/usr/bin/chmod "$mode" "${BDIR}/${filepath}"
if [ "xx${TSTAMP}" != "xx" ]; then
    /bin/touch -t "${TSTAMP}" "${BDIR}/${filepath}"
fi
case ${filepath} in
*~*)
    echo "WARNING: skipping file path $filepath"
    ;;
*)
    echo "${FTYPE} ${FCLASS} ${filepath}=${filepath} ${mode} ${owner} ${group}" >> "${BDIR}/prototype"
    ;;
esac
}

#
# parse a license line in the manifest
#
# all license files get placed under /var/sadm/license in a directory
# named after the package, in parallel with the /var/sadm/pkg hierarchy
#
handle_license() {
dirmode="0755"
mode="0644"
owner="root"
group="sys"
echo $* | read fhash line
fh=`echo $fhash| cut -c1-2`
# file in the repo is ${REPODIR}/file/${fh}/${fhash}
for frag in $line
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
license)
    licpath=$value
    ;;
*)
    :
    ;;
esac
done
if [ -n "$licpath" ]; then
    dirpath="var/sadm/license/${PKG}"
    if [ ! -d "${BDIR}/${dirpath}" ]; then
	mkdir -p "${BDIR}/${dirpath}"
    fi
    echo "d none ${dirpath} ${dirmode} ${owner} ${group}" >> "${BDIR}/prototype"
    case $licpath in
	*/*)
	    licfname=${licpath##*/}
	    ;;
	cr_*)
	    licfname=${licpath/cr_/COPYRIGHT.}
	    ;;
	lic_*)
	    :
	    licfname=${licpath/lic_/LICENSE.}
	    ;;
	license_in_headers)
	    licfname="SEE_HEADERS.txt"
	    ;;
    esac
    #
    # if the candidate name already exists, try adding a suffix
    #
    if [ -f "${BDIR}/${dirpath}/${licfname}" ]; then
	NLIC=1
	while [ -f "${BDIR}/${dirpath}/${licfname}.${NLIC}" ]
	do
	    NLIC=$((NLIC+1))
	done
	licfname="${licfname}.${NLIC}"
    fi
    filepath="${dirpath}/${licfname}"
/usr/bin/cp -p "${REPODIR}/file/${fh}/${fhash}" "${BDIR}/${filepath}.gz"
/usr/bin/gunzip "${BDIR}/${filepath}.gz"
/usr/bin/chmod "$mode" "${BDIR}/${filepath}"
    echo "f none ${filepath}=${filepath} ${mode} ${owner} ${group}" >> "${BDIR}/prototype"
fi
}

#
# parse a legacy line in the manifest
#
# This doesn't always work, as the legacy action maps to the SVR4 emulation
# layer. So there could be multiple legacy actions, in the case of merged
# packages, or none at all.
#
# none at all is bad, as that causes an incomplete pkginfo file which causes
# package generation to fail
#
handle_legacy() {
HAS_LEGACY=true
for frag in "$*"
do
    eval "$frag"
done
NAME=`echo $name| sed -e 's:, (Root)::' -e 's: (Root)::' -e 's:, (Usr)::' -e 's: (Usr)::' -e 's: (root)::'`
VERSION="$PKG_VERSION"
IPS_VERSION="$version"
ARCH="$arch"
CATEGORY="$category"
VENDOR="$vendor"
BASEDIR="/"
PKG="$OUTPKG"
DESC="$desc"
# FIXME why null?
# the problem appears to be if a legacy line includes a facet
if [ "x$IPS_VERSION" = "x" ]; then
  IPS_VERSION="1.0"
fi
# CLASSES automatically set by pkgmk
echo "PKG=\"${PKG}\"" >> "${BDIR}/pkginfo"
echo "NAME=\"${NAME}\"" >> "${BDIR}/pkginfo"
echo "ARCH=\"${ARCH}\"" >> "${BDIR}/pkginfo"
echo "VERSION=\"${VERSION}\"" >> "${BDIR}/pkginfo"
echo "IPS_VERSION=\"${IPS_VERSION}\"" >> "${BDIR}/pkginfo"
echo "CATEGORY=\"${CATEGORY}\"" >> "${BDIR}/pkginfo"
echo "VENDOR=\"${VENDOR}\"" >> "${BDIR}/pkginfo"
echo "BASEDIR=\"${BASEDIR}\"" >> "${BDIR}/pkginfo"
echo "PSTAMP=\"tribblix\"" >> "${BDIR}/pkginfo"
}

emulate_legacy() {
HAS_LEGACY=true
NAME="$OUTPKG"
VERSION="$PKG_VERSION"
ARCH="$ARCH32"
CATEGORY="application"
VENDOR="Tribblix"
BASEDIR="/"
PKG="$OUTPKG"
# FIXME should be pkg.summary
DESC="$OUTPKG"
# CLASSES automatically set by pkgmk
echo "PKG=\"${PKG}\"" >> "${BDIR}/pkginfo"
echo "NAME=\"${NAME}\"" >> "${BDIR}/pkginfo"
echo "ARCH=\"${ARCH}\"" >> "${BDIR}/pkginfo"
echo "VERSION=\"${VERSION}\"" >> "${BDIR}/pkginfo"
echo "CATEGORY=\"${CATEGORY}\"" >> "${BDIR}/pkginfo"
echo "VENDOR=\"${VENDOR}\"" >> "${BDIR}/pkginfo"
echo "BASEDIR=\"${BASEDIR}\"" >> "${BDIR}/pkginfo"
echo "PSTAMP=\"tribblix\"" >> "${BDIR}/pkginfo"
}

#
# parse set directives
#
handle_set() {
for frag in "$*"
do
    eval "$frag"
done
case $name in
'pkg.renamed')
  IS_GARBAGE=true
  ;;
'pkg.obsolete')
  IS_GARBAGE=true
  ;;
'pkg.description')
  echo "IPS_DESCRIPTION=$value" >> "${BDIR}/pkginfo"
  ;;
'pkg.summary')
  echo "IPS_SUMMARY=$value" >> "${BDIR}/pkginfo"
  ;;
'pkg.fmri')
  echo "IPS_FMRI=$value" >> "${BDIR}/pkginfo"
  ;;
'info.classification')
  echo "IPS_CLASSIFICATION=$value" >> "${BDIR}/pkginfo"
  ;;
'org.opensolaris.consolidation')
  echo "IPS_CONSOLIDATION=$value" >> "${BDIR}/pkginfo"
  ;;
'variant.arch'|'variant.opensolaris.zone'|'opensolaris.smf.fmri'|'org.opensolaris.smf.fmri'|'opensolaris.arc_url')
  :
  ;;
'info.repository_changeset'|'info.maintainer_url'|'info.repository_url'|'info.defect_tracker.url'|'info.source_url'|'info.upstream_url'|'info.upstream')
  :
  ;;
*)
  echo "Unhandled set directive $name"
  ;;
esac
}

#
# handle dependencies. we only accept pkg fmris, ignore consolidations
# we could put the version information in, but need to decide if and how
# to use it before doing so
#
# if we hit an incorporate dependency then this is an incorporation
# and we simply bail
#
handle_depend() {
for frag in "$*"
do
    eval "$frag"
done
case $type in
'incorporate')
  echo "Looks like an incorporation, bailing out"
  bail_out
  ;;
'require')
  case $fmri in
pkg*)
    pkg_str=`echo $fmri | sed 's=^pkg:/=='`
    pkg_name=`echo $pkg_str | awk -F@ '{print $1}'`
    pkg_vers=`echo $pkg_str | awk -F@ '{print $2}'`
case $pkg_name in
*incorporation)
    :
    ;;
*)
    svr4_name=`$PNAME $pkg_name`
    init_depend
    echo "P $svr4_name" >> "${BDIR}/install/depend"
    ;;
esac
    ;;
*consolidation*)
    :
    ;;
*)
    svr4_name=`$PNAME $fmri`
    init_depend
    echo "P $svr4_name" >> "${BDIR}/install/depend"
    ;;
esac
    ;;
*)
  echo "Unhandled dependency type $type"
  ;;
esac
}

#
# transform to replace a pathname in this package
#
# we look for an architecture-specific and a generic replacement
# in the transforms hierarchy
#
transform_replace() {
filepath=$1
if [ -f "${BDIR}/${filepath}" ]; then
  if [ -f "${TRANSDIR}/$filepath.${ARCH32}" ]; then
    cp "${TRANSDIR}/$filepath.${ARCH32}" "${BDIR}/${filepath}"
  elif [ -f "${TRANSDIR}/$filepath" ]; then
    cp "${TRANSDIR}/$filepath" "${BDIR}/${filepath}"
  else
    echo "WARN: transform_replace cannot find replacement for ${filepath}"
  fi
else
  echo "WARN: transform_replace cannot find path ${filepath}"
fi
}

#
# transform to add a dependency
#
transform_depend() {
pkgdep=$1
init_depend
echo "P ${pkgdep}" >> "${BDIR}/install/depend"
}

#
# transform to remove a dependency
#
transform_undepend() {
pkgdep=$1
if [ -f "${BDIR}/install/depend" ]; then
    mv "${BDIR}/install/depend" "${BDIR}/install/depend.transform"
    cat "${BDIR}/install/depend.transform" | egrep -v "P ${pkgdep}\$" > "${BDIR}/install/depend"
    rm "${BDIR}/install/depend.transform"
fi
}

#
# transform to delete a pathname from this package
#
# we need to remove the file from our temporary area and from
# the prototype file
#
transform_delete() {
filepath=$1
if [ -f "${BDIR}/${filepath}" ]; then
  /usr/bin/rm -f "${BDIR}/${filepath}"
else
  echo "WARN: transform_delete cannot find path ${filepath}"
fi
/usr/bin/mv "${BDIR}/prototype" "${BDIR}/prototype.transform"
cat "${BDIR}/prototype.transform" | grep -v " ${filepath}=${filepath} " > "${BDIR}/prototype"
/usr/bin/rm "${BDIR}/prototype.transform"
}

#
# transform to change the ftype of a pathname from this package
# need to have the class set to match
#
transform_type() {
filepath=$1
newtype=$2
if [ -f "${BDIR}/${filepath}" ]; then
  /usr/bin/mv "${BDIR}/prototype" "${BDIR}/prototype.transform"
  cat "${BDIR}/prototype.transform" | grep " ${filepath}=${filepath} " | read otype oclass opath operm ouser ogroup
  cat "${BDIR}/prototype.transform" | grep -v " ${filepath}=${filepath} " > "${BDIR}/prototype"
  case $newtype in
      e)
	  oclass="preserve"
	  ;;
      *)
	  oclass="none"
	  ;;
  esac
  echo "${newtype} ${oclass} ${opath} ${operm} ${ouser} ${ogroup}" >> "${BDIR}/prototype"
  /usr/bin/rm "${BDIR}/prototype.transform"
else
  echo "WARN: transform_type cannot find $filepath"
fi
}

#
# transform to rename a pathname in this package
#
transform_rename() {
filepath=$1
newpath=$2
newdir=`dirname $newpath`
echo "DBG: rename $filepath to $newpath in $newdir"
if [ -f "${BDIR}/${filepath}" ]; then
  /usr/bin/mkdir -p "${BDIR}/${newdir}"
  /usr/bin/mv "${BDIR}/${filepath}" "${BDIR}/${newpath}"
  /usr/bin/mv "${BDIR}/prototype" "${BDIR}/prototype.transform"
  cat "${BDIR}/prototype.transform" | grep " ${filepath}=${filepath} " | read otype oclass opath operm ouser ogroup
  cat "${BDIR}/prototype.transform" | grep -v " ${filepath}=${filepath} " > ${BDIR}/prototype
  echo "${otype} ${oclass} ${newpath}=${newpath} ${operm} ${ouser} ${ogroup}" >> ${BDIR}/prototype
  /usr/bin/rm "${BDIR}/prototype.transform"
else
  echo "WARN: transform_rename cannot find $filepath"
fi
}

#
# transform to delete a linked pathname from this package
#
# we need to remove the file from the prototype file
#
transform_linkdel() {
filepath=$1
/usr/bin/mv "${BDIR}/prototype" "${BDIR}/prototype.transform"
cat "${BDIR}/prototype.transform" | grep -v " ${filepath}=" > "${BDIR}/prototype"
/usr/bin/rm "${BDIR}/prototype.transform"
# delete the symlink so that the directory is empty for rmdir and rrmdir
if [ -h "${BDIR}/${filepath}" ]; then
    /usr/bin/rm -f "${BDIR}/${filepath}"
fi
}

#
# transform to delete a directory pathname from this package
#
# we need to remove the directory from our temporary area and from
# the prototype file
#
transform_rmdir() {
filepath=$1
if [ -d "${BDIR}/${filepath}" ]; then
  /usr/bin/rmdir "${BDIR}/${filepath}"
else
  echo "WARN: transform_rmdir cannot find directory ${filepath}"
fi
if [ -d "${BDIR}/${filepath}" ]; then
  echo "WARN: transform_rmdir cannot remove directory ${filepath}"
fi
/usr/bin/mv "${BDIR}/prototype" "${BDIR}/prototype.transform"
cat "${BDIR}/prototype.transform" | egrep -v " none ${filepath} " > "${BDIR}/prototype"
/usr/bin/rm "${BDIR}/prototype.transform"
}

#
# transform to recursively delete a directory and everything under it
#
# we do nothing here, but transform all the links, files, and directories
# that we find
#
# does not understand hard links, you will need to explicitly transform
# those away first
#
transform_rrmdir() {
rfilepath=$1
if [ -d "${BDIR}/${rfilepath}" ]; then
  for npath in `cd $BDIR ; find ${rfilepath} -xdev -type f`
  do
    transform_delete $npath
  done
  for npath in `cd $BDIR ; find ${rfilepath} -xdev -type l`
  do
    transform_linkdel $npath
  done
  for npath in `cd $BDIR ; find ${rfilepath} -xdev -type d -depth`
  do
    transform_rmdir $npath
  done
else
  echo "WARN: transform_rrmdir cannot find directory ${rfilepath}"
fi
if [ -d "${BDIR}/${rfilepath}" ]; then
  echo "WARN: transform_rrmdir cannot remove directory ${rfilepath}"
fi
}

#
# transform to add a file to this package
# we get the copy of the file either from the proto area
# or from this repo
#
transform_add() {
FTYPE="f"
FCLASS="none"
for frag in $*
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
path)
    filepath=$value
    ;;
mode)
    mode=$value
    ;;
owner)
    owner=$value
    ;;
group)
    group=$value
    ;;
esac
done
dpath=`dirname $filepath`
if [ ! -d "${BDIR}/${dpath}" ]; then
    mkdir -p "${BDIR}/${dpath}"
fi
if [ -f "${BDIR}/${filepath}" ]; then
    echo "DBG: parsing $hash $line"
    echo "WARN: path $filepath already exists in $dpath"
fi
if [ -f "${PROTODIR}/${filepath}" ]; then
  /usr/bin/cp -p "${PROTODIR}/${filepath}" "${BDIR}/${filepath}"
elif [ -f "${TRANSDIR}/${filepath}.${ARCH32}" ]; then
  /usr/bin/cp -p "${TRANSDIR}/${filepath}.${ARCH32}" "${BDIR}/${filepath}"
elif [ -f "${TRANSDIR}/${filepath}" ]; then
  /usr/bin/cp -p "${TRANSDIR}/${filepath}" "${BDIR}/${filepath}"
else
  echo "WARN: transform_add cannot find source for ${filepath}"
fi
if [ -f "${BDIR}/${filepath}" ]; then
  echo "${FTYPE} ${FCLASS} ${filepath}=${filepath} ${mode} ${owner} ${group}" >> "${BDIR}/prototype"
fi
}

#
# transform to add a symlink to this package
#
transform_symlink() {
for frag in $*
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
path)
    filepath=$value
    ;;
target)
    target=$value
    ;;
esac
done
dpath=`dirname $filepath`
if [ ! -d "${BDIR}/${dpath}" ]; then
    mkdir -p "${BDIR}/${dpath}"
fi
if [ -f "${BDIR}/${filepath}" ]; then
    echo "DBG: parsing $hash $line"
    echo "WARN: path $filepath already exists in $dpath"
fi
echo "s none ${filepath}=${target}" >> "${BDIR}/prototype"
}

#
# transform to add a directory to this package
#
transform_mkdir() {
for frag in $*
do
    key=${frag%%=*}
    nval=${frag#*=}
    value=${nval%%=*}
case $key in
path)
    filepath=$value
    ;;
mode)
    mode=$value
    ;;
owner)
    owner=$value
    ;;
group)
    group=$value
    ;;
esac
done
if [ ! -d "${BDIR}/${filepath}" ]; then
    mkdir -p -m "$mode" "${BDIR}/${filepath}"
fi
echo "d none ${filepath} ${mode} ${owner} ${group}" >> "${BDIR}/prototype"
}

#
# transform to replace an isaexec'ed binary by the real thing
# this is a 3-stage process
# 1. remove the link to isaexec
# 2. hoist the actual binary up out of the 64-bit subdirectory
# 3. put a 64-bit symlink in place
# it checks that the real binary does not exist, as that implies
# something has changed to not make the binary managed by isaexec
#
# this process does nothing to any 32-bit file; removing that is a
# separate operation, in case you still want to ship the file
#
transform_noisaexec() {
    filepath=$1
    echo "DBG: handling noisaexec $filepath"
    if [ -f "${filepath}" ]; then
	echo "WARN: path $filepath already exists, cannot noisaexec"
	return
    fi
    filedir=${filepath%/*}
    filename=${filepath##*/}
    isafile=${filedir}/${ARCH64}/${filename}
    if [ ! -f "${isafile}" ]; then
	echo "WARN: path $isafile does not exist, cannot noisaexec"
	return
    fi
    echo transform_linkdel $filepath
    transform_linkdel $filepath
    echo transform_rename $isafile $filepath
    transform_rename $isafile $filepath
    echo transform_symlink path=$isafile target=../$filename
    transform_symlink path=$isafile target=../$filename
}

#
# a variant where the thing we're execing is a link, so it won't exist
# for checking, and we have to recreate the link
#
transform_noisaexeclink() {
    xfilepath=$1
    linkspec=$2
    echo "DBG: handling noisaexec $filepath"
    if [ -f "${filepath}" ]; then
	echo "WARN: path $filepath already exists, cannot noisaexeclink"
	return
    fi
    filedir=${xfilepath%/*}
    filename=${xfilepath##*/}
    isafile=${filedir}/${ARCH64}/${filename}
    if [ -f "${isafile}" ]; then
	echo "WARN: path $isafile exists, cannot noisaexeclink"
	return
    fi
    echo transform_linkdel $xfilepath
    transform_linkdel $xfilepath
    echo transform_linkdel $isafile
    transform_linkdel $isafile
    echo restoring link $xfilepath $linkspec
    handle_hardlink path=$xfilepath $linkspec
    echo transform_symlink path=$isafile target=../$filename
    transform_symlink path=$isafile target=../$filename
}

#
# change the NAME field in pkginfo
# can't use : as the separator because it's used in packaging
#
transform_name() {
    newname="$1"
    sed -i "s#^NAME=.*#NAME=${newname}#" "${BDIR}/pkginfo"
}

case $# in
2)
    INPKG=$1
    OUTPKG=$2
    ;;
1)
    INPKG=$1
    OUTPKG=`$PNAME $INPKG`
    ;;
*)
    usage
    ;;
esac

#
# these ought to be args
#
REPODIR=${GATEDIR}/packages/${ARCH32}/nightly-nd/repo.${MYREPO}
PROTODIR=${GATEDIR}/proto/root_${ARCH32}

if [ ! -d ${REPODIR} ]; then
    REPODIR=${GATEDIR}/packages/${ARCH32}/nightly/repo.${MYREPO}
fi
if [ ! -d "${REPODIR}" ]; then
    echo "ERROR: Missing repo"
    exit 1
fi

mkdir -p "$DSTDIR/build" "$DSTDIR/pkgs" "$DSTDIR/tmp"

#
# find the input manifest
#
PDIR="${REPODIR}/pkg/${INPKG}"
if [ ! -d "${PDIR}" ]; then
    echo "ERROR: cannot find ${PDIR}"
    exit 1
fi

#
# skip packages marked as deleted
#
if [ -f "${TRANSDIR}/deleted/${OUTPKG}" ]; then
    echo "WARN: skipping ${OUTPKG}, marked as deleted"
    exit 0
fi
if [ -f "${TRANSDIR}/deleted/${OUTPKG}.${ARCH32}" ]; then
    echo "WARN: skipping ${OUTPKG}, marked as deleted"
    exit 0
fi

MANIFEST=`find $PDIR -type f`
if [ -z "$MANIFEST" ]; then
    bail_out
fi
MANIFEST=`/bin/ls -1tr ${PDIR}/* | tail -1`

#
# this is the temporary build area
#
BDIR=$DSTDIR/build/${OUTPKG}
mkdir -p "$BDIR"
touch "${BDIR}/pkginfo" "${BDIR}/prototype"
echo "i pkginfo=./pkginfo" >> "${BDIR}/prototype"

#
# read the manifest, line by line
#
cat $MANIFEST |
{
while read directive line ;
do
case $directive in
dir)
    handle_dir $line
    ;;
set)
    handle_set $line
    ;;
depend)
    handle_depend $line
    ;;
file)
    handle_file $line
    ;;
license)
    handle_license $line
    ;;
link)
    handle_link $line
    ;;
hardlink)
    handle_hardlink $line
    ;;
legacy)
    handle_legacy $line
    ;;
driver)
    # the eval is some funky magic to pass quoted arguments
    eval handle_driver $line
    ;;
*)
    echo "...directive $directive not yet supported..."
    ;;
esac

done
}

#
# is this a completely empty package? if it has no content, no legacy
# action, and is garbage (either renamed or obsolete) then just stop
#
if [ "$HAS_CONTENT" = "false" -a "$HAS_LEGACY" = "false" -a "$IS_GARBAGE" = "true" ]; then
    echo "Empty package, bailing out"
    bail_out
fi

#
# if one of the above is true, then we're in some sort of limbo
# issue an error and carry on hoping for the best
#
if [ "$HAS_CONTENT" = "false" ]; then
    echo "Unhandled package condition - no content"
fi
if [ "$HAS_LEGACY" = "false" ]; then
    echo "Unhandled package condition - no legacy, emulating"
    emulate_legacy
fi
if [ "$IS_GARBAGE" = "true" ]; then
    echo "Unhandled package condition - garbage package"
fi

#
# SUNWcs has bogus timestamps on
# etc/logadm.conf etc/security/*attr etc/user_attr
#
# need to reset kernel state files back to null
# (IMHO, that these files are editable is a bug)
#
# also remove history of the current live system
#
cd $BDIR || exit 1
if [ -f etc/logadm.conf ]; then
    touch -r /etc/passwd etc/logadm.conf
fi
if [ -f etc/user_attr ]; then
    touch -r /etc/passwd etc/user_attr
fi
if [ -f etc/security/auth_attr ]; then
    touch -r /etc/passwd etc/security/auth_attr
fi
if [ -f etc/security/exec_attr ]; then
    touch -r /etc/passwd etc/security/exec_attr
fi
if [ -f etc/security/prof_attr ]; then
    touch -r /etc/passwd etc/security/prof_attr
fi

#
# de-ctf scsi_vhci, just in case
#
if [ -f kernel/drv/scsi_vhci ]; then
    mcs -d -n .SUNW_ctf kernel/drv/scsi_vhci
fi
if [ -f kernel/drv/amd64/scsi_vhci ]; then
    mcs -d -n .SUNW_ctf kernel/drv/amd64/scsi_vhci
fi
if [ -f kernel/drv/sparcv9/scsi_vhci ]; then
    mcs -d -n .SUNW_ctf kernel/drv/sparcv9/scsi_vhci
fi

#
# package transforms
#
if [ -f "${TRANSDIR}/${OUTPKG}" ]; then
cat "${TRANSDIR}/${OUTPKG}" |
{
while read -r action pathname line ;
do
case $action in
delete)
    transform_delete $pathname
    ;;
linkdel)
    transform_linkdel $pathname
    ;;
rmdir)
    transform_rmdir $pathname
    ;;
rrmdir)
    transform_rrmdir $pathname
    ;;
type)
    transform_type $pathname $line
    ;;
depend)
    transform_depend $pathname
    ;;
undepend)
    transform_undepend $pathname
    ;;
add)
    transform_add path=$pathname $line
    ;;
symlink)
    transform_symlink path=$pathname $line
    ;;
mkdir)
    transform_mkdir path=$pathname $line
    ;;
replace)
    transform_replace $pathname
    ;;
rename)
    transform_rename $pathname $line
    ;;
name)
    transform_name "$pathname $line"
    ;;
noisaexec)
    transform_noisaexec $pathname
    ;;
noisaexeclink)
    transform_noisaexeclink $pathname $line
    ;;
modify)
    echo "DBG: gsed -i '$line' ${BDIR}/${pathname}"
    gsed -i "$line" "${BDIR}/${pathname}"
    ;;
*)
    echo "...transform action $action not yet supported..."
    ;;
esac

done
}
fi
#
# architecture-specific package transforms
#
if [ -f "${TRANSDIR}/${OUTPKG}.${ARCH32}" ]; then
cat "${TRANSDIR}/${OUTPKG}.${ARCH32}" |
{
while read -r action pathname line ;
do
case $action in
delete)
    transform_delete $pathname
    ;;
linkdel)
    transform_linkdel $pathname
    ;;
rmdir)
    transform_rmdir $pathname
    ;;
rrmdir)
    transform_rrmdir $pathname
    ;;
type)
    transform_type $pathname $line
    ;;
depend)
    transform_depend $pathname
    ;;
undepend)
    transform_undepend $pathname
    ;;
add)
    transform_add path=$pathname $line
    ;;
symlink)
    transform_symlink path=$pathname $line
    ;;
mkdir)
    transform_mkdir path=$pathname $line
    ;;
replace)
    transform_replace $pathname
    ;;
rename)
    transform_rename $pathname $line
    ;;
noisaexec)
    transform_noisaexec $pathname
    ;;
noisaexeclink)
    transform_noisaexeclink $pathname $line
    ;;
modify)
    echo "DBG: gsed -i '$line' ${BDIR}/${pathname}"
    gsed -i "$line" "${BDIR}/${pathname}"
    ;;
*)
    echo "...transform action $action not yet supported..."
    ;;
esac

done
}
fi

#
# if there were any services that need to be restarted, create install scripts
#
handle_restarts

#
# some of the packages have broken dependencies, so we exit cleanly to
# stop errors from missing services messing up pkgadd or pkgrm
#
# also rem_drv doesn't exit cleanly
#
# in any case, the policy is that packaging should succeed so that we
# can sort out errors later
#
if [ -f "${BDIR}/install/postinstall" ]; then
    echo "exit 0" >> "${BDIR}/install/postinstall"
    chmod 0555 "${BDIR}/install/postinstall"
fi
if [ -f "${BDIR}/install/postremove" ]; then
    echo "exit 0" >> "${BDIR}/install/postremove"
    chmod 0555 "${BDIR}/install/postremove"
fi

#
# sign elf objects if requested
# find_elf only finds libraries and binaries, not kernel modules
# so do those manually
# elfsign requires the file to be writable
#
if [ -n "$SIGNCERT" ]; then
    cd "$BDIR" || exit 1
    for exe in $(${FINDELF} . | grep '^OBJECT' | /usr/bin/awk '{if ($3 == "EXEC" || $3 == "DYN") print $NF}')
    do
	chmod u+w "$exe"
	/usr/bin/elfsign sign -k "${SIGNCERT}.key" -c "${SIGNCERT}.crt" -e "$exe"
    done
    if [ -d platform ]; then
	for exe in $(find platform -type f | grep -v '\.conf$')
	do
	    chmod u+w "$exe"
	    /usr/bin/elfsign sign -k "${SIGNCERT}.key" -c "${SIGNCERT}.crt" -e "$exe"
	done
    fi
    if [ -d kernel ]; then
	for exe in $(find kernel -type f | grep -v '\.conf$')
	do
	    chmod u+w "$exe"
	    /usr/bin/elfsign sign -k "${SIGNCERT}.key" -c "${SIGNCERT}.crt" -e "$exe"
	done
    fi
    if [ -d usr/kernel ]; then
	for exe in $(find usr/kernel -type f | grep -v '\.conf$')
	do
	    chmod u+w "$exe"
	    /usr/bin/elfsign sign -k "${SIGNCERT}.key" -c "${SIGNCERT}.crt" -e "$exe"
	done
    fi
fi

#
# build a package
#
cd "$BDIR" || exit 1
${PKGMK} -d "$DSTDIR/tmp" -f prototype -r $(pwd) "${OUTPKG}" > /dev/null
if [ -n "${QUICKMODE}" ]; then
    mkdir -p "$DSTDIR/quick"
    mv "${DSTDIR}/tmp/${OUTPKG}" "$DSTDIR/quick"
    cd /
    rm -fr "$BDIR"
    exit 0
fi
${PKGTRANS} -s "$DSTDIR/tmp" "${DSTDIR}/pkgs/${OUTPKG}.${PKG_VERSION}.pkg ${OUTPKG}" > /dev/null
if [ -f "${DSTDIR}/pkgs/${OUTPKG}.${PKG_VERSION}.pkg" ]; then
    cd /
    bail_out
fi
exit 0
