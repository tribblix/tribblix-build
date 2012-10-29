#!/bin/ksh
#
# convert an ips package to svr4, from an on-disk repo
#

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
# obvious shortcomings and fixes:
#
# 1. any non-file actions need auto-generated scripts to be created
# 2. What are the real package names?
# 3. What are the package names used in dependencies? Presumably the
#   legacy ones, as that's what the svr4 emulation layer creates. In that
#   case we need to use the legacy names too, or have a translation map
#   into a private namespace
# 4. Should skip any package for which pkg.renamed is true; we aren't
#   that interested in obsoleted packages. Should probably check for
#   dependencies on renamed packages and correct them, though
#

#
# weaknesses of the current implementation
# 1. no attempt at architecture variants
# 2. fixed paths
# 3. need to fully handle set actions
# 4. need to fully handle driver actions
# 5. need to check dependencies, once we've solved package naming
# 6. handle reboot-needed
# 7. handle editable files (how identified - preserve=renamenew ?)
# 8. Need to handle multiple legacy lines in a single manifest (eg ZFS)
# 9. Need to handle global/ngz
#

#
# Global variables
#
PKGDIR=/usr/bin
#PKGDIR=/var/tmp/nbuild/sprate-0.09/bin
PKGMK="${PKGDIR}/pkgmk"
PKGTRANS="${PKGDIR}/pkgtrans"
PNAME=/home/ptribble/Tribblix/pkg_name.sh

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
    rm -fr $BDIR $DSTDIR/tmp/${OUTPKG}
    exit 0
}

#
# initialize driver handling by creating the postinstall and postremove
# scripts
#
init_driver() {
mkdir -p ${BDIR}/install
if [ ! -f ${BDIR}/install/postinstall ]; then
cat > ${BDIR}/install/postinstall <<EOF
#!/sbin/sh
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
cat > ${BDIR}/install/postremove <<EOF
#!/sbin/sh
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
chmod a+x ${BDIR}/install/postremove ${BDIR}/install/postinstall
echo "i postinstall=./install/postinstall" >> ${BDIR}/prototype
echo "i postremove=./install/postremove" >> ${BDIR}/prototype
fi
}

#
# initialise dependency handling
#
init_depend() {
mkdir -p ${BDIR}/install
if [ ! -f ${BDIR}/install/depend ]; then
cat > ${BDIR}/install/depend <<EOF
# The following dependencies are automatically generated
# from the IPS manifest for this package, with automatic
# generation of SVR4 package names.
#
# No version information is preserved
#
EOF
echo "i depend=./install/depend" >> ${BDIR}/prototype
fi
}

#
# if there are services that should be restarted, add them to the postinstall
# script
#
handle_restarts() {
if [ -f ${BDIR}/restart_fmri_list ]; then
mkdir -p ${BDIR}/install
if [ ! -f ${BDIR}/install/postinstall ]; then
cat > ${BDIR}/install/postinstall <<EOF
#!/sbin/sh
#
# Automatically generated service restart script
#
EOF
cat > ${BDIR}/install/postremove <<EOF
#!/sbin/sh
#
# Automatically generated service restart script
#
EOF
chmod a+x ${BDIR}/install/postremove ${BDIR}/install/postinstall
echo "i postinstall=./install/postinstall" >> ${BDIR}/prototype
echo "i postremove=./install/postremove" >> ${BDIR}/prototype
fi
#
# this check is so we only actually restart if the install is to the
# current system. If we're installing to an alternate image, then the
# restarts will happen automatically when it boots
#
# FIXME should the restart be -s
#
cat >> ${BDIR}/install/postinstall <<EOF
if [ "\${BASEDIR}" = "/" ]; then
EOF
cat >> ${BDIR}/install/postremove <<EOF
if [ "\${BASEDIR}" = "/" ]; then
EOF
/usr/bin/cat ${BDIR}/restart_fmri_list | /usr/bin/sort | /usr/bin/uniq | /usr/bin/awk '{print "/usr/sbin/svcadm restart "$1}' >> ${BDIR}/install/postinstall
/usr/bin/cat ${BDIR}/restart_fmri_list | /usr/bin/sort | /usr/bin/uniq | /usr/bin/awk '{print "/usr/sbin/svcadm restart "$1}' >> ${BDIR}/install/postremove
echo "fi" >> ${BDIR}/install/postinstall
echo "fi" >> ${BDIR}/install/postremove
#
# some of the packages have broken dependencies, so we exit cleanly to
# stop errors from missing services messing up pkgadd or pkgrm
#
echo "exit 0" >> ${BDIR}/install/postinstall
echo "exit 0" >> ${BDIR}/install/postremove
/usr/bin/rm ${BDIR}/restart_fmri_list
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
CLONEPERMS=""
ALIASES=""
CLASS=""
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
alias)
    if [ "x${ALIASES}" = "x" ]; then
	ALIASES="-i '"'"'$value'"'
    else
	ALIASES="${ALIASES} "'"'$value'"'
    fi
    ;;
class)
    CLASS="-c $value"
    ;;
*zone*)
    printf ""
    ;;
clone_perms)
    CLONEPERMS="'$value'"
    ;;
*)
    echo unhandled driver action $frag
    ;;
esac
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
    echo "${CMD_FRAG} ${PERMS} ${ALIASES} ${CLASS} $DNAME" >> ${BDIR}/install/postinstall
    echo "${CMD_FRAG} $DNAME" >> ${BDIR}/install/postremove
fi
if [ "x${CLONEPERMS}" != "x" ]; then
    echo "${UCMD_FRAG} -a -m ${CLONEPERMS} clone" >> ${BDIR}/install/postinstall
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
    printf ""
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
    printf ""
    ;;
*)
    echo "unhandled dir attributes $frag"
    ;;
esac
done
mkdir -p -m $mode ${BDIR}/${dirpath}
echo "d none ${dirpath} ${mode} ${owner} ${group}" >> ${BDIR}/prototype
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
    printf ""
    ;;
path)
    dirpath=$value
    ;;
target)
    target=$value
    ;;
*)
    echo "unhandled link attribute $frag"
    ;;
esac
done
echo "s none ${dirpath}=${target}" >> ${BDIR}/prototype
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
    printf ""
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
echo "l none ${dirpath}=${target}" >> ${BDIR}/prototype
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
    # FIXME could filter on elfbits to make a 32-bit distro
    printf ""
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
    printf ""
    ;;
restart_fmri)
    touch ${BDIR}/restart_fmri_list
    echo $value >>${BDIR}/restart_fmri_list
    ;;
*)
    echo "unhandled file attribute $frag"
    ;;
esac
done
dpath=`dirname $filepath`
if [ ! -d ${BDIR}/${dpath} ]; then
    echo mkdir -p ${BDIR}/${dpath}
    mkdir -p ${BDIR}/${dpath}
fi
if [ -f ${BDIR}/${filepath} ]; then
    echo "DBG: parsing $hash $line"
    echo "WARN: path $filepath already exists in $dpath"
fi
/usr/bin/cp -p ${REPODIR}/file/${fh}/${fhash} ${BDIR}/${filepath}.gz
/usr/bin/gunzip ${BDIR}/${filepath}.gz
/usr/bin/chmod $mode ${BDIR}/${filepath}
if [ "xx${TSTAMP}" != "xx" ]; then
    /bin/touch -t ${TSTAMP} ${BDIR}/${filepath}
fi
echo "f none ${filepath}=${filepath} ${mode} ${owner} ${group}" >> ${BDIR}/prototype
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
NAME="$name"
VERSION="$version"
ARCH="$arch"
CATEGORY="$category"
VENDOR="$vendor"
BASEDIR="/"
PKG="$OUTPKG"
DESC="$desc"
# FIXME why null?
# the problem appears to be if a legacy line includes a facet
if [ "x$VERSION" = "x" ]; then
  VERSION="1.0"
fi
# PSTAMP automatically generated by pkgmk
# CLASSES automatically set by pkgmk
echo "PKG=\"${PKG}\"" >> ${BDIR}/pkginfo
echo "NAME=\"${NAME}\"" >> ${BDIR}/pkginfo
echo "ARCH=\"${ARCH}\"" >> ${BDIR}/pkginfo
echo "VERSION=\"${VERSION}\"" >> ${BDIR}/pkginfo
echo "CATEGORY=\"${CATEGORY}\"" >> ${BDIR}/pkginfo
echo "VENDOR=\"${VENDOR}\"" >> ${BDIR}/pkginfo
echo "BASEDIR=\"${BASEDIR}\"" >> ${BDIR}/pkginfo
}

emulate_legacy() {
HAS_LEGACY=true
NAME="$OUTPKG"
VERSION=`uname -v`
ARCH=`uname -p`
CATEGORY="application"
VENDOR="Tribblix"
BASEDIR="/"
PKG="$OUTPKG"
# FIXME should be pkg.summary
DESC="$OUTPKG"
# PSTAMP automatically generated by pkgmk
# CLASSES automatically set by pkgmk
echo "PKG=\"${PKG}\"" >> ${BDIR}/pkginfo
echo "NAME=\"${NAME}\"" >> ${BDIR}/pkginfo
echo "ARCH=\"${ARCH}\"" >> ${BDIR}/pkginfo
echo "VERSION=\"${VERSION}\"" >> ${BDIR}/pkginfo
echo "CATEGORY=\"${CATEGORY}\"" >> ${BDIR}/pkginfo
echo "VENDOR=\"${VENDOR}\"" >> ${BDIR}/pkginfo
echo "BASEDIR=\"${BASEDIR}\"" >> ${BDIR}/pkginfo
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
  echo "IPS_DESCRIPTION=$value" >> ${BDIR}/pkginfo
  ;;
'pkg.summary')
  echo "IPS_SUMMARY=$value" >> ${BDIR}/pkginfo
  ;;
'pkg.fmri')
  echo "IPS_FMRI=$value" >> ${BDIR}/pkginfo
  ;;
'info.classification')
  echo "IPS_CLASSIFICATION=$value" >> ${BDIR}/pkginfo
  ;;
'org.opensolaris.consolidation')
  echo "IPS_CONSOLIDATION=$value" >> ${BDIR}/pkginfo
  ;;
'variant.arch'|'variant.opensolaris.zone'|'opensolaris.smf.fmri'|'org.opensolaris.smf.fmri'|'opensolaris.arc_url')
  printf ""
  ;;
'info.repository_changeset'|'info.maintainer_url'|'info.repository_url'|'info.defect_tracker.url'|'info.source_url'|'info.upstream_url'|'info.upstream')
  printf ""
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
    printf ""
    ;;
*)
    svr4_name=`$PNAME $pkg_name`
    init_depend
    echo "P $svr4_name" >> ${BDIR}/install/depend
    ;;
esac
    ;;
*)
    printf ""
    ;;
esac
  ;;
*)
  echo "Unhandled dependency type $type"
  ;;
esac
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
REPODIR=/home/ptribble/illumos/code/illumos-gate/packages/i386/nightly/repo.redist
DSTDIR=/var/tmp/illumos-pkgs

if [ ! -d "${REPODIR}" ]; then
    echo "ERROR: Missing repo"
    exit 1
fi

mkdir -p $DSTDIR/build $DSTDIR/pkgs $DSTDIR/tmp

#
# find the input manifest
#
PDIR="${REPODIR}/pkg/${INPKG}"
if [ ! -d "${PDIR}" ]; then
    echo "ERROR: cannot find ${PDIR}"
    exit 1
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
mkdir -p $BDIR
touch ${BDIR}/pkginfo ${BDIR}/prototype
echo "i pkginfo=./pkginfo" >> ${BDIR}/prototype

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
    echo ...directive $directive not yet supported...
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
# if there were any services that need to be restarted, create install scripts
#
handle_restarts

#
# build a package
#
cd $BDIR
${PKGMK} -d $DSTDIR/tmp -f prototype -r `pwd` ${OUTPKG} > /dev/null
${PKGTRANS} -s $DSTDIR/tmp ${DSTDIR}/pkgs/${OUTPKG}.pkg ${OUTPKG} > /dev/null
if [ -f ${DSTDIR}/pkgs/${OUTPKG}.pkg ]; then
    cd /
    bail_out
fi
exit 0
