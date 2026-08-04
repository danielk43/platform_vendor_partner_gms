# Android Mobile Services

This is a collection of FOSS APKs, coupled with the respective Makefiles for an
easy integration in the Android build system.

To include them in your build, add a repo manifest file to include this repository as `vendor/partner_gms` and set
`WITH_GMS` to `true` when building.

For only open source apks in this fork `gms.mk` is used by default.
Or create a custom makefile and set `GMS_MAKEFILE` to your makefile name.

Example manifest:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project path="vendor/partner_gms" name="danielk43/platform_vendor_partner_gms" remote="github" revision="main" />
</manifest>
```

Note 1. If you encounter problems related to APK / app signing when using these components you may need to add the following line in the Android.mk for the component in question:
```
LOCAL_REPLACE_PREBUILT_APK_INSTALLED := $(LOCAL_PATH)/$(LOCAL_MODULE).apk
```
Such problems can occur when
* the app / APK is resigned with your keys; (this should not happen if the line LOCAL_CERTIFICATE := PRESIGNED is included in the app makefile)
* the app / APK signatures are 'stripped` during the during the deodexing phase of the build. For some apps the deodexed app ends up unsigned, and so will not run.

---------------

The included APKs are:
 * MicroG apks (binaries sourced from [here](https://github.com/microg))
   * GmsCore: the main component of microG, a FOSS reimplementation of the Google Play Services
   * FakeStore: an empty package that mocks the existence of the Google Play Store
   * GsfProxy: a GmsCore proxy for legacy GCM compatibility
 * Open Source apks
   * AuroraStore: an alternate to Google's Play Store (binaries sourced from [here](https://gitlab.com/AuroraOSS/AuroraStore/-/releases))
   * Obtainium: allows you to install and update Open-Source Apps directly (binaries sourced from [here](https://github.com/ImranR98/Obtainium/releases))
   * PdfViewer: a simple Android PDF viewer (binaries sourced from [here](https://github.com/GrapheneOS/PdfViewer/releases))

These are official unmodified prebuilt binaries, signed by the corresponding developers. They
are not tracked in this repository: `vendorsetup.sh` fetches each one from the latest upstream
release at envsetup time and rejects it unless its signing certificate matches the pinned hash.

microG is installed **unprivileged**, in `/product/app` rather than `/product/priv-app`.
Signature spoofing keys off the signing certificate rather than privilege, so no
`privapp-permissions` entry is needed; runtime permissions come from `default-permissions-*.xml`,
which works for non-privileged apps. The trade-off is that microG cannot register as a network
location provider, since `INSTALL_LOCATION_PROVIDER` is `signature|privileged`.
