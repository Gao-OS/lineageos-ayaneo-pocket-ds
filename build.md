# Build Record

Date: 2026-04-28

Target:

- Product: `lineage_pocket_ds`
- Release: `ap2a`
- Variant: `userdebug`
- Command: `./scripts/build.sh --build --jobs 16`

## Attempts

### Attempt 1

Command:

```sh
./scripts/build.sh --build --jobs 16 2>&1 | tee build-attempt-1.log
```

Result: failed before lunch.

Failure:

```text
build/envsetup.sh: line 21: TOP: unbound variable
```

Fix: `scripts/build.sh` uses `set -u`, but LineageOS `build/envsetup.sh` expects some variables to be unset while it initializes. Temporarily disabled nounset around the `source build/envsetup.sh` call.

### Attempt 2

Command:

```sh
./scripts/build.sh --build --jobs 16 2>&1 | tee build-attempt-2.log
```

Result: failed during `lunch`.

Failure:

```text
build/envsetup.sh: line 191: BUILD_VAR_CACHE_READY: unbound variable
```

Fix: Android build helper functions also rely on unset variables after `envsetup.sh` is sourced. Kept nounset disabled through `lunch` and `mka bacon`, then restored it after the build command returns.

### Attempt 3

Command:

```sh
./scripts/build.sh --build --jobs 16 2>&1 | tee build-attempt-3.log
```

Result: success.

Duration reported by Android build:

```text
#### build completed successfully (12:16 (mm:ss)) ####
```

## Notes

Warnings observed but not build-blocking:

- `This device does not have Treble enabled. This is unsafe.`
- Prebuilt kernel warning from `vendor/lineage/build/tasks/kernel.mk`.
- Duplicate install-rule warnings for several VINTF manifests and vendor libraries.
- `lpmake` printed `Invalid sparse file format at header magic` while building `super.img`, but the image was written successfully.
- OTA packaging warned about missing build props for a few partitions and empty boot ramdisk extraction; packaging completed successfully.

## Output

Primary output:

```text
out/target/product/pocket_ds/lineage-21.0-20260428-UNOFFICIAL-pocket_ds.zip
```

Release copy:

```text
out/release/lineage-21.0-20260428-UNOFFICIAL-pocket_ds.zip
```

Size:

```text
1.6G
```

SHA256:

```text
675fdc21f8351e79004db78f08d06ebdadb410e73f4f591656213b25fd739fab
```

## Build Script Change

`scripts/build.sh` now disables `set -u` while invoking LineageOS build environment functions:

- `source build/envsetup.sh`
- `lunch lineage_pocket_ds-ap2a-userdebug`
- `mka bacon -j16`

This is required because the upstream Android shell helpers intentionally inspect unset variables during normal operation.
