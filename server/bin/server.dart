import 'dart:io';
import 'dart:convert';

// Simple local API server for products with CORS enabled.
// Endpoints:
// - GET    /products           -> returns list of products (array)
// - POST   /products           -> creates product, returns created JSON
// - PUT    /products/{id}      -> updates product, returns updated JSON
// - DELETE /products/{id}      -> deletes product, returns 204
// Also handles CORS preflight (OPTIONS).

Future<void> main(List<String> args) async {
  final port = _readPort(args) ?? 8080;
  final productsStore = ProductsStore(
    dataFile: File('server/data/products.json'),
    fallbackAsset: File('assets/data/products.json'),
  );
  await productsStore.init();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Products API server running at http://localhost:$port');
  await for (final req in server) {
    _addCorsHeaders(req.response);
    try {
      await _route(req, productsStore);
    } catch (e, st) {
      stderr.writeln('Error: $e\n$st');
      req.response.headers.contentType = ContentType.json;
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.write(jsonEncode({'error': e.toString()}));
      await req.response.close();
    }
  }
}

int? _readPort(List<String> args) {
  for (final a in args) {
    if (a.startsWith('--port=')) {
      final v = int.tryParse(a.split('=')[1]);
      if (v != null) return v;
    }
  }
  return null;
}

Future<void> _route(HttpRequest req, ProductsStore store) async {
  final segments = req.uri.pathSegments;
  final method = req.method.toUpperCase();

  // CORS preflight
  if (method == 'OPTIONS') {
    req.response.statusCode = HttpStatus.noContent;
    await req.response.close();
    return;
  }

  if (segments.isEmpty) {
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
    return;
  }

  if (segments[0] != 'products') {
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
    return;
  }

  // /products
  if (segments.length == 1) {
    switch (method) {
      case 'GET':
        final items = store.list();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(items));
        await req.response.close();
        return;
      case 'POST':
        final body = await utf8.decoder.bind(req).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final created = store.create(decoded);
        req.response.headers.contentType = ContentType.json;
        req.response.statusCode = HttpStatus.created;
        req.response.write(jsonEncode(created));
        await req.response.close();
        return;
      default:
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
    }
  }

  // /products/{id}
  if (segments.length == 2) {
    final id = segments[1];
    switch (method) {
      case 'PUT':
        final body = await utf8.decoder.bind(req).join();
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final updated = store.update(id, decoded);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(updated));
        await req.response.close();
        return;
      case 'DELETE':
        store.delete(id);
        req.response.statusCode = HttpStatus.noContent;
        await req.response.close();
        return;
      default:
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
        return;
    }
  }

  req.response.statusCode = HttpStatus.notFound;
  await req.response.close();
}

void _addCorsHeaders(HttpResponse resp) {
  resp.headers.set('Access-Control-Allow-Origin', '*');
  resp.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  resp.headers.set('Access-Control-Allow-Headers', 'Content-Type');
}

class ProductsStore {
  ProductsStore({required this.dataFile, required this.fallbackAsset});

  final File dataFile;
  final File fallbackAsset;
  late List<Map<String, dynamic>> _items;

  Future<void> init() async {
    if (await dataFile.exists()) {
      _items = await _readFile(dataFile);
      return;
    }
    if (await fallbackAsset.exists()) {
      _items = await _readFile(fallbackAsset);
      await _writeFile(dataFile, _items);
      return;
    }
    _items = <Map<String, dynamic>>[];
    await _writeFile(dataFile, _items);
  }

  List<Map<String, dynamic>> list() => List<Map<String, dynamic>>.from(_items);

  Map<String, dynamic> create(Map<String, dynamic> product) {
    final id = (product['id'] as String?) ?? 'p_${DateTime.now().millisecondsSinceEpoch}';
    final created = Map<String, dynamic>.from(product)..['id'] = id;
    _items.add(created);
    _persist();
    return created;
  }

  Map<String, dynamic> update(String id, Map<String, dynamic> product) {
    final idx = _items.indexWhere((e) => e['id'] == id);
    if (idx == -1) {
      throw StateError('Product not found: $id');
    }
    final updated = Map<String, dynamic>.from(product)..['id'] = id;
    _items[idx] = updated;
    _persist();
    return updated;
  }

  void delete(String id) {
    _items.removeWhere((e) => e['id'] == id);
    _persist();
  }

  Future<List<Map<String, dynamic>>> _readFile(File f) async {
    final raw = await f.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>();
    }
    if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      return (decoded['items'] as List).cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  void _persist() {
    _writeFile(dataFile, _items);
  }

  Future<void> _writeFile(File f, List<Map<String, dynamic>> items) async {
    final encoder = const JsonEncoder.withIndent('  ');
    await f.create(recursive: true);
    await f.writeAsString(encoder.convert(items));
  }
}