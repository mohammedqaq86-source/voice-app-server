// Web implementation — runs only when dart.library.html is available.
// beforeunload is a best-effort signal; async Firestore writes may not
// complete before the browser kills the page, but the heartbeat + stale
// cleanup system (75 s window) covers the gap automatically.
import 'dart:html' as html;

void listenForPageUnload(void Function() callback) {
  html.window.addEventListener('beforeunload', (_) => callback());
}
