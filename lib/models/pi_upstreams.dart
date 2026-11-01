// The upstreams pi is set up with, taken into Settings → Models: pi's own
// models.json lists each provider's protocol, base URL, key and models, and
// those are what its sessions run on. Taken here, the app's own small jobs
// (Polish, Translate, titles, commit messages) can ask them too, over HTTP,
// instead of the Claude Code Haiku they fall back to.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'model_provider.dart';
import 'model_providers.dart';
import 'upstream.dart';
import 'upstream_import.dart';

/// What taking pi's upstreams in did: [added] by name, [updated] (there
/// already, their models brought up to date), and [skipped] left out (a
/// protocol Settings → Models does not speak, ChatGPT's accounts, or no
/// base URL to go to).
class PiUpstreamsResult {
  const PiUpstreamsResult({
    this.added = const [],
    this.updated = const [],
    this.skipped = const [],
  });

  final List<String> added;
  final List<String> updated;
  final List<String> skipped;

  bool get nothing => added.isEmpty && updated.isEmpty;
}

/// pi's upstreams to read, or the reason there is none.
class PiUpstreamsException implements Exception {
  const PiUpstreamsException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract final class PiUpstreams {
  /// Where pi keeps its models.json: `PI_CODING_AGENT_DIR` as it is set,
  /// else `<home>/.pi/agent`.
  static File file({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final dir = switch (env['PI_CODING_AGENT_DIR']) {
      final String dir when dir.trim().isNotEmpty => dir.trim(),
      _ => p.join(env['HOME'] ?? '', '.pi', 'agent'),
    };
    return File(p.join(dir, 'models.json'));
  }

  /// The upstreams [json] (pi's models.json) sets up, each as an import
  /// makes it, with the key it has; and the names left out.
  static ({List<({UpstreamImport upstream, List<ProviderModel> models})> taken,
    List<String> skipped}) parse(Object? json) {
    final taken = <({UpstreamImport upstream, List<ProviderModel> models})>[];
    final skipped = <String>[];
    if (json is! Map) return (taken: taken, skipped: skipped);
    final providers = json['providers'];
    if (providers is! Map) return (taken: taken, skipped: skipped);
    for (final MapEntry(:key, :value) in providers.entries) {
      final name = '$key';
      if (value is! Map) {
        skipped.add(name);
        continue;
      }
      final protocol = switch (value['api']) {
        final String api =>
          _protocols.where((protocol) => protocol.id == api).firstOrNull,
        _ => null,
      };
      final baseUrl = switch (value['baseUrl']) {
        final String url when UpstreamUrls.parse(url) != null => url,
        _ => null,
      };
      if (protocol == null || baseUrl == null) {
        skipped.add(name);
        continue;
      }
      taken.add((
        upstream: UpstreamImport(
          name: name,
          protocol: protocol,
          baseUrl: baseUrl,
          key: switch (value['apiKey']) {
            final String key => key,
            _ => '',
          },
        ),
        models: _models(value['models']),
      ));
    }
    return (taken: taken, skipped: skipped);
  }

  /// Those of them [json] names, taken into [providers]: an upstream that
  /// is there already (the same protocol at the same base URL) only has its
  /// models brought up to date, its own settings and key left as they are.
  static Future<PiUpstreamsResult> takeInto(
    ModelProviders providers, {
    File? file,
  }) async {
    final source = file ?? PiUpstreams.file();
    final Object? json;
    try {
      json = jsonDecode(await source.readAsString());
    } on FileSystemException {
      throw PiUpstreamsException('No pi setup at ${source.path}');
    } on FormatException catch (error) {
      throw PiUpstreamsException('${source.path}: ${error.message}');
    }
    final (:taken, :skipped) = parse(json);
    final added = <String>[];
    final updated = <String>[];
    for (final (:upstream, :models) in taken) {
      final existing = upstream.existingIn(providers.providers);
      if (existing == null) {
        final id = providers.newId(upstream.name);
        await providers.save(
          upstream.toProvider(id).copyWith(models: models),
        );
        if (upstream.key.trim().isNotEmpty) {
          await providers.setKey(id, upstream.key);
        }
        added.add(upstream.name);
        continue;
      }
      // Its own are kept as they are: their settings, and the ones turned
      // off or dropped here stay that way.
      final known = {for (final model in existing.models) model.id};
      final fresh = [
        for (final model in models)
          if (!known.contains(model.id)) model,
      ];
      if (fresh.isEmpty) continue;
      await providers.save(
        existing.copyWith(models: [...existing.models, ...fresh]),
      );
      updated.add(existing.name);
    }
    return PiUpstreamsResult(added: added, updated: updated, skipped: skipped);
  }

  /// Those an upstream can come in with: not ChatGPT's, which signs in with
  /// accounts.
  static const _protocols = [
    ProviderProtocol.anthropic,
    ProviderProtocol.openaiChat,
    ProviderProtocol.openaiResponses,
  ];

  static List<ProviderModel> _models(Object? json) => [
    if (json is List)
      for (final model in json)
        if (model is Map)
          if (model['id'] case final String id when id.trim().isNotEmpty)
            ProviderModel(
              id: id.trim(),
              contextWindow: switch (model['contextWindow']) {
                final int tokens when tokens > 0 => tokens,
                _ => null,
              },
              images: switch (model['input']) {
                final List input => input.contains('image'),
                _ => true,
              },
            ),
  ];
}
