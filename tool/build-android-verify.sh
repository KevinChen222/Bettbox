#!/usr/bin/env bash
# Verify a Smart release APK without modifying it.
set -euo pipefail

apk=${1:?APK path required}
build_tools="${ANDROID_SDK_ROOT:?Android SDK required}/build-tools/36.0.0"
"$build_tools/apksigner" verify "$apk"
[[ "$("$build_tools/aapt2" dump packagename "$apk")" == com.kevinchen222.bettbox.smart ]]
python3 - "$apk" <<'PY'
from pathlib import Path
from sys import argv
from zipfile import ZipFile

with ZipFile(argv[1]) as apk:
    names = apk.namelist()
    native_libraries = [name for name in names if name.startswith('lib/') and name.endswith('.so')]
    if ({name.split('/')[1] for name in native_libraries} != {'arm64-v8a'}
            or 'lib/arm64-v8a/libmeta.so' not in native_libraries):
        raise SystemExit('Smart APK must contain libmeta.so and only arm64-v8a native libraries')
    if apk.read('assets/flutter_assets/NOTICE') != Path('NOTICE').read_bytes():
        raise SystemExit('APK NOTICE differs from the root NOTICE')
PY
