import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'utils.dart';
import 'db.dart';

bool isWide(BuildContext c) => MediaQuery.of(c).size.width >= 1000;
bool isMedium(BuildContext c) => MediaQuery.of(c).size.width >= 700;

void toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c).hideCurrentSnackBar();
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Theme.of(c).colorScheme.error : null,
    behavior: SnackBarBehavior.floating,
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

String errMsg(Object e) {
  final s = e.toString();
  return s.replaceFirst('Exception: ', '').replaceFirst(RegExp(r'^\[.*?\]\s*'), '');
}

Future<bool> confirmDialog(BuildContext c, String titulo, String texto, {String ok = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

/// Envuelve un Stream<List<Rec>> con estados de carga/error.
class RecStream extends StatelessWidget {
  final Stream<List<Rec>> stream;
  final Widget Function(BuildContext, List<Rec>) builder;
  const RecStream({super.key, required this.stream, required this.builder});

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Rec>>(
        stream: stream,
        builder: (c, snap) {
          if (snap.hasError) return ErrorView(snap.error.toString());
          if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
          return builder(c, snap.data!);
        },
      );
}

class ErrorView extends StatelessWidget {
  final String msg;
  const ErrorView(this.msg, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Ocurrió un error: $msg', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      );
}

/// Contenedor estándar de página: título, acciones y contenido con scroll.
class PageBody extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;
  final bool scroll;
  const PageBody({super.key, required this.title, this.subtitle, this.actions = const [], required this.child, this.scroll = true});

  @override
  Widget build(BuildContext context) {
    final head = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null) Text(subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ]),
          ...actions,
        ],
      ),
    );
    if (scroll) {
      return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          head,
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), child: child),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      head,
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), child: child)),
    ]);
  }
}

class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;
  const SectionCard({super.key, this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  if (trailing != null) trailing!,
                ]),
              ),
            child,
          ]),
        ),
      );
}

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? hint;
  const KpiCard({super.key, required this.label, required this.value, required this.icon, this.color, this.hint});
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          CircleAvatar(backgroundColor: c.withOpacity(.12), child: Icon(icon, color: c)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (hint != null) Text(hint!, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Rejilla responsiva: reparte hijos en N columnas según el ancho.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 260, this.spacing = 12});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (c, box) {
        final cols = (box.maxWidth / minItemWidth).floor().clamp(1, 6);
        final w = (box.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(spacing: spacing, runSpacing: spacing, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class EstadoChip extends StatelessWidget {
  final String estado;
  const EstadoChip(this.estado, {super.key});
  static Color color(String e) {
    switch (e) {
      case 'Pendiente':
      case 'Pendiente MP':
        return Colors.orange;
      case 'Aprobada':
      case 'MP Asignada':
        return Colors.blue;
      case 'En Producción':
      case 'En Impresión/Corte':
      case 'En Armado':
        return Colors.deepPurple;
      case 'Calidad Registrada':
      case 'Finalizado':
        return Colors.teal;
      case 'Listo para Entrega':
        return Colors.indigo;
      case 'Entregada':
        return Colors.green;
      case 'Rechazada':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
      child: Text(estado, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Campo numérico con controlador propio.
Widget numField(TextEditingController c, String label, {String? suffix, String? prefix, bool dec = true, void Function(String)? onChanged, String? helper}) =>
    TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: dec),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(dec ? r'[0-9.,]' : r'[0-9]'))],
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, suffixText: suffix, prefixText: prefix, helperText: helper),
    );

Widget textField(TextEditingController c, String label, {int lines = 1, void Function(String)? onChanged, bool enabled = true, String? hint}) =>
    TextField(controller: c, maxLines: lines, onChanged: onChanged, enabled: enabled, decoration: InputDecoration(labelText: label, hintText: hint));

Widget dropdown<T>(String label, T? value, List<T> items, void Function(T?) onChanged, {String Function(T)? text}) =>
    DropdownButtonFormField<T>(
      value: items.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final i in items) DropdownMenuItem(value: i, child: Text(text != null ? text(i) : '$i', overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );

/// Abre la cámara para leer QR / código de barras. Devuelve el texto leído.
Future<String?> scanWithCamera(BuildContext context, {String title = 'Escanear código'}) {
  return showDialog<String>(context: context, builder: (_) => _ScannerDialog(title: title));
}

class _ScannerDialog extends StatefulWidget {
  final String title;
  const _ScannerDialog({required this.title});
  @override
  State<_ScannerDialog> createState() => _ScannerDialogState();
}

class _ScannerDialogState extends State<_ScannerDialog> {
  final controller = MobileScannerController();
  bool done = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 420,
          height: 340,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (done) return;
                for (final b in capture.barcodes) {
                  final v = b.rawValue;
                  if (v != null && v.isNotEmpty) {
                    done = true;
                    Navigator.pop(context, v);
                    return;
                  }
                }
              },
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
      );
}

/// Campo de escaneo: sirve para lector USB/Bluetooth (teclado + Enter) y para cámara.
class ScanField extends StatefulWidget {
  final String label;
  final void Function(String) onScan;
  final bool autofocus;
  const ScanField({super.key, required this.label, required this.onScan, this.autofocus = true});
  @override
  State<ScanField> createState() => _ScanFieldState();
}

class _ScanFieldState extends State<ScanField> {
  final c = TextEditingController();
  final f = FocusNode();
  @override
  void dispose() {
    c.dispose();
    f.dispose();
    super.dispose();
  }

  void _submit(String v) {
    if (v.trim().isEmpty) return;
    widget.onScan(v.trim());
    c.clear();
    f.requestFocus();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: c,
        focusNode: f,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.done,
        onSubmitted: _submit,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: const Icon(Icons.qr_code_scanner),
          suffixIcon: IconButton(
            tooltip: 'Usar cámara',
            icon: const Icon(Icons.photo_camera_outlined),
            onPressed: () async {
              final r = await scanWithCamera(context);
              if (r != null) _submit(r);
            },
          ),
        ),
      );
}

/// Autocompletado de un catálogo (clientes, productos, MP...).
class RecPicker extends StatelessWidget {
  final String label;
  final List<Rec> items;
  final String Function(Rec) text;
  final void Function(Rec) onSelected;
  final String? initial;
  const RecPicker({super.key, required this.label, required this.items, required this.text, required this.onSelected, this.initial});
  @override
  Widget build(BuildContext context) => Autocomplete<Rec>(
        initialValue: TextEditingValue(text: initial ?? ''),
        displayStringForOption: text,
        optionsBuilder: (v) {
          final q = v.text.toLowerCase();
          final r = items.where((e) => text(e).toLowerCase().contains(q)).take(30);
          return r;
        },
        onSelected: onSelected,
        fieldViewBuilder: (c, ctrl, focus, submit) => TextField(
          controller: ctrl,
          focusNode: focus,
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.search)),
        ),
      );
}

/// Marca de tiempo del servidor o ahora, para campos de fecha.
Map<String, dynamic> auditoria() => {'uid': Db.uid};
