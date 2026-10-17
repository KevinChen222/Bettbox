#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source tool/linux-env.sh

commit="$(git rev-parse HEAD)"
version="$(awk '/^version:/ {print $2}' pubspec.yaml)"
output_dir="$PWD/dist/smart-local/$commit"
check_dir="$PWD/.test/linux-local/$commit"
mkdir -p "$output_dir" "$check_dir"

flutter pub get
dart run build_runner build -d
cp lib/features/chains/LICENSE assets/data/avalon-chain-LICENSE.txt
cp NOTICE assets/data/avalon-chain-NOTICE.txt
dart setup.dart linux --arch amd64 --out core
dart pub global activate --source path plugins/flutter_distributor/packages/flutter_distributor
dart pub global run flutter_distributor:main package --skip-clean --platform linux --targets deb --description x64 --build-target-platform linux-x64 --build-dart-define=APP_ENV=pre

package="dist/Bettbox-${version%%+*}-linux-x64.deb"
[[ -n "$package" && -f "$package" ]]
cp "$package" "$output_dir/Bettbox-smart-linux-x64.deb"
package="$output_dir/Bettbox-smart-linux-x64.deb"
[[ "$(dpkg-deb -f "$package" Package)" == bettbox-smart ]]
[[ "$(dpkg-deb -f "$package" Architecture)" == amd64 ]]
[[ "$(dpkg-deb -f "$package" Version)" == "$version" ]]
dpkg-deb -x "$package" "$check_dir/bundle"
dpkg-deb -e "$package" "$check_dir/control"
bundle="$check_dir/bundle/usr/share/Bettbox"
[[ -x "$bundle/Bettbox" && -x "$bundle/BettboxCore" && ! -u "$bundle/BettboxCore" ]]
dpkg-deb -c "$package" | awk '$NF == "./usr/share/Bettbox/BettboxCore" { if ($1 != "-rwxr-xr-x" || $2 != "root/root") exit 1; found = 1 } END { if (!found) exit 1 }'
grep -F 'cap_net_admin,cap_net_bind_service,cap_net_raw=+ep' "$check_dir/control/postinst"
dpkg-deb -f "$package" Depends | grep -F libcap2-bin
cmp linux/packaging/polkit/90-bettbox.rules "$check_dir/bundle/usr/share/polkit-1/rules.d/90-bettbox.rules"
cmp lib/features/chains/LICENSE "$bundle/data/flutter_assets/assets/data/avalon-chain-LICENSE.txt"
cmp NOTICE "$bundle/data/flutter_assets/assets/data/avalon-chain-NOTICE.txt"
desktop-file-validate "$check_dir/bundle/usr/share/applications/Bettbox.desktop"
readelf -d "$bundle/lib/libdartjni.so" | grep -F '/usr/lib/jvm/java-17-openjdk-amd64/lib/server'
go version -m "$bundle/BettboxCore" | grep -F 'GOAMD64=v3'
for elf in "$bundle/Bettbox" "$bundle"/lib/*.so; do
  dependencies="$(ldd "$elf")"
  if [[ "$dependencies" == *'not found'* ]]; then
    printf '%s\n' "$dependencies" >&2
    exit 1
  fi
done
python3 - "$commit" "$version" "$package" <<'PY'
import datetime,hashlib,json,platform,subprocess,sys
from pathlib import Path
commit,version,package=sys.argv[1:]
info={
    'commit':commit,'version':version,'platform':platform.platform(),
    'osRelease':platform.freedesktop_os_release(),'coreGOAMD64':'v3',
    'flutter':subprocess.check_output(['flutter','--version'],text=True),
    'go':subprocess.check_output(['go','version'],text=True).strip(),
    'sha256':hashlib.sha256(Path(package).read_bytes()).hexdigest(),
    'packageChecks':'metadata, core permissions, capabilities installer, Polkit, license, NOTICE, JNI path, ELF dependencies',
    'createdAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
Path(package).with_name('linux-build-info.json').write_text(json.dumps(info,indent=2)+'\n')
PY
printf '\nDEB: %s\n' "$package"
sha256sum "$package"
