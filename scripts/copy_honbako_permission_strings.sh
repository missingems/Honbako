#!/bin/sh
set -eu

# Shared legacy InfoPlist.strings are excluded from the Honbako target. Install
# only these target-specific translations after Copy Bundle Resources, before
# signing, so the system never uses the legacy localized display name.
HONBAKO_PERMISSION_SOURCE="${SRCROOT}/AppStore/permission-strings"
HONBAKO_TRANSLATION_SOURCE="${SRCROOT}/Aidoku/App/Resources/Localization"
HONBAKO_RESOURCE_DESTINATION="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
case "${HONBAKO_RESOURCE_DESTINATION}/" in
    *.app/*) ;;
    *) echo "Honbako localization destination must be an assembled app bundle." >&2; exit 1 ;;
esac
for HONBAKO_LOCALE in en ja zh-Hans zh-Hant; do
    mkdir -p "${HONBAKO_RESOURCE_DESTINATION}/${HONBAKO_LOCALE}.lproj"
    /usr/bin/plutil -convert binary1 -o "${HONBAKO_RESOURCE_DESTINATION}/${HONBAKO_LOCALE}.lproj/InfoPlist.strings" "${HONBAKO_PERMISSION_SOURCE}/${HONBAKO_LOCALE}.strings"
    /usr/bin/plutil -convert binary1 -o "${HONBAKO_RESOURCE_DESTINATION}/${HONBAKO_LOCALE}.lproj/Localizable.strings" "${HONBAKO_TRANSLATION_SOURCE}/${HONBAKO_LOCALE}.lproj/Localizable.strings"
done
/usr/bin/plutil -convert binary1 -o "${HONBAKO_RESOURCE_DESTINATION}/en.lproj/Localizable.stringsdict" "${HONBAKO_TRANSLATION_SOURCE}/en.lproj/Localizable.stringsdict"

# Remove only stale generated translation tables from older incremental builds.
# Keep unknown resources and the legacy app target untouched.
for HONBAKO_OLD_LOCALE in "${HONBAKO_RESOURCE_DESTINATION}"/*.lproj; do
    [ -d "${HONBAKO_OLD_LOCALE}" ] || continue
    case "${HONBAKO_OLD_LOCALE##*/}" in
        en.lproj|ja.lproj|zh-Hans.lproj|zh-Hant.lproj|Base.lproj) continue ;;
    esac
    rm -f "${HONBAKO_OLD_LOCALE}/Localizable.strings" "${HONBAKO_OLD_LOCALE}/Localizable.stringsdict" "${HONBAKO_OLD_LOCALE}/InfoPlist.strings"
    rmdir "${HONBAKO_OLD_LOCALE}" 2>/dev/null || true
done
