#!/bin/bash
#for github actions
set -eu
if command -v sudo; then
    sudo apt-get update
else
    apt-get update
    apt-get install -y sudo
fi
source submodules.conf
#submodules
bash -x get-submodules.sh
Initsystem() {
    sudo apt install -y \
        libssl-dev \
        python2 \
        libc6-dev \
        binutils \
        libgcc-11-dev \
        zip
    # fix aarch64-linux-android-4.9-gcc 从固定的位置获取python
    test -f /usr/bin/python || ln /usr/bin/python2 /usr/bin/python
    export PATH="${GITHUB_WORKSPACE}"/android_prebuilts_build-tools-"${PREBUILTS_HASH}"/path/linux-x86/:$PATH
    export PATH="${GITHUB_WORKSPACE}"/android_prebuilts_build-tools-"${PREBUILTS_HASH}"/linux-x86/bin/:$PATH
    export PATH="${GITHUB_WORKSPACE}"/$LLVM_TAG/bin:"$PATH"
    export PATH="${GITHUB_WORKSPACE}"/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9-"${AARCH64_GCC_HASH}"/bin:"$PATH"
    export PATH="${GITHUB_WORKSPACE}"/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9-"${ARM_GCC_HASH}"/bin:"$PATH"

}

Patch_su() {
    # fix pm command/path_umount and KernelSU module activation issue/
    patch -p1 < ../kernel_patch/fix_patch.diff
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
    # use kprobe hook
    for config in CONFIG_KPROBES CONFIG_HAVE_KPROBES CONFIG_KPROBE_EVENTS; do
      grep -q "^$config=y" arch/arm64/configs/lineage_oneplus5_defconfig || echo "$config=y" >> arch/arm64/configs/lineage_oneplus5_defconfig
    done
}

Releases() {
    # 复制 Image.gz-dtb 到 AnyKernel3 目录
    cp -f out/arch/arm64/boot/Image.gz-dtb ../AnyKernel3-${ANYKERNEL_HASH}/Image.gz-dtb

    # 上传 Image.gz 和 Image.lz4
    UPLOAD_FILES=()
    for img in Image.gz Image.lz4; do
        if [ -f out/arch/arm64/boot/${img} ]; then
            cp out/arch/arm64/boot/${img} "${GITHUB_WORKSPACE}/releases/${img}"
            UPLOAD_FILES+=("${GITHUB_WORKSPACE}/releases/${img}")
            echo "✔ copied ${img}"
        fi
    done

    # 生成构建信息
    md5=$(md5sum ../AnyKernel3-${ANYKERNEL_HASH}/Image.gz-dtb)
    md5tab=${md5:0:5}
    kernelversion=$(head -n 3 "${GITHUB_WORKSPACE}/android_kernel_oneplus_msm8998-${KERNEL_HASH}/Makefile" | awk '{print $3}' | tr -d '\n')
    buildtime=$(date +%Y%m%d-%H%M%S)

    cat > "${GITHUB_WORKSPACE}/AnyKernel3-${ANYKERNEL_HASH}/buildinfo" <<EOF
buildtime ${buildtime}
Image.gz-dtb hash ${md5}
EOF

    # 设置 kernel-images artifact 上传信息（带 md5 和时间戳）
    echo "filename1=${1}-${kernelversion}_images_${buildtime}_${md5tab}" >> "${GITHUB_WORKSPACE}/env.add"
    echo "filepath1=$(printf "%s\n" "${UPLOAD_FILES[@]}")" >> "${GITHUB_WORKSPACE}/env.add"

    # 设置 AnyKernel3 artifact 上传信息
    echo "filename2=${1}-${kernelversion}_testbuild_${buildtime}_${md5tab}" >> "${GITHUB_WORKSPACE}/env.add"
    echo "filepath2=${GITHUB_WORKSPACE}/AnyKernel3-${ANYKERNEL_HASH}" >> "${GITHUB_WORKSPACE}/env.add"
}

#使用指定的anykernel配置文件
cp "${GITHUB_WORKSPACE}"/anykernel.sh "${GITHUB_WORKSPACE}"/AnyKernel3-${ANYKERNEL_HASH}/anykernel.sh

Initsystem
test -d releases || mkdir releases
# ls -lh
cd ./android_kernel_oneplus_msm8998-"${KERNEL_HASH}"/

##su patch
Patch_su
#Write flag
test -f localversion || touch localversion
cat >localversion <<EOF
-0
EOF
#llvm dc build
make -j"$(nproc --all)" O=out lineage_oneplus5_defconfig \
    ARCH=arm64 \
    SUBARCH=arm64 \
    LLVM=1

(make -j"$(nproc --all)" O=out \
    ARCH=arm64 \
    SUBARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-android- \
    CROSS_COMPILE_ARM32=arm-linux-androideabi- \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    LLVM=1 &&
    Releases "op5lin22.1-ksu") || (echo "su build error" && exit 1)
