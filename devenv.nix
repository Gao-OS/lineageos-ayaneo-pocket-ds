{ pkgs, lib, ... }:

{
  # Android / LineageOS build environment for Ayaneo Pocket DS

  packages = with pkgs; [
    # Android repo tool
    git-repo

    # Android platform tools (adb, fastboot)
    android-tools

    # Sparse image conversion
    simg2img

    # Filesystem tools
    e2fsprogs

    # Build essentials
    python3
    jdk17
    git-lfs
    ccache
    gnumake
    zip
    unzip
    curl
    bc
    rsync

    # Binary analysis
    xxd
    binutils       # provides strings, objdump (used by patch-kernelsu.sh)
    file           # file type detection (required by patch-kernelsu.sh)

    # Compression / archive tools (used by patch-kernelsu.sh and unpack-boot.sh)
    cpio
    lz4
    zstd

    # XML parsing (for rawprogram XML)
    xmlstarlet

    # Build dependencies commonly needed by AOSP
    ncurses5
    bison
    flex
    openssl
    zlib
    libxml2
    m4
    fontconfig
    freetype

    # Script linting
    shellcheck
    jq

    # NOTE: The following tools are NOT available in nixpkgs and must be
    # built from AOSP source or obtained as pre-built binaries:
    #   - unpackbootimg / mkbootimg  (from system/tools/mkbootimg)
    #   - lpunpack / lpmake          (from system/extras/partition_tools)
    #
    # After `repo sync`, build them with:
    #   cd <aosp_root>
    #   source build/envsetup.sh
    #   m mkbootimg unpack_bootimg lpunpack lpmake
    #
    # Or install from a pre-built release:
    #   pip install mkbootimg  (Python implementation)
    #
    # The scripts in scripts/ will check for these tools and provide
    # instructions if they're missing.
  ];

  env = {
    # Android build requires C locale
    LC_ALL = "C";

    # Enable ccache for faster rebuilds
    USE_CCACHE = "1";
    CCACHE_EXEC = "${pkgs.ccache}/bin/ccache";

    # Allow building with missing dependencies (common during bringup)
    ALLOW_MISSING_DEPENDENCIES = "true";

    # Java home for Android build
    JAVA_HOME = "${pkgs.jdk17.home}";
  };

  enterShell = ''
    echo ""
    echo "================================================"
    echo "  LineageOS 21 — Ayaneo Pocket DS Build Environment"
    echo "================================================"
    echo ""
    echo "  Target:  Ayaneo Pocket DS (Qualcomm TurboX C8550 / SM8750)"
    echo "  Base:    LineageOS 21 (Android 14)"
    echo "  Java:    $(java -version 2>&1 | head -1)"
    echo "  ccache:  $CCACHE_EXEC"
    echo ""
    echo "  Quick Start:"
    echo "    1. repo init -u https://github.com/LineageOS/android.git -b lineage-21.0 --git-lfs"
    echo "    2. cp local_manifests/* .repo/local_manifests/"
    echo "    3. repo sync -c -j$(nproc) --force-sync --no-tags"
    echo "    4. source build/envsetup.sh"
    echo "    5. lunch lineage_pocket_ds-userdebug"
    echo "    6. mka bacon"
    echo ""
    echo "  Or run: ./scripts/build.sh --all"
    echo ""
    echo "  NOTE: mkbootimg, unpackbootimg, lpunpack, lpmake are built"
    echo "  from AOSP source after repo sync. See devenv.nix for details."
    echo "================================================"
    echo ""

    # Ensure JAVA_HOME is on PATH
    export PATH="${pkgs.jdk17}/bin:$PATH"
  '';
}
