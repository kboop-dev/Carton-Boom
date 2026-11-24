// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<void> hardReload() async {
  html.window.location.reload();
}
