import 'package:bett_box/features/chains/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('chain snapshot YAML preserves rules, providers and scalar types', () {
    final config = <String, dynamic>{
      'proxies': [
        {
          'name': '香港 🇭🇰 → 出口',
          'password': 'true\n# not a comment',
          'port': 443,
          'udp': true,
          'dialer-proxy': '入口',
        },
      ],
      'proxy-groups': [
        {'name': 'Smart', 'type': 'smart', 'proxies': ['香港 🇭🇰 → 出口']},
      ],
      'proxy-providers': {
        'yes': {'type': 'http', 'url': 'https://example.com/sub?a=1&b=2'},
      },
      'rules': ['DOMAIN,example.com,Smart', 'MATCH,DIRECT'],
      'null': 'null',
      '0123': '0123',
      'empty': <String, dynamic>{},
    };
    expect(loadYaml(encodeChainProfile(config)), equals(config));
    expect(loadYaml(encodeChainProfile({})), isEmpty);
  });
}
