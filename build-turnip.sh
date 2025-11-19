#!/bin/bash -e

# Fixed versions and configurations
DROID_VER="9"
API_VER="28"
NDK_VER="29"
DEV_VER="25.3"
DRM_VER="2.4.128"
ISODATE=$(date +"%Y%m%d")
PKG_CONFIG_PATH_ORIG=$PKG_CONFIG_PATH
export CFLAGS="-O3"
export CXXFLAGS="-O3"

# Version sets: MESA_VER PKG_VER DATE
versions=(
# The following will not compile with modern Android NDKs
#    "21.2.6 6 20211124"
#    "21.3.9 9 20220608"
#    "22.0.5 5 20220601"
#    "22.1.7 7 20220922"
    "22.2.4 4 20221116"
    "22.3.7 7 20230308"
    "23.0.4 4 20230530"
    "23.1.9 9 20231004"
    "23.2.1 1 20230928"
    "23.3.6 6 20240215"
    "24.0.9 9 20240606"
    "24.1.7 7 20240829"
    "24.2.8 8 20241128"
    "24.3.4 4 20250122"
    "25.0.7 7 20250528"
    "25.1.9 9 20250827"
    "25.2.7 7 20251112"
    "25.3.0 0 20251114"
    "STAGING $DEV_VER staging-$DEV_VER 1.4"
    "HEAD main $ISODATE"
)

# Required packages for building the turnip driver
deps="meson ninja patchelf unzip curl pip flex bison zip"

# Android NDK
ndkver="https://dl.google.com/android/repository/android-ndk-r$NDK_VER-linux.zip"
ndkdir="android-ndk-r$NDK_VER"

# Colors for terminal output
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

workdir="$(pwd)/turnip_workdir"
magiskdir="$workdir/turnip_module"

# Turnip variables
DRIVER_FILE="vulkan.turnip.so"
META_FILE="meta.json"

clear

# Clean work directory if it exists
if [ -d "$workdir" ]; then
    echo "Work directory already exists. Cleaning before proceeding..." $'\n'
    rm -rf "$workdir"
    sleep 2
fi

echo "Checking system for required dependencies..."

# Check for required dependencies 
for deps_chk in $deps; do
    sleep 0.25
    if command -v "$deps_chk" >/dev/null 2>&1; then
        echo -e "$green - $deps_chk found $nocolor"
    else
        echo -e "$red - $deps_chk not found, cannot continue. $nocolor"
        deps_missing=1
    fi
done

# Install missing dependencies automatically
if [ "$deps_missing" == "1" ]; then
    echo "Missing dependencies, installing them now..." $'\n'
    sudo apt install -y meson patchelf unzip curl python3-pip flex bison zip python3-mako python-is-python3 &> /dev/null
fi

clear

# Download Android NDK
echo "Downloading Android NDK r$NDK_VER..." $'\n'
curl $ndkver --output "$ndkdir".zip

# Loop through each version set
for version in "${versions[@]}"; do
    # Extract version values
    read -r MESA_VER PKG_VER DATE <<< "$version"

    echo -e "${green}Building Mesa $MESA_VER...${nocolor}"

    # Mesa
    if [[ "$MESA_VER" == "HEAD" ]]; then
        mesaver="https://gitlab.freedesktop.org/mesa/mesa/-/archive/main/mesa-main.zip"
        mesadir="mesa-main"
    elif [[ "$MESA_VER" == "STAGING" ]]; then
        mesaver="https://gitlab.freedesktop.org/mesa/mesa/-/archive/staging/$PKG_VER/mesa-staging-$PKG_VER.zip"
        mesadir="mesa-staging-$PKG_VER"
    else 
        mesaver="https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-$MESA_VER/mesa-mesa-$MESA_VER.zip"
        mesadir="mesa-mesa-$MESA_VER"
    fi

    ZIP_FILE="Turnip-$MESA_VER-EMULATOR.zip"


    echo "Creating and entering the work directory..." $'\n'
    mkdir -p "$workdir" && cd "$_"

    clear

    echo "Extracting Android NDK r$NDK_VER..." $'\n'
    unzip "../$ndkdir".zip &> /dev/null

    # Download Mesa source
    echo "Downloading Mesa $MESA_VER source ..." $'\n'
    curl $mesaver --output "$mesadir".zip 

    clear

    echo "Extracting Mesa $MESA_VER source..." $'\n'
    unzip "$mesadir".zip &> /dev/null
    cd $mesadir

    # Set NDK r$NDK_VER Clang bin directory
    ndk_bin="$workdir/$ndkdir/toolchains/llvm/prebuilt/linux-x86_64/bin"

    # Set toolchain variables
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export RANLIB=llvm-ranlib
    export STRIP=llvm-strip
    export OBJDUMP=llvm-objdump
    export OBJCOPY=llvm-objcopy
    export LDFLAGS="-fuse-ld=lld"

    # Retrieve Vulkan Version
    vkxml="src/vulkan/registry/vk.xml"
    VULKAN_VER=""
    if [[ -f "$vkxml" ]]; then
        # Extract patch (VK_HEADER_VERSION)
        vkpatch=$(grep -A 1 '<type api="vulkan" category="define"' "$vkxml" | grep -oP '#define <name>VK_HEADER_VERSION</name>\s*\K\d+')
    
        # Extract variant, major, minor from VK_HEADER_VERSION_COMPLETE
        read vkvariant vkmajor vkminor <<< $(grep -A 1 '<type api="vulkan" category="define"' "$vkxml" | grep -oP '#define <name>VK_HEADER_VERSION_COMPLETE</name> <type>VK_MAKE_API_VERSION</type>\(\K[0-9]+,\s*[0-9]+,\s*[0-9]+' | sed 's/,//g')

        if [[ -n "$vkpatch" && -n "$vkmajor" && -n "$vkminor" ]]; then
            VULKAN_VER="${vkmajor}.${vkminor}.${vkpatch}"
        fi
    fi

    echo "Vulkan Version: $VULKAN_VER" $'\n'

    # Retrieve and verify Mesa Version
    version_file="VERSION"
    CODE_VER=""
    if [[ -f "$version_file" ]]; then
       read CODE_VER < "$version_file"
    fi

    echo "Mesa Version: $CODE_VER" $'\n'

    # Create a temporary directory for fake cc/c++
    mkdir -p /tmp/fake-cc

    # Create symbolic links to NDK-Clang
    ln -sf "$ndk_bin/clang" /tmp/fake-cc/cc
    ln -sf "$ndk_bin/clang++" /tmp/fake-cc/c++

    # Prepend both fake-cc and NDK bin to PATH
    export PATH="/tmp/fake-cc:$ndk_bin:$PATH"

    echo "Creating Meson cross file..." $'\n'
    cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk_bin/llvm-ar'
c = ['ccache', '$ndk_bin/aarch64-linux-android$API_VER-clang']
cpp = ['ccache', '$ndk_bin/aarch64-linux-android$API_VER-clang++', '--start-no-unused-arguments', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++', '--end-no-unused-arguments', '-Wno-error=c++11-narrowing']
c_ld = '$ndk_bin/ld.lld'
cpp_ld = '$ndk_bin/ld.lld'
strip = '$ndk_bin/aarch64-linux-android-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=NDKDIR/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

cat <<EOF >"native.txt"
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

echo "Generating build files..." $'\n'

# The fredreno-kmds flag does not exist in Mesa < 23.2.0
if [ "$(printf "%s\n%s" "$MESA_VER" "23.2.0" | sort -V | head -n1)" != "23.2.0" ]; then
    # libdrm
    echo "Downloading libdrm..."
    drmver="https://gitlab.freedesktop.org/mesa/libdrm/-/archive/libdrm-$DRM_VER/libdrm-libdrm-$DRM_VER.zip"
    drmdir="libdrm-libdrm-$DRM_VER"
    curl $drmver --output "$drmdir".zip &> /dev/null
    ls -l
    echo "Extracting libdrm-$DRM_VER..."
    unzip "$drmdir".zip

    echo "Building libdrm-$DRM_VER..."
    cd $drmdir
    mkdir -p build-libdrm

CC=clang CXX=clang++ CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" meson setup build-libdrm \
    --cross-file "$workdir/$mesadir/android-aarch64.txt" \
    --native-file "$workdir/$mesadir/native.txt" \
    --prefix="$workdir/$ndkdir/toolchains/llvm/prebuilt/linux-x86_64" \
    -Dbuildtype=release \
    -Db_lto=true &> meson_log

    ninja -C build-libdrm/ install
    cd ..

    echo "Building libdrm-$DRM_VER complete"

    export PKG_CONFIG_PATH=$workdir/$ndkdir/toolchains/llvm/prebuilt/linux-x86_64/lib/pkgconfig:$PKG_CONFIG_PATH

CC=clang CXX=clang++ CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" meson setup build-android-aarch64 \
    --cross-file "$workdir/$mesadir/android-aarch64.txt" \
    --native-file "$workdir/$mesadir/native.txt" \
    -Dbuildtype=release \
    -Dplatforms=android \
    -Dplatform-sdk-version=$API_VER \
    -Dandroid-stub=true \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Db_lto=true \
    -Degl=disabled \
    -Dstrip=true &> $workdir/meson_log
else
CC=clang CXX=clang++ CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" meson setup build-android-aarch64 \
    --cross-file "$workdir/$mesadir/android-aarch64.txt" \
    --native-file "$workdir/$mesadir/native.txt" \
    -Dbuildtype=release \
    -Dplatforms=android \
    -Dplatform-sdk-version=$API_VER \
    -Dandroid-stub=true \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl \
    -Db_lto=true \
    -Degl=disabled \
    -Dstrip=true
fi

# Compile build files using Ninja
echo "Compiling build files..." $'\n'
ninja -C build-android-aarch64 

echo "Using patchelf to match .so name..." $'\n'
cp "$workdir"/"$mesadir"/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so "$workdir"
cd "$workdir"



if ! [ -a libvulkan_freedreno.so ]; then
    echo -e "$red Build failed! libvulkan_freedreno.so not found $nocolor" && exit 1
fi

echo "Prepare magisk module structure..." $'\n'
p1="system/vendor/lib64/hw"
mkdir -p "$magiskdir/$p1"
cd "$magiskdir"

echo "Copy necessary files from the work directory..." $'\n'
cp "$workdir"/libvulkan_freedreno.so "$workdir"/vulkan.adreno.so
cp "$workdir"/vulkan.adreno.so "$magiskdir/$p1"

meta="META-INF/com/google/android"
mkdir -p "$meta"

# Create update-binary
cat <<EOF >"$meta/update-binary"
#!/sbin/sh

#################
# Initialization
#################

umask 022

# echo before loading util_functions
ui_print() { echo "\$1"; }

require_new_magisk() {
  ui_print "*******************************"
  ui_print " Please install Magisk v25.2+! "
  ui_print "*******************************"
  exit 1
}

#########################
# Load util_functions.sh
#########################

OUTFD=\$2
ZIPFILE=\$3

mount /data 2>/dev/null

[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ \$MAGISK_VER_CODE -lt 25200 ] && require_new_magisk

install_module
exit 0
EOF

# Create updater-script
cat <<EOF >"$meta/updater-script"
#MAGISK
EOF

cat <<EOF >"uninstall.sh"
find /data/user_de/*/*/*cache/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*graphitecache*" -exec rm -rf {} +
find /data/data/* -iname "*gpucache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*shader*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*graphitecache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*gpucache*" -exec rm -rf {} +
EOF

cat <<EOF >"module.prop"
id=turnip-mesa
name=Freedreno Turnip Vulkan Driver $CODE_VER
version=$MESA_VER
versionCode=$DATE
author=RTIANGHA
description=Turnip is an open-source vulkan driver for devices with Adreno 6xx-8xx GPUs.
updateJson=https://raw.githubusercontent.com/rtiangha/Mesa-Turnip-Builder/refs/heads/stable/update.json
EOF

cat <<EOF >"customize.sh"
MODVER=\`grep_prop version \$MODPATH/module.prop\`
MODVERCODE=\`grep_prop versionCode \$MODPATH/module.prop\`

ui_print ""
ui_print "Version=\$MODVER "
ui_print "MagiskVersion=\$MAGISK_VER"
ui_print ""
ui_print "Freedreno Turnip Vulkan Driver -RTIANGHA"
ui_print "Adreno Driver Support Group - Telegram"
ui_print ""
sleep 1.25

ui_print ""
ui_print "Checking Device info ..."
sleep 1.25

[ \$(getprop ro.system.build.version.sdk) -lt $API_VER ] && echo "Android $DROID_VER is required! Aborting ..." && abort
echo ""
echo "Everything looks fine .... proceeding"
ui_print ""
ui_print "Installing Driver Please Wait ..."
ui_print ""

sleep 1.25
set_perm_recursive \$MODPATH/system 0 0 755 u:object_r:system_file:s0
set_perm_recursive \$MODPATH/system/vendor 0 2000 755 u:object_r:vendor_file:s0
set_perm \$MODPATH/system/vendor/lib64/hw/vulkan.adreno.so 0 0 0644 u:object_r:same_process_hal_file:s0

ui_print ""
ui_print " Cleaning GPU Cache ... Please wait!"
find /data/user_de/*/*/*cache/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*graphitecache*" -exec rm -rf {} +
find /data/data/* -iname "*gpucache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*shader*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*graphitecache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*gpucache*" -exec rm -rf {} +

ui_print ""
ui_print "- Gpu Cache Cleared ..."
ui_print ""

ui_print "Driver installed Successfully"
sleep 1.25

ui_print ""
ui_print "All done, Please REBOOT device"
ui_print ""
ui_print "BY: @RTIANGHA"
ui_print ""
EOF

echo "Packing driver files into Magisk/KSU module ..." $'\n'
zip -r $workdir/Turnip-$MESA_VER-MAGISK-KSU.zip * &> /dev/null
if ! [ -a $workdir/Turnip-$MESA_VER-MAGISK-KSU.zip ]; then
    echo -e "$red-Packing failed!$nocolor" && exit 1
else
    clear

    echo " Its time to create Turnip build for EMULATOR"

    sleep 2

    cd ..

    mv vulkan.adreno.so vulkan.turnip.so

# Create meta.json file for turnip emulator
 cat <<EOF > "$META_FILE"
{
  "schemaVersion": 1,
  "name": "Freedreno Turnip Driver $MESA_VER",
  "description": "Mesa $CODE_VER compiled using Android NDK r$NDK_VER with $CXXFLAGS",
  "author": "rtiangha",
  "packageVersion": "$PKG_VER",
  "vendor": "Mesa3D",
  "driverVersion": "Vulkan $VULKAN_VER",
  "minApi": $API_VER,
  "libraryName": "vulkan.turnip.so"
}
EOF

# Zip the turnip .so file and meta.json file
    if ! zip "$ZIP_FILE" "$DRIVER_FILE" "$META_FILE" > /dev/null 2>&1; then
    echo -e "$red Error: Zipping driver files failed. $nocolor"
    exit 1
    fi

    clear

    echo -e "$green-All done, you can take your drivers from here;$nocolor" $'\n'
    echo $workdir/Turnip-$MESA_VER-MAGISK-KSU.zip $'\n'
    echo $workdir/Turnip-$MESA_VER-EMULATOR.zip $'\n'
    echo -e "$green Build Finished :). $nocolor" $'\n'

    # Copy Turnip files to GitHub Actions artifacts directory
    mkdir -p ../artifacts
    cp $workdir/Turnip-*.zip ../artifacts

    # Cleanup 
    rm "$DRIVER_FILE" "$META_FILE"
    
    # Clean up fake-cc directory and symbolic links on exit
    rm -rf /tmp/fake-cc/cc
    rm -rf /tmp/fake-cc/c++
    rm -rf /tmp/fake-cc

    # Cleanup workdir
    cd ..
    rm -rf $workdir
fi

# Restore original PKG_CONFIG_PATH
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH_ORIG
done

echo -e "${green}All builds completed. Artifacts are in the artifacts directory.${nocolor}" $'\n'

