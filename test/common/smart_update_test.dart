import 'package:bett_box/common/identity.dart';
import 'package:bett_box/common/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Smart identity keeps the existing data and binary names', () {
    expect(AppIdentity.packageId, 'com.kevinchen222.bettbox.smart');
    expect(AppIdentity.displayName, 'Bettbox Smart');
    expect(AppIdentity.dataDirName, 'Bettbox');
    expect(AppIdentity.mainExecutableName, 'Bettbox');
    expect(AppIdentity.coreExecutableName, 'BettboxCore');
  });

  test('the updater only offers newer Smart releases from the fork', () {
    const prefix = 'https://github.com/KevinChen222/Bettbox/releases';
    expect(appUpdater.releaseUrl, '$prefix/latest');
    expect(
      appUpdater.releaseTagUrl('smart-v1.19.9-20261121.2'),
      '$prefix/tag/smart-v1.19.9-20261121.2',
    );
    final expectations = {
      'smart-v1.19.9-20261121.2': true,
      'smart-v1.19.9-20261121.1': false,
      'smart-v1.19.9-20261120.3': false,
      'smart-v1.19.10-20261120.1': true,
      'smart-v1.19.8-20261122.1': false,
      'v1.20.0': false,
      'smart-v1.20.0-20261122.0': false,
      'smart-v1.20.0-20261122.100': false,
    };
    for (final entry in expectations.entries) {
      expect(
        appUpdater.hasReleaseUpdate(entry.key, '1.19.9', '2026112101'),
        entry.value,
        reason: entry.key,
      );
    }
  });
}
