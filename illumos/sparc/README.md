# SPARC builds

The SPARC builds before m26 were built from a vanilla gate at the same
checkout to the corresponding x86 release. The m26 release was from a
vanilla illumos-gate, but with a slightly different commit to x86.

Subsequent releases are built differently. Upstream gate cannot be used
as SPARC support has been removed. They start from a fixed commit, and
then cherry-pick subsequent commits (sometimes modified).

The scripts sparc-repo-m27.sh and similar describe the exact commits
and patches used. A copy of the patches used is in the gate-patches
directory here; some of the patches are modified as necessary.
