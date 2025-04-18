#!/bin/sh
#
# SPDX-License-Identifier: CDDL-1.0
#
# Copyright 2025 Peter Tribble
#
# this script reproduces the m27 sparc repo
#
# assumes my gatepatch script is in the path
#
THISGATE=m27-gate

THOME=${THOME:-/packages/localsrc/Tribblix}
alias gatepatch=${THOME}/tribblix-build/illumos/sparc/gatepatch
REFGATE=${HOME}/Illumos-reference/illumos-gate
git clone "${REFGATE}" "${THISGATE}"
cd "${THISGATE}"

#
# this is the baseline, with reverts to kill off breakage
#
# just before the 13707/13708 breakage
git checkout 6538c7b4c76e1d53fc801540cfe1dfe59d26bf29
# revert 14196 Want librename
git revert --no-edit 6e2462f93bf3de7b08885a4677464e11be3c807b
# revert 13806 which disable the dladm warning gags
git revert --no-edit f3ac7507d50b5ba3cf8e8f10d10cedc91620ed29
# revert 14158 compiler breakage
git revert --no-edit 3873d743e5df219b4232c7efe3c4be24a673379f

#
# and now we effectively cherry-pick subsequent patches
#
# 14189 14190
gatepatch c53c97f77356a767b8a3cec554ede591cf4074d9
gatepatch 252adeb303174e992b64771bf9639e63a4d55418
gatepatch 83c2c0baa22bd77bc77facf1e1ef091642673ce2
gatepatch da0001592ab4792956d927cb6a8dc2c02c7e6719
gatepatch db2effc6fa1e364418090bfc0ca0cfd267792bea
gatepatch 9495f63eafceb1605bec42e743f2976df42d683a
gatepatch 19d47a18af13baff2c2fb35e9dde5bf902143f07
gatepatch fb25420ba8dbfa4c292d42c87555eee97a474854
# this is the pkg v2 update
# this one needed some changes;
# remove libidspace and librename
# remove cores and dumper from ostests
gatepatch 86d4171132ce4f4c1345b7ce0d5048577e1f3976
# this is the pkg rename
gatepatch 25b05a3ecbac136f5e1192d4d9e79dc14f895785
#
gatepatch 705b6680745618ebbf67feb254ce9a62511084a5
gatepatch d8f839f91e21bea2f5200f95df55608cbecdeeb9
gatepatch f81209f5137586c57e31f7d74b929149299d9b3c
gatepatch a73be61a80f7331c35adfa540bcf8f1546ff1e33
# pkg v2 on inc files
gatepatch 96bb5f330b9b75a0f74766485ffaf400a063a668
#
gatepatch a28480febf31f0e61debac062a55216a98a05a92
gatepatch ffe0b5fa2f11b603291b4b98b4f727bc8c8dbd9c
gatepatch 2c181cc4d9d2e7a92c98a12cafffc6dadff80019
gatepatch eabc1bc5e61dbfdd2fc3cb588315c864d621d500
gatepatch 338d6fc1b322c01b220f204edde962e843478a78
gatepatch 0be687ea0c09cd50b4ae51df829900fea257d535
gatepatch 617b28ccfac40348ebae033171d0643fcca18c22
gatepatch 92c32ccad68fb065a366d11e8f3dfcd5c6ebae94
gatepatch b3619796d92b4472acfed6b7c813f83cef335013
gatepatch 3d6d4f792e72bec8b227212e65f7555396295d84
gatepatch 861fa1490335b8e3cc91a1efafd8b9e481813931
gatepatch 4d131170e62381276a07ffc0aeb1b62e527d940c
gatepatch eb9b100249a3fb5f3c9f9dae512c8fe719bb6110
gatepatch 9d6ca3965c3358c32eb68544fe91ff8ad9c3fcde
gatepatch 123e0aa39ff14433d916a870ec23b74c77097914
# this is the tmpfs CVE in 25.3:
gatepatch f859e7171bb5db34321e45585839c6c3200ebb90
gatepatch 186c806e1377410853ef84873c5f064d8e980262
gatepatch 1aff3eee7740231f158365739d74142c5cf1947a
# this is 14329, modify as it would otherwise remove sparc
gatepatch 1dc4a5921402bdb59d1de1e99e79a3f9d0dd51df
gatepatch dc5774e5554edd469013b4fe1c42fbd63f5212e1
gatepatch 772eca3305893e0fc7b9c13ec6a1a6df72251dbd
gatepatch 25cdfc4f8d373444e56178d1053ca53f1c3ea928
# feature cron randomized delay 14358:
gatepatch 618372bccd696950e1d234d0ad9c94c353882dee
gatepatch 9023fe694e5cc93a381708677f172a85f250caa5
gatepatch 597b30361cb132283d94270df35d0536cf12895f
gatepatch b51a7e2003caa1eee7cfd998a535231eb646bb8d
gatepatch e8b9fe7cd6fc0b13bcf65e0380c48fcb99ac5700
gatepatch 8ac8a393f9ba5b2bf3aeabc50511c40334e9f5c8
gatepatch c8f4a9f75f12adb1f76391a838d75f2b427becb6
gatepatch 11029d9dcf6c3fb63ae0cbb0ad67f86d267db4eb
gatepatch 094cd349c8e33cc6119847f48b8ec86874a7c947
gatepatch e2d5561a2e4376608422303f917fd80a7ed70298
gatepatch 6b3099ac66a51f03e3d221e99f2427e42d2dff93
gatepatch dfc4fe31363cc213fe0423dc162bc08298c796cd
gatepatch c2cd3a449cfa117e3a164f66931fa6c26c762945
