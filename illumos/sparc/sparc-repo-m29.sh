#!/bin/sh
#
# SPDX-License-Identifier: CDDL-1.0
#
# Copyright 2025 Peter Tribble
#
# this script reproduces the m29 sparc repo
#
# assumes my gatepatch script is in the path
#
THISGATE=m29-gate

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
# m28 from here
# fmthard needed by ipd4
gatepatch d4a480543b4d3a54736b195968989e52bf3a854a
# libnisdb needed by ipd4
gatepatch 439b932b1a6fbc5105bd6987cb696a707183a149
# chmod needed by ipd4
gatepatch cf96e8bf1ffaa8e64318435100a5e29e9d7971c7
# ena (needed for other patches)
gatepatch 6f443ebc1fb4fec01d6e8fa8ca4648182ed215bb
# posix pty nomenclature OK
gatepatch 1fa2a66491e7d8ae0be84e7da4da8e812480c710
# ufs no directory unlink OK
gatepatch ad8f9d956254e0caad9e4f8c85217f97cbdcade2
# diff -q OK
gatepatch d2b76ef70a19a09ea9aab5aaeb614dc7c9d195ed
# IPD4 - quite a lot of breakage
gatepatch bbf215553c7233fbab8a0afdf1fac74c44781867
# tzdata 2022a OK
gatepatch 2de2fd878c86481f0654c04127ab602117c48830
# 64-bit pam_smb_passwd.so.1 OK
gatepatch c4140c56306ad2a74081dd949618b4f3162dd06b
# 14562 zfs OK
gatepatch f43aa5faf71b05bec443dbb0af363ddeaff8ec17
# 14593 zpool OK
gatepatch 7d6cab3f0d6a4cea17d062d3a93e223b15de705c
# man4i [depends on ipd4] OK
gatepatch 899b7fc7762875c5244567fbc6bb4ccace75d6f7
# smf ipmp OK
gatepatch 57cf819efa50a6a3b3a478c25a098c29722eb358
# 14619 OK
gatepatch 041297c2d66302c15134da1d1bdd91cf787a945a
# pwait OK
gatepatch b1bc843f030b066c3da149508c52f7306b25b8ff
# mman.h - man fails, otherwise OK
gatepatch df5cd018c34371890eeeb8c930245b9323e8aa25
# ld - !partial failure, rejected
# gatepatch fb12490ab4d1e87e7a63e457dd4fba1ea34c402a
# select.3c OK
gatepatch 19141168d83c6b9692f40a6885b0c7258161ec6b
# loader to make the zlib patch clean
gatepatch 554e720a4cb6223d6736bd96950f9ad7d853f2a9
gatepatch 8c65387009c4cfaa0924c78065b46a4d4a178d41
# zlib 1.2.12 !partial failure, mostly OK
gatepatch 148fd93e57d3d5813d90f1291e6bd30de45c7723
# strip OK
gatepatch 56b75c05d0c84c701fbb1eb2a572b0ecee66f012
# man xref OK
gatepatch c55633c3b85a97a093b3f79f341aee08eb6bd15b
# 3729 OK
gatepatch 3ee592424ed4bb7b850d9adccb9f3c493ce7534b
# man OK
gatepatch ceb17889bb64b964be7a5439344cc243f0498512
gatepatch 5b0d53307d70a828ad7aef4dc6d8a3ad7d5c231b
gatepatch feea3b2dd6c0c3b59dfb1ab0f992b01906567d90
# pyzfs OK
gatepatch 38aced4fb3d60e34a44207b22d0b0dd4909bf4d1
# man OK
gatepatch 0a4ff7c07705facb2cf0991453d0a3e20cdc50ce
# kssl problematic
# gatepatch 7d10cd4ddf12f982d3bc7edcd01cc8b8d1dcc464
# man OK
gatepatch 92ee55c7e1c76d6edfc89c4ad988922d56888580
# aout problematic
# gatepatch 9174bfaa08ca3aa4c0a12e840c4bd4f2570237a0
# nca problematic
# gatepatch 15f90b02bdacbf0ae47fa105944f15b6596f9748
# gatepatch d5ba932774e3e5d63ba25284cae7bb0e8a0b5d1d
# [this is about Jul 2022]
# just after came 14786 remove packaging support for SPARC
# setuname OK 
gatepatch fed77ffd89ea4501fe7b7103197dc7541246e3bb
# zlib OK
gatepatch 2e401babeb53295c8df347e32364beadc0ed1620
# man OK 
gatepatch 50959a0eb0e3bc8618e60f532f23b93bfc7bcad7
# tzdata 2022b OK 
gatepatch 427b4c5ce2bacaad900016741167a4293e7a4fde
# 14930 (fixes 3729)
gatepatch 2ec63ffb3ec249bd7cb4523118c8437e6c6be335
# tnf problematic
# gatepatch 2570281cf351044b6936651ce26dbe1f801dcbd8

# m29 from here L7003
# man ipadm
gatepatch 625b8b2ac3f4d9aee6c88dfdf2b99a6423a9b5b5
# tzdata 2022d
gatepatch fff4a95698f012e39591174e3bcfcbb5d83f7034
# 14548 snoop has strange bedfellows
gatepatch 470204d3561e07978b63600336e8d47cc75387fa
# tzdata 2022f
gatepatch f117aa50f60d0a3e62bfa8cbddecd855d648a464
# 15191 Convert sharemgr(8) to mandoc
gatepatch f92d0ef50ade5e261591e634cd91553a9658cf72
# 15387 snoop: buffer overflow in netbiosname2ascii()
gatepatch 576b08ea81d99ad56d74d406b713f1badc94f637
# 15246 scsi_hba_attach_setup(9F): Typo dev_bus_ops -> devo_bus_ops
gatepatch c77843b01543b72a167a9899efe84a9743d98ab8
# 15381 fix inw(9F) synopsis
gatepatch 58e7cf8311dcd6a59422313fbb06e47b9e14b779
# 15401 Spelling mistakes in section 3c of the manual
# modified to remove pthread_mutex_init
gatepatch 4a8d6d7c6863b4310fb772fbc42910bd3126b7aa
# 15404 The rup.1c manual page unnecessarily duplicates rup.1
gatepatch 58b0c750516461d4f52a4ce7d86b1cc0619c196c
# 15402 Incorrect service name and other errors in the zonestat(1) manual
gatepatch 43a6dad6f69186cf44370a0d7565c00acb3e265e
# 14705 Extra spaces in the manual
gatepatch b92be93cdb5c3e9e673cdcb4daffe01fe1419f9e
# 15406 Duplicate SEE ALSO entries in the manual
gatepatch 806838751b3ce15414781bffd4adfac166204c62
# 15469 Spelling mistakes in the manual
gatepatch 11845c326ad8c691a402c512ccf50d1792fd6aab
# 15476 csh should be mediated in the packaging
gatepatch 5418b7d90f4acb3e524771dad953c2cad85e61bb
# tzdata 2023b
gatepatch af2e290bb42516a18ceaf6aed43dd7e45c108b08
# 15471 replace csh based which(1) with implementation in C from BSD
gatepatch c464e8d1c46f2eb4848495bcfccd020b8481787d
# tzdata 2023c
gatepatch e519aeb4e5d9ffab4de922a01a99749bdfaf523a
# 15799 The ndd manual still refers to nca(1)
gatepatch fcc1989165c64ff33645a934c567fa4909b3c507
# 15800 Typos in the pmap manual
gatepatch 8036f8bd7c6d7f2aabce516dceaa94a666184553
# 15841 Some man pages contain incorrect bin paths
gatepatch cbc1ee827389bb051e180a9bb8fe62c8136b0548
# 15845 Errors in pam manual pages
gatepatch 10a40e179c111088c21d8e895198ac95dcb83d14
# 15731 Tidy up audio driver man pages
gatepatch 63e22ea4f2e3c9c64bbc3b905c94bff00b65df13
# 16003 pkg:/system/network/spdadm
gatepatch 575c9402f8074257d0d40d88a0db7e83f09a05a9
# 16061 man: qsort has no argument Ibase
gatepatch 8c9d84f540d1f878958d02bef1d5c221fc8d30c0
# tzdata 2023d
gatepatch b4eb54e12087790f14dc9589afa6713f3f53588d
