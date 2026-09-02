// Parses the `flutter build apk --analyze-size` JSON (the same analysis the
// DevTools "Size" page consumes) and prints how many bytes the
// `package:hintful` subtree contributes to a release Android build (release
// builds tree-shake, so the node is exactly hintful's code that survived).
// Prints a human line plus one machine-readable sample for
// tool/check_goldens.dart.
//
// Usage: dart run tool/native_size_parse.dart <size-analysis.json>
// Exit codes: 0 ok, 1 hintful node missing/unreadable.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/native_size_parse.dart <size-analysis.json>');
    exit(2);
  }
  final dynamic doc;
  try {
    doc = jsonDecode(File(args[0]).readAsStringSync());
  } on Exception catch (e) {
    stderr.writeln('FAIL: cannot read analysis JSON: $e');
    exit(1);
  }
  final package = _find(doc as Map<String, dynamic>, 'package:hintful');
  if (package == null) {
    stderr.writeln('FAIL: package:hintful node not found in analysis tree');
    exit(1);
  }
  final size = _totalOf(package);
  stdout.writeln('native_size: hintful contributes $size bytes (AOT, release)');
  stdout.writeln('HINTFUL_BENCH_JSON:{"metric":"native_size","value":$size}');
}

Map<String, dynamic>? _find(Map<String, dynamic> node, String name) {
  if (node['n'] == name) return node;
  for (final child in (node['children'] as List?) ?? const []) {
    final found = _find(child as Map<String, dynamic>, name);
    if (found != null) return found;
  }
  return null;
}

int _totalOf(Map<String, dynamic> node) {
  final v = node['value'];
  var sum = v is int ? v : 0;
  for (final child in (node['children'] as List?) ?? const []) {
    sum += _totalOf(child as Map<String, dynamic>);
  }
  return sum;
}