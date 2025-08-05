#!/bin/bash

## Helper scripts for Droidian kernel compilation
#
# Version: 0.0.12
#
# Upstream-Name: berb-kernel-build-helper-scripts
# Source: https://github.com/berbascum/berb-kernel-build-helper-scripts
#
# Copyright (C) 2024 Berbascum <berbascum@ticv.cat>
# All rights reserved.
#
# BSD 3-Clause License
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the <organization> nor the
#      names of its contributors may be used to endorse or promote products
#      derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

abort() {
    echo; echo "$*"; exit 1
}

START_DIR="/buildd/sources"
KERNEL_DIR="${START_DIR}"
## Check for /buildd/sources dir
[ -d "${KERNEL_DIR}" ] || abort "The expected ${KERNEL_DIR} does not exist!"
## Check for a kernel tree root
[ -f "$(pwd)/Kconfig" ] || abort "Not in a kernel source dir!"

ROOTDIR="/opt"
## The arch var is used by clang-manual, but not by releng
export ARCH=arm64

fn_enable_ccache() {
    ## Use ccache tu speedup the build
    export USE_CCACHE=1
    export CCACHE_EXEC=/usr/bin/ccache
    ccache -M 10G
    ccache -o compression=false
    ccache -s
    exit
}

fn_install_prereqs_kernel_build() {
apt-get update
apt-get install linux-packaging-snippets bc bison build-essential ccache curl flex git git-lfs gnupg gperf imagemagick libelf-dev libncurses5-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev python3 python-is-python3
# libsdl1.2-dev
}

fn_install_prereqs_droidian_tools() {
    ## Update apt
    apt-get update
    ## For Debian bullseye clang-11 arm64
    # apt-get install apt-config-berbascum-bullseye-debian
    # apt-get install apt-config-berbascum-bookworm-debian
    ## Add Droidian apt repo
    apt-get install apt-config-berbascum-trixie-droidian
    ## Update apt
    apt-get update
    apt-get install droidian-apt-config droidian-archive-keyring apt-transport-droidian
    ## Set Droidian to next
    echo "Acquire::Droidian::Version "next";" > /etc/apt/apt.conf.d/90-droidian-snapshot
    ## Update apt
    apt-get update
    ## Install Droidian build tools
    apt-get update && apt-get install -y --no-install-recommends linux-packaging-snippets releng-tools
    ## releng-tools: craches on arm64 docker host
}

fn_install_prereqs_droidian_kernel_info() {
    apt-get install binutils-aarch64-linux-gnu clang-android-${CLANG_VERSION} gcc-4.9-aarch64-linux-android g++-4.9-aarch64-linux-android libgcc-4.9-dev-aarch64-linux-android-cross
}

fn_install_clang_custom() {
#CLANG_CUSTOM_URL="https://github.com/android-berb/platform.prebuilts.clang.host.linux-x86.git"
#CLANG_CUSTOM_BRANCH="clang-14-r450784e-a14-x86"

##### Download branch as zip
    if [ -z "${BUILD_PATH}" ] || [ ! -d "${BUILD_PATH}" ]; then \
        BUILD_PATH_BASE="/opt"

        echo "Start clang custom download"

	#echo "CLANG_CUSTOM_BRANCH val: $CLANG_CUSTOM_BRANCH"
	#read -p "CLANG_CUSTOM_URL val: ${CLANG_CUSTOM_URL}"
	## Check the url for a supported suffix
        arr_download_types=( "git" )
        for download_type in ${arr_download_types[@]}; do
            check_url="$(echo ${CLANG_CUSTOM_URL} | grep -c ${download_type})"
            [ "${check_url}" -eq "1" ] && break
        done
        [ "${check_url}" == "0" ] && abort "Download type \"${download_type}\" not supported"
        if [ "${download_type}" == "git" ]; then
	        clang_url_cleaned=$(echo ${CLANG_CUSTOM_URL} | sed "s|.${download_type}$||g")
            clang_dir_name="$(basename ${CLANG_CUSTOM_URL} | awk -F".${download_type}" '{print $1}')"
	        ## The zip natively contains a dir named:
	           ## <repo>-<branch>
	        clang_dir_in_zip_name="${clang_dir_name}-${CLANG_CUSTOM_BRANCH}"
	        ## Download the toolchain
	        if [ ! -d "${BUILD_PATH_BASE}/${clang_dir_in_zip_name}" ]; then
                wget ${clang_url_cleaned}/archive/refs/heads/${CLANG_CUSTOM_BRANCH}.zip -O /tmp/${CLANG_CUSTOM_BRANCH}.zip
            [ "$?" -eq "0" ] || abort "Download failed"
	        fi
        fi
	    ## Extract the toolchain
	    if [ ! -d "${BUILD_PATH_BASE}/${clang_dir_in_zip_name}" ]; then
            unzip /tmp/${CLANG_CUSTOM_BRANCH}.zip \
		-d ${BUILD_PATH_BASE}
            [ "$?" -eq "0" ] || abort "Unpack failed"
            rm /tmp/${CLANG_CUSTOM_BRANCH}.zip
	    fi
        arr_bins_found=()
        for bin_found in $(find ${BUILD_PATH_BASE}/${clang_dir_in_zip_name} -wholename '*bin/clang-*'); do
            bin_path="$(dirname "${bin_found}")"
            found_in_arr="$(echo ${arr_bins_found[*]} | grep -c "${bin_path}")"
                echo "found_in_arr: $found_in_arr"
            if [ "${found_in_arr}" -eq "0" ] ; then
                arr_bins_found+=( "${bin_path}" )
            fi
        done
        if [ "${#arr_bins_found[@]}" -eq "0" ]; then
            abort "No dirs found matching bin/clang"
        elif [ "${#arr_bins_found[@]}" -eq "1" ]; then
            export CLANG_CUSTOM_PATH="${arr_bins_found[0]}"
        elif [ "${#arr_bins_found[@]}" -gt "1" ]; then
            abort "Found \"${#arr_bins_found[@]}\" dirs matching bin/clang"
        fi
        #echo "clang_dir_name val: \"$clang_dir_name\""
        echo "CLANG_CUSTOM_PATH val: \"$CLANG_CUSTOM_PATH\""
    fi
##### TODO: Cloning a git repo alternate method
        #BUILD_PATH_BASE="/opt"
        #clang_dir_name="$(basename ${CLANG_CUSTOM_URL} | awk -F".${download_type}" '{print $1}')"

#        git clone ${CLANG_CUSTOM_URL} ${BUILD_PATH_BASE}/${clang_dir_name}
#
# wget https://github.com/android-berb/platform.prebuilts.clang.host.linux-x86/archive/refs/heads/android-gs-felix-5.10-android14-qpr3.zip -O branch.zip
<< "DISABLED_TAR_SAMPLE"
    if [ ! -d "/usr/lib/llvm-android-${CLANG_VERSION}/bin" ]; then
        cd /usr/lib
        wget https://github.com/droidian-berb/android-platform-prebuilts-clang-host-linux-x86/raw/main/llvm-clang-${CLANG_VERSION}-droidian-x86_aarch64.tar.gz
        echo "Extracting clang..."
        tar zxf llvm-clang-${CLANG_VERSION}-droidian-x86_aarch64.tar.gz
    fi
DISABLED_TAR_SAMPLE
}

fn_install_lineage_toolchains() {
    cd /opt
    # gcc
    git clone -b lineage-18.1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git
    #
    # clang
#    git clone https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git
    #
    # build-tools
    los_ver="lineage-18.1"
    los_branch="android-11.0.0_r0.100"
    # los_branch="android-13.0.0_r0.117"
    # los_ver="lineage-20.1"
    git clone -b ${los_branch} \
    https://android.googlesource.com/kernel/prebuilts/build-tools
    git clone -b ${los_branch} https://github.com/LineageOS/android_prebuilts_tools-lineage.git
}

######################################
## Clang manual lineage build tools ##
######################################
fn_clang_manual_droidian_gcc_vars() {
    ## TODO: review if still needed
    CLANG_PATH="/usr/lib/llvm-android-${CLANG_VERSION}/bin"
    export PATH="${CLANG_PATH}:$PATH"
}
fn_clang_manual_lineage_gcc_vars() {
    ## TODO: review if still needed
    #CLANG_PATH="$ROOTDIR/android_prebuilts_clang_kernel_linux-x86_clang-r416183b/bin"
    export PATH=$PATH:$ROOTDIR/build-tools/linux-x86/bin:$ROOTDIR/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9/aarch64-linux-android/bin:$ROOTDIR/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9/bin::$ROOTDIR/android_prebuilts_tools-lineage/linux-x86/bin
}

fn_kernel_info_vars() {
    export ARCH=$(cat "${KERNEL_DIR}/debian/kernel-info.mk" | grep "KERNEL_ARCH" | awk '{print $3}')
    export ARCH_HOST=$(cat "${KERNEL_DIR}/debian/kernel-info.mk" | grep "DEB_BUILD_ON" | awk '{print $3}')
    ## CLANG_VERSION requires a same name var in kernel-info.mk
    CLANG_VERSION="$(cat "${KERNEL_DIR}/debian/kernel-info.mk" | grep "^CLANG_VERSION = " | awk '{print $3}')"
    BUILD_PATH="$(cat "${KERNEL_DIR}/debian/kernel-info.mk" | grep "^BUILD_PATH = " | awk '{print $3}')"
    CLANG_CUSTOM="$(cat "${KERNEL_DIR}/debian/kernel-info.mk" | grep "^CLANG_CUSTOM = " | awk '{print $3}')"
    CLANG_CUSTOM_URL="$(cat "${KERNEL_DIR}/debian/kernel-info.mk" | grep "^CLANG_CUSTOM_URL = " | awk '{print $3}')"
    CLANG_CUSTOM_BRANCH="$(cat "${KERNEL_DIR}/debian/kernel-info.mk" | grep "^CLANG_CUSTOM_BRANCH = " | awk '{print $3}')"
}

fn_clang_manual_vars() {
    ## Clang version vars
    # CLANG_VERSION="6.0-4691093"
    # CLANG_VERSION="9.0-r353983c"
    CLANG_VERSION="10.0-r370808"
    # CLANG_VERSION="11.0-r383902" 
    # CLANG_VERSION="12.0-r416183b"
    # CLANG_VERSION="14.0-r450784d"
    # CLANG_VERSION="17.0-r487747"
    ## defconfig files vars
    DEFCONFIG_SOC="vendor/sm8150_defconfig"
    DEFCONFIG_MODEL="vayu_user_defconfig"
    DEFCONFIG_MAIN="vayu_main_defconfig"
    KERNEL_RELEASE="4.14-290-xiaomi-vayu"
    CROSS_TYPE="android" # | gnu
    # COMPILER="aarch64-linux-android-gcc-4.9"
    COMPILER=clang
    # CLANG_PATH="${CLANG_PATH}"
    # CLANG=$CLANG_PATH/clang
    #export PATH=${CLANG_PATH}:$PATH
    #export AS=aarch64-linux-${CROSS_TYPE}-as
    #export LD=aarch64-linux-${CROSS_TYPE}-ld
    #export AR=aarch64-linux-${CROSS_TYPE}-ar
    #export NM=aarch64-linux-${CROSS_TYPE}-nm
    # export OBJCOPY=aarch64-linux-${CROSS_TYPE}-objcopy
    # export OBJDUMP=aarch64-linux-${CROSS_TYPE}-objdump
    # export STRIP=aarch64-linux-${CROSS_TYPE}-strip
    export CROSS_COMPILE=aarch64-linux-${CROSS_TYPE}-
    export CROSS_COMPILE_ARM32=aarch64-linux-${CROSS_TYPE}-
    export CLANG_TRIPLE=aarch64-linux-gnu-

}


########################################
## Clang manual compilation functions ##
########################################
fn_mrproper() {
    make -C /buildd/sources ARCH=${ARCH} \
	O=/buildd/sources/out/KERNEL_OBJ \
	CC=$COMPILER \
	mrproper
}

fn_gen_main_defconfig() {
    ## Load soc_defconfig as base
    fn_set_defconfig "${DEFCONFIG_SOC}"
    echo "" && echo "soc_defconfig loaded" && echo ""
    ## Merge model_defconfig into .config
    /buildd/sources/scripts/kconfig/merge_config.sh \
	-O /buildd/sources/out/KERNEL_OBJ \
	-m /buildd/sources/out/KERNEL_OBJ/.config \
	 /buildd/sources/arch/${ARCH}/configs/"${DEFCONFIG_MODEL}"
    echo "" && echo "device_defconfig merged" && echo ""
    ## regenerate .config
    fn_olddefconfig
    echo "" &&  echo ".config regenerated" && echo ""
    ## copy .config to arch configs base dir
    cp -v  out/KERNEL_OBJ/.config \
        /buildd/sources/arch/${ARCH}/configs/${DEFCONFIG_MAIN}
}

fn_set_defconfig() {
    [ -z "${DEFCONFIG_MAIN}" ] && DEFCONFIG_MAIN=$1
    make -C /buildd/sources ARCH=${ARCH} \
	O=/buildd/sources/out/KERNEL_OBJ \
	CC=$COMPILER \
        ${DEFCONFIG_MAIN}
}

fn_merge_fragments() {
    /buildd/sources/scripts/kconfig/merge_config.sh \
	-O /buildd/sources/out/KERNEL_OBJ \
	-m /buildd/sources/out/KERNEL_OBJ/.config \
	/buildd/sources/droidian/vayu.config \
	/buildd/sources/droidian/common_fragments/droidian.config \
	/buildd/sources/droidian/common_fragments/halium.config
}

fn_menuconfig() {
    make -C /buildd/sources ARCH=${ARCH} \
	O=/buildd/sources/out/KERNEL_OBJ \
	CC=$COMPILER \
	KCONFIG_CONFIG=/buildd/sources/out/KERNEL_OBJ/.config menuconfig
}

fn_kconfig() {
    make -C /buildd/sources ARCH=${ARCH} \
	O=/buildd/sources/out/KERNEL_OBJ \
	CC=$COMPILER \
	KCONFIG_CONFIG=/buildd/sources/out/KERNEL_OBJ/.config kconfig
}

fn_listconfig() {
    make -C /buildd/sources ARCH=${ARCH} \
	O=/buildd/sources/out/KERNEL_OBJ \
	CC=$COMPILER \
	KCONFIG_CONFIG=/buildd/sources/out/KERNEL_OBJ/.config \
	./scripts/config --list-config | grep CGROUP_PIDS
}

fn_olddefconfig() {
    make -C /buildd/sources ARCH=${ARCH} \
	O=/buildd/sources/out/KERNEL_OBJ \
	CC=$COMPILER \
	KCONFIG_CONFIG=/buildd/sources/out/KERNEL_OBJ/.config olddefconfig
}

fn_savedefconfig() {
    cp /buildd/sources/out/KERNEL_OBJ/.config.old \
       /buildd/sources/out/KERNEL_OBJ/.config
    make -C /buildd/sources ARCH=${ARCH} \
	O=/buildd/sources/out/KERNEL_OBJ \
	CC=$COMPILER \
	KCONFIG_CONFIG=/buildd/sources/out/KERNEL_OBJ/.config savedefconfig
}

fn_build_kernel_clang_manual() {
    make -C /buildd/sources ARCH=${ARCH} \
     KERNELRELEASE=${KERNEL_RELEASE} \
     LLVM=1 LLVM_IAS=1 \
     -j8 \
     O=/buildd/sources/out/KERNEL_OBJ \
     CC=$COMPILER
     # CXX=clang++ \
}

###########################################
## Droidian releng compilation functions ##
###########################################
fn_invert_PATH_kernel_snippet() {
    ## NOT USED
    ## Patch releng kernel-snippet.mk
    ## To use the lineage toolchain, the FULL_PATH var needs to be defined with the PATH var at the beguin
    sed -i 's|FULL_PATH = $(BUILD_PATH):$(CURDIR)/debian/path-override:${PATH}|FULL_PATH = ${PATH}:$(BUILD_PATH):$(CURDIR)/debian/path-override|g' /usr/share/linux-packaging-snippets/kernel-snippet.mk
}

fn_build_kernel_droidian_releng() {
    ## Reconf PATH in kernel snippet (if using custom gcc)
    ## Pre compile configs

    ## Remove python x86 from control for a arm64 host
#    if [ "${ARCH_HOST}" == "arm64" ]; then
#        sed -i '/android-platform-prebuilts-python-linux-x86-2.7.5,/d' /usr/share/linux-packaging-snippets/control.in
#    fi
    ## Droidian official configs
    chmod +x /buildd/sources/debian/rules
    cd /buildd/sources
    rm -f debian/control
    debian/rules debian/control
    ## Call releng
    RELENG_HOST_ARCH=${ARCH} releng-build-package
}

fn_patch_file_arr_line_num_reference() {
    is_patched=$(grep "${arr_lines_to_add[0]}" "${path}/${file}")
    [ -n "${is_patched}" ] && echo "skipping" && return

    num_line_reference=$(grep -n "${patch_line_reference}" ${path}/${file} | awk -F':' '{print $1}')
    num_line_start=$((num_line_reference + start_relative))
    for line in "${arr_lines_to_add[@]}"; do
        sed -i "${num_line_start}a ${line}" "${path}/${file}"
        num_line_start=$((num_line_start + 1))
    done
    ## Add a blank line after last line
    sed -i "${num_line_start}a\

    " "${path}/${file}"
}

fn_releng_tools_cherry_berb_mods() {
    ## Patch releng-tools with some berbascum mods on development
    ## Git config
    git config --global user.email "build@local.lan"
    git config --global user.name "build"
    ## First clone the upstream
    rm -rf /tmp/releng-tools
    cd /tmp
    git clone -b droidian https://github.com/droidian-releng/releng-tools
    cd releng-tools
    git remote add origin-berb https://github.com/berbascum/releng-tools
    git fetch origin-berb
    ## Cherry-pick "berb-debug" commit:
       # [releng-tools] debug: Add some messages to show info about branches/tags
    commit_2_cherry="9c713bbfb172c519a4ec555eda0db63b8ca3e02a"
    ## commit_2_cherry="9553301851220fc4493cab22ad8ab5c83b07b3c8"
    git cherry-pick ${commit_2_cherry}
    if [ "$?" -eq "0" ]; then
        echo "Cherry-pick OK"
    else
        abort "Cherry-pick FAILED"
    fi
    ## Cherry-pick "tag-argument" commit:
       # [releng-tools] tar-argument: Add support for supplying a tag as build_package argument
    commit_2_cherry="ce4b8444a8921f3923ae0d2acad4fbaf40495145"
    ## commit_2_cherry="4e61f8d8fb43b775689a19d10cdc10c42bcbb5e8"
    git cherry-pick ${commit_2_cherry}
    if [ "$?" -eq "0" ]; then
        echo "Cherry-pick OK"
    else
        abort "Cherry-pick FAILED"
    fi
    ## Cherry-pick "clang-custom-support-DEV"
       # [releng-tools] clang-custom-support: DEVELOP: Add support for supplying a tag as build_package argument
    commit_2_cherry="0fddd47bcbd3534a02ced392a5c676b6d701b5f3"
    git cherry-pick ${commit_2_cherry}
    if [ "$?" -eq "0" ]; then
        echo "Cherry-pick OK"
    else
        abort "Cherry-pick FAILED"
    fi

    ## Update the system releng scripts
    cat build_package.sh > /usr/lib/releng-tools/build_package.sh
    cat build_changelog.py > /usr/lib/releng-tools/build_changelog.py
}

fn_kernel_snippet_main_wget() {
    ## Get unofficial-berb kernel snippets mods
    wget -O /usr/share/linux-packaging-snippets/kernel-snippet.mk https://raw.githubusercontent.com/berbascum/linux-packaging-snippets/refs/heads/feature/clang-conf-advanced/kernel-snippet.mk
    #### cp -v debian/kernel-snippet-berb.mk /usr/share/linux-packaging-snippets/kernel-snippet.mk
}

fn_kernel_snippets_clang() {
    ## Get clang kernel-snippets from berb-git
    wget -O /usr/share/linux-packaging-snippets/kernel-snippet-clang-conf-advanced.mk https://raw.githubusercontent.com/berbascum/linux-packaging-snippets/refs/heads/feature/clang-conf-advanced/kernel-snippet-clang-conf-advanced.mk
    wget -O /usr/share/linux-packaging-snippets/kernel-snippet-clang-clean-deb-toolchain.mk https://raw.githubusercontent.com/berbascum/linux-packaging-snippets/refs/heads/feature/clang-conf-advanced/kernel-snippet-clang-clean-deb-toolchain.mk
    wget -O /usr/share/linux-packaging-snippets/kernel-snippet-clang-versions.mk https://raw.githubusercontent.com/berbascum/linux-packaging-snippets/refs/heads/feature/clang-conf-advanced/kernel-snippet-clang-versions.mk
}

fn_kernel_snippets_extra_frag_extended_wget() {
    wget -O /usr/share/linux-packaging-snippets/kernel-snippet-extra-fragments-extended.mk https://raw.githubusercontent.com/berbascum/linux-packaging-snippets/refs/heads/feature/extra-frags-extended/kernel-snippet-extra-fragments-extended.mk
    file="kernel-snippet.mk"
    path="/usr/share/linux-packaging-snippets"
    patch_line_reference="ifdef KERNEL_CONFIG_EXTRA_FRAGMENTS"
    add_line1="include /usr/share/linux-packaging-snippets/kernel-snippet-extra-fragments-extended.mk"
    ## Add lines 2 lines (n;n;) after match
    ## Adding more lines
    #    a ${add_line1}
    #    a ${add_line2}
    is_patched=$(grep "${add_line1}" ${path}/${file})
    [ -n "${is_patched}" ] && return

    sed -i "/^${patch_line_reference}$/{
        n;n;
        a ""
        a ${add_line1}
    }" "${path}/${file}"
}

fn_kernel_snippet_kernel_release_info_extended_wget() {
    ## Add the previous kernel developer at the KERNEL_RELEASE's end
#    sed -i "s/^KERNEL_RELEASE = \$(KERNEL_BASE_VERSION)-\$(DEVICE_VENDOR)-\$(DEVICE_MODEL)/KERNEL_RELEASE = \$(KERNEL_BASE_VERSION)-\$(VARIANT)-\$(KERNEL_DEVELOPER_NAME)-\$(DEVICE_VENDOR)-\$(DEVICE_MODEL)-\$(KBUILD_DROIDIAN_VERSION)/g" /usr/share/linux-packaging-snippets/kernel-snippet.mk
    ## Get the control override snippet
    wget -O /usr/share/linux-packaging-snippets/control-override-kernel-release-extended.mk https://raw.githubusercontent.com/berbascum/linux-packaging-snippets/refs/heads/feature/kernel-release-extended/control-override-kernel-release-extended.mk
    #### cp -v debian/control-override-kernel-release-extended.mk /usr/share/linux-packaging-snippets/

    ## Patch kernel-snippet to include a control
    ## override snippet for custom kernel name
    ## start relative: "-" before, "+" after
    start_relative="-1"
    patch_line_reference='debian.*control:'
    file="kernel-snippet.mk"
    path="/usr/share/linux-packaging-snippets"
    arr_lines_to_add=(
        '# control override for enabling kernel developer name in kernel name'
        'ifdef KERNEL_DEVELOPER_NAME'
        'include /usr/share/linux-packaging-snippets/kernel-snippet-control-override-developer-name.mk'
        'endif'
    )
    ## Disable patching kernel-snippet, the snippet
    ## is included in debian/rules instead
    #fn_patch_file_arr_line_num_reference
}

#fn_enable_ccache

## Custom lineage build tools
# fn_install_lineage_toolchains
   ## Need to define paths in kernel-info.mk

if [ "$1" == "releng" ]; then
#   fn_install_prereqs_kernel_build
       ## DONE in the docker image
    ## Install/Upgrade Droidian build tools
    fn_install_prereqs_droidian_tools
    # Get kernel-snippet main from berb-git
    fn_kernel_snippets_main_wget
    ## Get clang kernel-snippets from berb-git
    fn_kernel_snippets_clang
    ## Update releng build_package to last unofficial testing
    fn_releng_tools_cherry_berb_mods
    # Get kernel-snippet extra fragments extended
    fn_kernel_snippets_extra_frag_extended_wget
    # Get kernel-snippet kernel release info extended
    fn_kernel_snippet_kernel_release_info_extended_wget
    #
#    sed -i 's/CROSS_COMPILE_ARM32/CROSS_COMPILE_COMPAT/g' /usr/share/linux-packaging-snippets/kernel-snippet.mk
    #
#   fn_install_prereqs_droidian_kernel_info
    fn_kernel_info_vars
    ## Install clang custom if enabled in kernel-info.mk
    if [ "${CLANG_CUSTOM}" -eq "1" ]; then
        fn_install_clang_custom
    fi
    fn_build_kernel_droidian_releng
    #
#    sed -i 's/CROSS_COMPILE_ARM32/CROSS_COMPILE_COMPAT/g' /usr/share/linux-packaging-snippets/kernel-snippet.mk   #
elif [ "$1" == "clang" ]; then
#   fn_install_prereqs_kernel_build
    #
#    fn_install_prereqs_droidian_kernel_info
    fn_clang_manual_vars
    fn_clang_manual_droidian_gcc_vars
#    fn_clang_manual_lineage_gcc_vars
    fn_mrproper
#    fn_menuconfig
#    fn_gen_main_defconfig
#    fn_set_defconfig
#    fn_merge_fragments
#    fn_olddefconfig
#    fn_savedefconfig
    #### fn_build_kernel_clang_manual
else
    echo
    echo "Please type \"releng\" or \"clang\""
fi
