#!/bin/bash -e

# Fixed versions and configurations
DROID_VER="9";
API_VER="28";
NDK_VER="28b";
DEV_VER="25.1";
ISODATE=$(date +"%Y%m%d")

export CFLAGS="-O3"
export CXXFLAGS="-O3"

# Version sets: MESA_VER PKG_VER DATE
versions=(
# The following won't build due to:
#  Run-time dependency libdrm found: NO (tried pkgconfig)
#  meson.build:1760:13: ERROR: Dependency "libdrm" not found, tried pkgconfig
#    "21.2.6 6 20211124"
#    "21.3.9 9 20220608"
#    "22.0.5 5 20220601"
#    "22.1.7 7 20220922"
#    "22.2.4 4 20221116"
#    "22.3.7 7 20230308"
#    "23.0.4 4 20230530"
#    "23.1.9 9 20231004"
    "23.2.1 1 20230928"
    "23.3.6 6 20240215"
    "24.0.9 9 20240606"
    "24.1.7 7 20240829"
    "24.2.8 8 20241128"
    "24.3.4 4 20250122"
    "25.0.5 5 20250430"
    "25.1.0 0 20250507"
    "STAGING $DEV_VER staging-$DEV_VER 1.4"
    "HEAD main $ISODATE"
)

# Required packages for building the turnip driver
deps=(meson ninja patchelf unzip curl pip flex bison zip)

# Android NDK
ndk_url="https://dl.google.com/android/repository/android-ndk-r$NDK_VER-linux.zip"
ndk_dir="android-ndk-r$NDK_VER"

# Colors for terminal output
green='\033[0;32m';
red='\033[0;31m';
nocolor='\033[0m'

workdir="$(pwd)/turnip_workdir"
magiskdir="$workdir/turnip_module"

# Turnip variables
DRIVER_FILE="vulkan.turnip.so"
META_FILE="meta.json"

# --- Functions ---

# Clean work directory
clean_dir() { [ -d "$1" ] && { echo "Cleaning $1 ..."; rm -rf "$1"; }; }

# Check for required dependencies
check_deps() {

    echo "Checking system for required dependencies..."

    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 && echo -e "$green - $dep found $nocolor" || { echo -e "$red - $dep not found $nocolor"; missing+=("$dep"); }
    done

    # Install missing dependencies automatically
    if (( ${#missing[@]} )); then
        echo "Installing missing deps: ${missing[*]}"
        sudo apt install -y "${deps[@]}" python3-mako python-is-python3 &>/dev/null
    fi
}

# Create Meson cross compilation file
make_crossfile() {
    local ndk_bin="$1" out="$2"
    cat <<EOF >"$out"
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
}

make_nativefile() {
    local out="$1"
    cat <<EOF >"$out"
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
}

# Make magisk module files
make_magisk_module_files() {
    local magiskdir="$1" MESA_VER="$2" CODE_VER="$3" DATE="$4"
    local meta="$magiskdir/META-INF/com/google/android"
    mkdir -p "$meta"
    cat <<'EOF' >"$meta/update-binary"
#!/sbin/sh

#################
# Initialization
#################

umask 022
ui_print() { echo "$1"; }
require_new_magisk() {
  ui_print "*******************************";
  ui_print " Please install Magisk v25.2+! ";
  ui_print "*******************************";
  exit 1;
}

#########################
# Load util_functions.sh
#########################

OUTFD=$2
ZIPFILE=$3
mount /data 2>/dev/null
[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ $MAGISK_VER_CODE -lt 25200 ] && require_new_magisk
install_module
exit 0
EOF

# Create updater-script
    echo "#MAGISK" >"$meta/updater-script"
    cat <<'EOF' >"$magiskdir/uninstall.sh"
find /data/user_de/*/*/*cache/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*graphitecache*" -exec rm -rf {} +
find /data/data/* -iname "*gpucache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*shader*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*graphitecache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*gpucache*" -exec rm -rf {} +
EOF
    cat <<EOF >"$magiskdir/module.prop"
id=turnip-mesa
name=Freedreno Turnip Vulkan Driver $CODE_VER
version=$MESA_VER
versionCode=$DATE
author=RTIANGHA
description=Turnip is an open-source vulkan driver for devices with Adreno 6xx-8xx GPUs.
updateJson=https://raw.githubusercontent.com/rtiangha/Mesa-Turnip-Builder/refs/heads/stable/update.json
EOF
    cat <<EOF >"$magiskdir/customize.sh"
MODVER=\`grep_prop version \$MODPATH/module.prop\`
MODVERCODE=\`grep_prop versionCode \$MODPATH/module.prop\`

ui_print "";
ui_print "Version=\$MODVER ";
ui_print "MagiskVersion=\$MAGISK_VER"
ui_print "";
ui_print "Freedreno Turnip Vulkan Driver -RTIANGHA"
ui_print "Adreno Driver Support Group - Telegram";
ui_print "";
sleep 1.25

ui_print "";
ui_print "Checking Device info ...";
sleep 1.25

[ \$(getprop ro.system.build.version.sdk) -lt $API_VER ] && echo "Android $DROID_VER is required! Aborting ..." && abort
echo "";
echo "Everything looks fine .... proceeding";
ui_print "";
ui_print "Installing Driver Please Wait ...";
ui_print "";
sleep 1.25
set_perm_recursive \$MODPATH/system 0 0 755 u:object_r:system_file:s0
set_perm_recursive \$MODPATH/system/vendor 0 2000 755 u:object_r:vendor_file:s0
set_perm \$MODPATH/system/vendor/lib64/hw/vulkan.adreno.so 0 0 0644 u:object_r:same_process_hal_file:s0
ui_print "";
ui_print " Cleaning GPU Cache ... Please wait!"
find /data/user_de/*/*/*cache/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*shader*" -exec rm -rf {} +
find /data/data/* -iname "*graphitecache*" -exec rm -rf {} +
find /data/data/* -iname "*gpucache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*shader*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*graphitecache*" -exec rm -rf {} +
find /data_mirror/data*/*/*/*/* -iname "*gpucache*" -exec rm -rf {} +

ui_print "";
ui_print "- Gpu Cache Cleared ...";
ui_print "";

ui_print "Driver installed Successfully";
sleep 1.25

ui_print "";
ui_print "All done, Please REBOOT device";
ui_print "";
ui_print "BY: @RTIANGHA";
ui_print ""
EOF
}

# Make Turnip emulator driver json file
make_meta_json() {
    cat <<EOF >"$META_FILE"
{
  "schemaVersion": 1,
  "name": "Freedreno Turnip Driver $1",
  "description": "Mesa $2 compiled using Android NDK r$NDK_VER with $CXXFLAGS",
  "author": "rtiangha",
  "packageVersion": "$3",
  "vendor": "Mesa3D",
  "driverVersion": "Vulkan $4",
  "minApi": $API_VER,
  "libraryName": "vulkan.turnip.so"
}
EOF
}

# --- Main Script ---

# Clean work directory if it exists
clean_dir "$workdir"

# Check for required dependencies
check_deps

# Download Android NDK
echo "Downloading Android NDK r$NDK_VER..."
curl -L "$ndk_url" --output "$ndk_dir.zip"

# Loop through and compile each Mesa version set
for version in "${versions[@]}"; do
    read -r MESA_VER PKG_VER DATE <<<"$version"
    echo -e "${green}Building Mesa $MESA_VER...${nocolor}"

    # Mesa source URL and dir
    if [[ "$MESA_VER" == "HEAD" ]]; then
        mesaver="https://gitlab.freedesktop.org/mesa/mesa/-/archive/main/mesa-main.zip"; mesadir="mesa-main"
    elif [[ "$MESA_VER" == "STAGING" ]]; then
        mesaver="https://gitlab.freedesktop.org/mesa/mesa/-/archive/staging/$PKG_VER/mesa-staging-$PKG_VER.zip"; mesadir="mesa-staging-$PKG_VER"
    else
        mesaver="https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-$MESA_VER/mesa-mesa-$MESA_VER.zip"; mesadir="mesa-mesa-$MESA_VER"
    fi
    ZIP_FILE="Turnip-$MESA_VER-EMULATOR.zip"

    echo "Creating and entering the work directory..."
    mkdir -p "$workdir" && cd "$workdir"

    echo "Extracting Android NDK r$NDK_VER..."
    unzip -q "../$ndk_dir.zip"

    echo "Downloading Mesa $MESA_VER source ..."
    curl -L "$mesaver" --output "$mesadir.zip"

    echo "Extracting Mesa $MESA_VER source..."
    unzip -q "$mesadir.zip"

    cd "$mesadir"
    ndk_bin="$workdir/$ndk_dir/toolchains/llvm/prebuilt/linux-x86_64/bin"

    export PATH="/tmp/fake-cc:$ndk_bin:$PATH"
    mkdir -p /tmp/fake-cc
    ln -sf "$ndk_bin/clang" /tmp/fake-cc/cc
    ln -sf "$ndk_bin/clang++" /tmp/fake-cc/c++

    # Extract Mesa code version
    CODE_VER=$(<VERSION)

    # Extract Vulkan version
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

    echo "Mesa Version: $CODE_VER  Vulkan Version: $VULKAN_VER"

    echo "Creating Meson cross file..." $'\n'
    make_crossfile "$ndk_bin" "android-aarch64.txt"

    make_nativefile "native.txt"

    # Build flags
    build_args=(
        build-android-aarch64
        --cross-file "$workdir/$mesadir/android-aarch64.txt"
        --native-file "$workdir/$mesadir/native.txt"
        -Dbuildtype=release
        -Dplatforms=android
        -Dplatform-sdk-version=$API_VER
        -Dandroid-stub=true
        -Dgallium-drivers=
        -Dvulkan-drivers=freedreno
        -Db_lto=true
        -Degl=disabled
        -Dstrip=true
    )
    # Add freedreno-kmds if Mesa >= 23.2.0
    if [[ "$CODE_VER" =~ ^([0-9]+\.[0-9]+) ]] && (( $(echo "${BASH_REMATCH[1]} >= 23.2" | bc -l) )); then
        build_args+=( -Dfreedreno-kmds=kgsl )
    fi

    echo "Generating build files..."
    CC=clang CXX=clang++ CFLAGS="$CFLAGS" CXXFLAGS="$CXXFLAGS" meson setup "${build_args[@]}" &> $workdir/meson_log

    echo -e "${green}Building Mesa $MESA_VER...${nocolor}"

    ninja -C build-android-aarch64

    cp "$workdir/$mesadir/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so" "$workdir" || { echo -e "$red Build failed! $nocolor"; exit 1; }

    # Magisk Module
    mkdir -p "$magiskdir/system/vendor/lib64/hw"
    cp "$workdir"/libvulkan_freedreno.so "$workdir"/vulkan.adreno.so
    cp "$workdir"/vulkan.adreno.so "$magiskdir/system/vendor/lib64/hw/"
    make_magisk_module_files "$magiskdir" "$MESA_VER" "$CODE_VER" "$DATE"
    (cd "$magiskdir" && zip -qr "$workdir/Turnip-$MESA_VER-MAGISK-KSU.zip" .)

    # Emulator zip
    cd "$workdir"
    mv vulkan.adreno.so vulkan.turnip.so
    make_meta_json "$MESA_VER" "$CODE_VER" "$PKG_VER" "$VULKAN_VER"
    zip -q "$ZIP_FILE" "$DRIVER_FILE" "$META_FILE"

    # Copy artifacts
    mkdir -p ../artifacts
    cp Turnip-*.zip ../artifacts

    # Clean up
    rm -rf /tmp/fake-cc "$magiskdir" "$DRIVER_FILE" "$META_FILE"
    cd ..
    rm -rf "$workdir"

    echo -e "${green}Building Mesa $MESA_VER complete.${nocolor}\n"
done

echo -e "${green}All builds completed. Artifacts are in the artifacts directory.${nocolor}\n"
