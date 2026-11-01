import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/pi_upstreams.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// pi's models.json as it is set up.
Map<String, Object?> _pi() => {
  'providers': {
    'cctq': {
      'api': 'openai-responses',
      'apiKey': 'sk-cctq',
      'baseUrl': 'https://www.cctq.ai/v1',
      'models': [
        {
          'id': 'gpt-5.6-luna',
          'contextWindow': 258000,
          'maxTokens': 16384,
          'reasoning': true,
          'input': ['text', 'image'],
        },
        {'id': 'gpt-5.6-sol', 'input': ['text']},
      ],
    },
    'local': {
      'api': 'anthropic',
      'apiKey': 'sk-local',
      'baseUrl': 'http://localhost:8080',
      'models': [
        {'id': 'claude-haiku-4-5', 'contextWindow': 200000},
      ],
    },
    'chatgpt': {'api': 'codex', 'models': []},
    'weird': {'api': 'gemini', 'baseUrl': 'https://x.dev', 'models': []},
    'nowhere': {'api': 'anthropic', 'apiKey': 'sk-x', 'models': []},
  },
};

void main() {
  group('PiUpstreams.parse', () {
    test('each upstream pi sets up, with its key and models', () {
      final (:taken, :skipped) = PiUpstreams.parse(_pi());
      expect(taken.map((entry) => entry.upstream.name), ['cctq', 'local']);
      final cctq = taken.first;
      expect(cctq.upstream.protocol, ProviderProtocol.openaiResponses);
      expect(cctq.upstream.baseUrl, 'https://www.cctq.ai/v1');
      expect(cctq.upstream.key, 'sk-cctq');
      expect(cctq.models.map((model) => model.id), [
        'gpt-5.6-luna',
        'gpt-5.6-sol',
      ]);
      expect(cctq.models.first.contextWindow, 258000);
      expect(cctq.models.first.images, isTrue);
      expect(cctq.models.last.images, isFalse);
      expect(taken.last.upstream.protocol, ProviderProtocol.anthropic);
      // ChatGPT signs in with accounts; a protocol Settings → Models does
      // not speak; and one with no base URL to go to.
      expect(skipped, ['chatgpt', 'weird', 'nowhere']);
    });

    test('nothing to read: nothing taken', () {
      expect(PiUpstreams.parse(null).taken, isEmpty);
      expect(PiUpstreams.parse({'providers': 'no'}).taken, isEmpty);
    });
  });

  group('PiUpstreams.takeInto', () {
    late Directory dir;
    late File file;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('pi-upstreams');
      file = File('${dir.path}/models.json')
        ..writeAsStringSync(jsonEncode(_pi()));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('they are added with their keys, and their models offered', () async {
      final secrets = MemorySecretStore();
      final providers = ModelProviders.memory(secrets: secrets);
      final result = await PiUpstreams.takeInto(providers, file: file);

      expect(result.added, ['cctq', 'local']);
      expect(result.skipped, ['chatgpt', 'weird', 'nowhere']);
      final cctq = providers.providers.firstWhere((p) => p.name == 'cctq');
      expect(cctq.protocol, ProviderProtocol.openaiResponses);
      expect(cctq.enabledModels, hasLength(2));
      expect(await secrets.read(cctq.keyRef), 'sk-cctq');
      // Its models are the auxiliary model's to pick.
      expect(
        [
          for (final provider in providers.providers)
            for (final model in provider.enabledModels)
              modelRef(provider.id, model.id),
        ],
        contains(modelRef(cctq.id, cctq.enabledModels.first.id)),
      );
    });

    test('taken again: only what is new comes in, keys left as they are',
        () async {
      final secrets = MemorySecretStore();
      final providers = ModelProviders.memory(secrets: secrets);
      await PiUpstreams.takeInto(providers, file: file);
      final cctq = providers.providers.firstWhere((p) => p.name == 'cctq');

      // A model turned off here, a key of the user's, and one more in pi.
      await providers.save(
        cctq.copyWith(
          models: [
            cctq.models.first.copyWith(enabled: false),
            cctq.models.last,
          ],
        ),
      );
      await providers.setKey(cctq.id, 'sk-mine');
      final more = _pi();
      ((more['providers'] as Map)['cctq'] as Map)['models'] = [
        ...((more['providers'] as Map)['cctq'] as Map)['models'] as List,
        {'id': 'gpt-5.6-new'},
      ];
      file.writeAsStringSync(jsonEncode(more));

      final result = await PiUpstreams.takeInto(providers, file: file);
      expect(result.added, isEmpty);
      expect(result.updated, ['cctq']);
      final after = providers.providers.firstWhere((p) => p.name == 'cctq');
      expect(after.id, cctq.id);
      expect(after.models.map((model) => model.id), [
        'gpt-5.6-luna',
        'gpt-5.6-sol',
        'gpt-5.6-new',
      ]);
      // The one turned off stays off.
      expect(after.models.first.enabled, isFalse);
      expect(await secrets.read(after.keyRef), 'sk-mine');
      expect(providers.providers, hasLength(2));
    });

    test('no pi setup: says where it looked', () async {
      final providers = ModelProviders.memory();
      await expectLater(
        PiUpstreams.takeInto(
          providers,
          file: File('${dir.path}/nothing/models.json'),
        ),
        throwsA(isA<PiUpstreamsException>()),
      );
    });
  });
}
