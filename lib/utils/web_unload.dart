// Selects the correct implementation at compile time.
// dart.library.html is present on Flutter Web; dart.library.io on native.
export 'web_unload_io.dart'
    if (dart.library.html) 'web_unload_html.dart';
