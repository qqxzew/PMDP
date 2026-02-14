import 'dart:html' as html;

const _cacheStorageKey = 'osrm_polyline_cache_v1';

Future<String?> readOsrmCache() async {
  return html.window.localStorage[_cacheStorageKey];
}

Future<void> writeOsrmCache(String value) async {
  html.window.localStorage[_cacheStorageKey] = value;
}
