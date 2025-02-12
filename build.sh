#!/bin/bash
echo ""
echo "Pixel Experience 12 Treble Buildbot"
echo "ATTENTION: this script syncs repo on each run"
echo "Executing in 5 seconds - CTRL-C to exit"
echo ""
sleep 5

# Abort early on error
set -eE
trap '(\
echo;\
echo \!\!\! An error happened during script execution;\
echo \!\!\! Please check console output for bad sync,;\
echo \!\!\! failed patch application, etc.;\
echo\
)' ERR

START=`date +%s`
BUILD_DATE="$(date +%Y%m%d)"
WITHOUT_CHECK_API=true
BL=$PWD/treble_build_pe
BD=$HOME/builds

if [ ! -d .repo ]
then
    echo "Initializing PE workspace"
    repo init --depth=1 --no-repo-verify -u git://github.com/PixelOS-Pixelish/manifest -b twelve -g default,-mips,-darwin,-notdefault
    echo ""

    echo "Preparing local manifest"
    mkdir -p .repo/local_manifests
    cp $BL/manifest.xml .repo/local_manifests/pixel.xml
    echo ""
fi

echo "Syncing repos"
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j8
echo ""

echo "Setting up build environment"
source build/envsetup.sh &> /dev/null
mkdir -p $BD
echo ""

echo "Applying prerequisite patches"
bash $BL/apply-patches.sh $BL prerequisite
echo ""

echo "Applying PHH patches"
cd device/phh/treble
cp $BL/pe.mk .
bash generate.sh pe
cd ../../..
bash $BL/apply-patches.sh $BL phh
echo ""

echo "Applying personal patches"
bash $BL/apply-patches.sh $BL personal
echo ""

buildTrebleApp() {
    cd treble_app
    bash build.sh release
    cp TrebleApp.apk ../vendor/hardware_overlay/TrebleApp/app.apk
    cd ..
}

buildVariant() {
    lunch treble_arm64_bvS-userdebug
    make installclean
    make -j$(nproc --all) systemimage
    make vndk-test-sepolicy
    mv $OUT/system.img $BD/system-treble_arm64_bvS.img
}

buildSlimVariant() {
    wget https://gist.github.com/ponces/891139a70ee4fdaf1b1c3aed3a59534e/raw/slim.patch -O /tmp/slim.patch
    (cd vendor/gapps && git am /tmp/slim.patch)
    make -j$(nproc --all) systemimage
    (cd vendor/gapps && git reset --hard HEAD~1)
    mv $OUT/system.img $BD/system-treble_arm64_bvS-slim.img
}

buildVndkliteVariant() {
    cd sas-creator
    sudo bash lite-adapter.sh 64 $BD/system-treble_arm64_bvS.img
    cp s.img $BD/system-treble_arm64_bvS-vndklite.img
    sudo rm -rf s.img d tmp
    cd ..
}

generatePackages() {
    xz -cv $BD/system-treble_arm64_bvS.img -T0 > $BD/PixelExperience_arm64-ab-12.0-$BUILD_DATE-UNOFFICIAL.img.xz
    xz -cv $BD/system-treble_arm64_bvS-vndklite.img -T0 > $BD/PixelExperience_arm64-ab-vndklite-12.0-$BUILD_DATE-UNOFFICIAL.img.xz
    xz -cv $BD/system-treble_arm64_bvS-slim.img -T0 > $BD/PixelExperience_arm64-ab-slim-12.0-$BUILD_DATE-UNOFFICIAL.img.xz
    rm -rf $BD/system-*.img
}

buildTrebleApp
buildVariant
buildSlimVariant
buildVndkliteVariant
generatePackages
generateOtaJson

END=`date +%s`
ELAPSEDM=$(($(($END-$START))/60))
ELAPSEDS=$(($(($END-$START))-$ELAPSEDM*60))
echo "Buildbot completed in $ELAPSEDM minutes and $ELAPSEDS seconds"
echo ""
