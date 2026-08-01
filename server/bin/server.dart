import 'dart:io';
import 'dart:convert';

/// Modular local API server for the interior design marketplace.
///
/// Endpoints:
///   /products     GET/POST         → list / create products
///   /products/{id} PUT/DELETE      → update / delete product
///   /orders       GET/POST         → list / create orders
///   /orders/{id}  PUT/DELETE       → update status / delete order
///   /categories   GET/POST         → list / create categories
///   /categories/{id} PUT/DELETE    → update / soft-delete category
///   /styles       GET/POST         → list / create styles
///   /styles/{id}  PUT/DELETE       → update / soft-delete style
///   /config       GET              → global configuration
///   /refunds/{id} PUT              → approve / reject refund
///
/// All endpoints return JSON. CORS enabled for all origins.

Future<void> main(List<String> args) async {
  final port = _readPort(args) ?? 8080;

  final stores = _Stores(
    products: ProductsStore(
      dataFile: File('server/data/products.json'),
      fallbackAsset: File('assets/data/products.json'),
    ),
    orders: JsonFileStore('server/data/orders.json'),
    categories: JsonFileStore('server/data/categories.json'),
    styles: JsonFileStore('server/data/styles.json'),
    config: JsonFileStore('server/data/config.json'),
  );

  await stores.initAll();

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Marketplace API server running at http://localhost:$port');
  stdout.writeln('  /products   /orders   /categories   /styles   /config   /refunds');

  await for (final req in server) {
    _addCorsHeaders(req.response);
    try {
      await _route(req, stores);
    } catch (e, st) {
      stderr.writeln('Error: $e\n$st');
      _jsonResponse(req.response, {'error': e.toString()},
          status: HttpStatus.internalServerError);
    }
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

int? _readPort(List<String> args) {
  for (final a in args) {
    if (a.startsWith('--port=')) {
      return int.tryParse(a.split('=')[1]);
    }
  }
  return null;
}

void _addCorsHeaders(HttpResponse resp) {
  resp.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type');
}

Future<void> _jsonResponse(HttpResponse resp, dynamic data,
    {int status = HttpStatus.ok}) async {
  resp.headers.contentType = ContentType.json;
  resp.statusCode = status;
  resp.write(jsonEncode(data));
  await resp.close();
}

Future<Map<String, dynamic>> _readBody(HttpRequest req) async {
  final raw = await utf8.decoder.bind(req).join();
  return jsonDecode(raw) as Map<String, dynamic>;
}

// ─── Router ───────────────────────────────────────────────────────────────────

Future<void> _route(HttpRequest req, _Stores stores) async {
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

  final resource = segments[0];
  final hasId = segments.length >= 2;
  final id = hasId ? segments[1] : null;

  switch (resource) {
    case 'products':
      await _handleProducts(req, method, id, stores.products);
      return;
    case 'orders':
      await _handleOrders(req, method, id, stores.orders);
      return;
    case 'categories':
      await _handleResource(req, method, id, stores.categories);
      return;
    case 'styles':
      await _handleResource(req, method, id, stores.styles);
      return;
    case 'config':
      if (method == 'GET' && !hasId) {
        await _jsonResponse(req.response, stores.config.list());
      } else {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
      }
      return;
    case 'refunds':
      if (method == 'PUT' && hasId) {
        await _handleRefund(req, id!, stores.orders);
      } else {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        await req.response.close();
      }
      return;
    default:
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
  }
}

/// Generic CRUD handler for products / categories / styles.
Future<void> _handleResource(
    HttpRequest req, String method, String? id, JsonFileStore store) async {
  switch (method) {
    case 'GET':
      if (id == null) {
        final all = store.list();
        // For categories & styles, optionally filter active only
        final activeOnly = req.uri.queryParameters['active'] == 'true';
        if (activeOnly) {
          return await _jsonResponse(
              req.response,
              all.where((e) => e['active'] != false).toList());
        }
        return await _jsonResponse(req.response, all);
      }
      // GET by id
      final item = store.findById(id);
      if (item == null) {
        return await _jsonResponse(req.response, {'error': 'Not found: $id'},
            status: HttpStatus.notFound);
      }
      return await _jsonResponse(req.response, item);

    case 'POST':
      if (id != null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      final body = await _readBody(req);
      final created = store.create(body);
      return await _jsonResponse(req.response, created,
          status: HttpStatus.created);

    case 'PUT':
      if (id == null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      final putBody = await _readBody(req);
      final updated = store.update(id, putBody);
      return await _jsonResponse(req.response, updated);

    case 'DELETE':
      if (id == null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      store.delete(id);
      return await _jsonResponse(req.response, {'deleted': id});

    default:
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
  }
}

/// Products handler — same CRUD pattern but ProductsStore has its own type.
Future<void> _handleProducts(
    HttpRequest req, String method, String? id, ProductsStore store) async {
  switch (method) {
    case 'GET':
      if (id == null) {
        return await _jsonResponse(req.response, store.list());
      }
      final item = store.findById(id);
      if (item == null) {
        return await _jsonResponse(req.response, {'error': 'Product not found: $id'},
            status: HttpStatus.notFound);
      }
      return await _jsonResponse(req.response, item);
    case 'POST':
      if (id != null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      final body = await _readBody(req);
      final created = store.create(body);
      return await _jsonResponse(req.response, created, status: HttpStatus.created);
    case 'PUT':
      if (id == null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      final putBody = await _readBody(req);
      final updated = store.update(id, putBody);
      return await _jsonResponse(req.response, updated);
    case 'DELETE':
      if (id == null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      store.delete(id);
      return await _jsonResponse(req.response, {'deleted': id});
    default:
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
  }
}

/// Orders have custom logic: POST auto-assigns id/orderNumber,
/// PUT updates status, DELETE cancels.
Future<void> _handleOrders(
    HttpRequest req, String method, String? id, JsonFileStore store) async {
  switch (method) {
    case 'GET':
      if (id == null) {
        return await _jsonResponse(req.response, store.list());
      }
      final item = store.findById(id);
      if (item == null) {
        return await _jsonResponse(req.response, {'error': 'Order not found: $id'},
            status: HttpStatus.notFound);
      }
      return await _jsonResponse(req.response, item);

    case 'POST':
      if (id != null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      final body = await _readBody(req);
      // Auto-assign order id and number if not provided by client
      body.putIfAbsent('id', () => 'ord-${DateTime.now().millisecondsSinceEpoch}');
      final existingCount = store.list().length;
      body.putIfAbsent('orderNumber',
          () => 'ORD-${_todayString()}-${existingCount + 1}');
      body.putIfAbsent('createdAt', () => DateTime.now().toUtc().toIso8601String());
      body.putIfAbsent('status', () => 'pending');
      body.putIfAbsent('refundStatus', () => null);
      final created = store.create(body);
      return await _jsonResponse(req.response, created,
          status: HttpStatus.created);

    case 'PUT':
      if (id == null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      final putBody = await _readBody(req);
      final updated = store.update(id, putBody);
      return await _jsonResponse(req.response, updated);

    case 'DELETE':
      if (id == null) {
        req.response.statusCode = HttpStatus.methodNotAllowed;
        return await req.response.close();
      }
      store.delete(id);
      return await _jsonResponse(req.response, {'deleted': id});

    default:
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
  }
}

/// Process a refund request — admin approves or rejects.
Future<void> _handleRefund(
    HttpRequest req, String orderId, JsonFileStore ordersStore) async {
  if (req.method.toUpperCase() != 'PUT') {
    req.response.statusCode = HttpStatus.methodNotAllowed;
    return await req.response.close();
  }
  final body = await _readBody(req);
  final action = body['action'] as String?; // 'approve' or 'reject'
  final order = ordersStore.findById(orderId);
  if (order == null) {
    return await _jsonResponse(req.response,
        {'error': 'Order not found: $orderId'}, status: HttpStatus.notFound);
  }

  if (action == 'approve') {
    order['refundStatus'] = 'approved';
    order['status'] = 'cancelled';
  } else if (action == 'reject') {
    order['refundStatus'] = 'rejected';
  } else {
    return await _jsonResponse(req.response,
        {'error': 'action must be "approve" or "reject"'},
        status: HttpStatus.badRequest);
  }

  ordersStore.update(orderId, order);
  return await _jsonResponse(req.response, order);
}

String _todayString() {
  final now = DateTime.now();
  return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
}

// ─── Products Store (dedicated, with asset fallback on init) ──────────────────

class ProductsStore {
  ProductsStore({required this.dataFile, required this.fallbackAsset});

  final File dataFile;
  final File fallbackAsset;
  late final JsonFileStore _inner = JsonFileStore(dataFile.path);

  Future<void> init() async {
    if (await dataFile.exists()) {
      _inner.reload();
      return;
    }
    // Seed from asset fallback
    if (await fallbackAsset.exists()) {
      final raw = await fallbackAsset.readAsString();
      final decoded = jsonDecode(raw);
      final items = decoded is List
          ? decoded.cast<Map<String, dynamic>>()
          : (decoded['items'] as List).cast<Map<String, dynamic>>();
      for (final item in items) {
        _inner.create(item);
      }
      return;
    }
    // Empty
    _inner.reload();
  }

  List<Map<String, dynamic>> list() => _inner.list();
  Map<String, dynamic>? findById(String id) => _inner.findById(id);
  Map<String, dynamic> create(Map<String, dynamic> item) => _inner.create(item);
  Map<String, dynamic> update(String id, Map<String, dynamic> item) =>
      _inner.update(id, item);
  void delete(String id) => _inner.delete(id);
}

// ─── Generic JSON File Store ──────────────────────────────────────────────────

class JsonFileStore {
  JsonFileStore(this._path);

  final String _path;
  final List<Map<String, dynamic>> _items = [];

  void reload() {
    _items.clear();
    final file = File(_path);
    if (!file.existsSync()) return;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is List) {
      _items.addAll(decoded.cast<Map<String, dynamic>>());
    } else if (decoded is Map<String, dynamic> && decoded['items'] is List) {
      _items.addAll((decoded['items'] as List).cast<Map<String, dynamic>>());
    }
  }

  List<Map<String, dynamic>> list() => List<Map<String, dynamic>>.from(_items);

  Map<String, dynamic>? findById(String id) {
    try {
      return _items.firstWhere((e) => e['id'] == id);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> create(Map<String, dynamic> item) {
    final id = (item['id'] as String?) ??
        '${_path.split('/').last.replaceAll('.json', '')}_${DateTime.now().millisecondsSinceEpoch}';
    final created = Map<String, dynamic>.from(item)..['id'] = id;
    _items.add(created);
    _persist();
    return created;
  }

  Map<String, dynamic> update(String id, Map<String, dynamic> item) {
    final idx = _items.indexWhere((e) => e['id'] == id);
    if (idx == -1) throw StateError('Item not found: $id');
    final updated = Map<String, dynamic>.from(item)..['id'] = id;
    _items[idx] = updated;
    _persist();
    return updated;
  }

  void delete(String id) {
    _items.removeWhere((e) => e['id'] == id);
    _persist();
  }

  void _persist() {
    final file = File(_path);
    file.createSync(recursive: true);
    file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(_items));
  }
}

// ─── Stores Container ─────────────────────────────────────────────────────────

class _Stores {
  _Stores({
    required this.products,
    required this.orders,
    required this.categories,
    required this.styles,
    required this.config,
  });

  final ProductsStore products;
  final JsonFileStore orders;
  final JsonFileStore categories;
  final JsonFileStore styles;
  final JsonFileStore config;

  Future<void> initAll() async {
    await products.init();
    orders.reload();
    categories.reload();
    styles.reload();
    config.reload();
  }
}
