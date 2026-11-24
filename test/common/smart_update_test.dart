import 'package:bett_box/common/identity.dart';
import 'package:bett_box/common/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the Smart identity keeps the existing data and binary names', () {
    expect(AppIdentity.packageId, 'com.vela');
    expect(AppIdentity.displayName, 'Vela');
    expect(AppIdentity.dataDirName, 'Bettbox');
    expect(AppIdentity.mainExecutableName, 'Bettbox');
    expect(AppIdentity.coreExecutableName, 'BettboxCore');
  });

  test('the updater only offers newer Smart releases from the fork', () {
    const prefix = 'https://github.com/KevinChen222/Bettbox/releases';
    expect(appUpdater.releaseUrl, prefix);
    expect(appUpdater.releaseFeedUrl, '$prefix.atom');
    expect(
      appUpdater.releaseApiUrl,
      'https://api.github.com/repos/KevinChen222/Bettbox/releases?per_page=10',
    );
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

  test('the updater discovers newer test and formal releases from feed and API', () {
    const atomFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>tag:github.com,2008:Repository/1/smart-v1.19.10-20261123.1</id>
    <link rel="alternate" type="text/html" href="https://github.com/KevinChen222/Bettbox/releases/tag/smart-v1.19.10-20261123.1"/>
    <title>Bettbox Smart 1.19.10 · 2026-11-23.1 · test</title>
  </entry>
  <entry>
    <id>tag:github.com,2008:Repository/1/smart-v1.19.9-20261121.1</id>
    <link rel="alternate" type="text/html" href="https://github.com/KevinChen222/Bettbox/releases/tag/smart-v1.19.9-20261121.1"/>
    <title>Bettbox Smart 1.19.9 · 2026-11-21.1</title>
  </entry>
  <entry>
    <id>tag:github.com,2008:Repository/1/v1.20.0</id>
    <link rel="alternate" type="text/html" href="https://github.com/KevinChen222/Bettbox/releases/tag/v1.20.0"/>
    <title>Upstream v1.20.0</title>
  </entry>
</feed>
''';
    final feedTags = appUpdater.parseReleaseFeedTags(atomFeed);
    expect(feedTags, [
      'smart-v1.19.10-20261123.1',
      'smart-v1.19.9-20261121.1',
      'v1.20.0',
    ]);
    expect(
      appUpdater.selectLatestReleaseTag(feedTags, '1.19.9', '2026112101'),
      'smart-v1.19.10-20261123.1',
    );
    expect(
      appUpdater.selectLatestReleaseTag(feedTags, '1.19.10', '2026112301'),
      isNull,
    );

    final apiTags = appUpdater.parseReleaseApiTags([
      {'tag_name': 'smart-v1.19.11-20261124.1', 'draft': true, 'prerelease': true},
      {'tag_name': 'smart-v1.19.10-20261123.2', 'draft': false, 'prerelease': true},
      {'tag_name': 'smart-v1.19.10-20261123.1', 'draft': false, 'prerelease': false},
      {'tag_name': 'v2.0.0', 'draft': false, 'prerelease': false},
    ]);
    expect(apiTags, [
      'smart-v1.19.10-20261123.2',
      'smart-v1.19.10-20261123.1',
      'v2.0.0',
    ]);
    expect(
      appUpdater.selectLatestReleaseTag(apiTags, '1.19.10', '2026112301'),
      'smart-v1.19.10-20261123.2',
    );
    expect(appUpdater.parseReleaseFeedTags('<broken'), isEmpty);
  });
}
