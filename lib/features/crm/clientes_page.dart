import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});
  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  String q = '', filtro = 'todos';

  Future<void> _editar([Rec? r]) async {
    final nombre = TextEditingController(text: r?.s('nombre'));
    final razon = TextEditingController(text: r?.s('razonSocial'));
    final rfc = TextEditingController(text: r?.s('rfc'));
    final contacto = TextEditingController(text: r?.s('contacto'));
    final tel = TextEditingController(text: r?.s('telefono'));
    final mail = TextEditingController(text: r?.s('correo'));
    final dir = TextEditingController(text: r?.s('direccion'));
    final notas = TextEditingController(text: r?.s('notas'));
    String estado = r?.s('estado', 'activo') ?? 'activo';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(r == null ? 'Nuevo cliente' : 'Editar cliente'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                textField(nombre, 'Nombre comercial *'),
                const SizedBox(height: 10),
                textField(razon, 'Razón social'),
                const SizedBox(height: 10),
                Row(children: [Expanded(child: textField(rfc, 'RFC')), const SizedBox(width: 8), Expanded(child: textField(tel, 'Teléfono'))]),
                const SizedBox(height: 10),
                Row(children: [Expanded(child: textField(contacto, 'Contacto')), const SizedBox(width: 8), Expanded(child: textField(mail, 'Correo'))]),
                const SizedBox(height: 10),
                textField(dir, 'Dirección de entrega', lines: 2),
                const SizedBox(height: 10),
                dropdown<String>('Estado', estado, ['prospecto', 'activo'], (v) => set(() => estado = v!)),
                const SizedBox(height: 10),
                textField(notas, 'Notas', lines: 2),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (nombre.text.trim().isEmpty) return toast(context, 'El nombre es obligatorio.', error: true);
    final data = {
      'nombre': nombre.text.trim(),
      'nombreLower': nombre.text.trim().toLowerCase(),
      'razonSocial': razon.text.trim(),
      'rfc': rfc.text.trim().toUpperCase(),
      'contacto': contacto.text.trim(),
      'telefono': tel.text.trim(),
      'correo': mail.text.trim(),
      'direccion': dir.text.trim(),
      'notas': notas.text.trim(),
      'estado': r?.s('estado') == 'inactivo' ? 'inactivo' : estado,
    };
    try {
      if (r == null) {
        await Db.add('clientes', {...data, 'fechaAlta': FieldValue.serverTimestamp(), 'totalPedidos': 0});
      } else {
        await Db.update('clientes', r.id, data);
      }
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  Future<void> _baja(Rec r) async {
    String motivo = Catalogos.motivosBaja.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Dar de baja a ${r.s('nombre')}'),
          content: dropdown<String>('Motivo', motivo, Catalogos.motivosBaja, (v) => set(() => motivo = v!)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Dar de baja')),
          ],
        ),
      ),
    );
    if (ok == true) await Db.update('clientes', r.id, {'estado': 'inactivo', 'fechaBaja': FieldValue.serverTimestamp(), 'motivoBaja': motivo});
  }

  Future<void> _archivos(Rec cli) => showDialog(context: context, builder: (_) => _ArchivosDialog(cli: cli));

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Clientes',
      subtitle: 'Cartera, flujo de clientes y banco de logos / suajes',
      actions: [FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.person_add), label: const Text('Nuevo cliente'))],
      scroll: false,
      child: RecStream(
        stream: Db.stream('clientes', orderBy: 'nombre'),
        builder: (c, todos) {
          final lista = todos.where((e) => (filtro == 'todos' || e.s('estado') == filtro) && e.s('nombre').toLowerCase().contains(q.toLowerCase())).toList();
          return Column(children: [
            Row(children: [
              Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar cliente'), onChanged: (v) => setState(() => q = v))),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'todos', label: Text('Todos')), ButtonSegment(value: 'activo', label: Text('Activos')), ButtonSegment(value: 'prospecto', label: Text('Prospectos')), ButtonSegment(value: 'inactivo', label: Text('Perdidos'))],
                selected: {filtro},
                onSelectionChanged: (s) => setState(() => filtro = s.first),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: lista.isEmpty
                  ? const EmptyState('Sin clientes')
                  : ListView.separated(
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final r = lista[i];
                        final inactivo = r.s('estado') == 'inactivo';
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: inactivo ? Colors.red.shade100 : null, child: Text(r.s('nombre', '?').isEmpty ? '?' : r.s('nombre')[0].toUpperCase())),
                            title: Text(r.s('nombre')),
                            subtitle: Text('${r.s('contacto')} ${r.s('telefono')} · ${r.i('totalPedidos')} pedidos · último: ${fmtDate(r.dt('ultimoPedido'))}${inactivo ? ' · baja: ${r.s('motivoBaja')}' : ''}'),
                            trailing: Wrap(spacing: 4, children: [
                              EstadoChip(r.s('estado') == 'inactivo' ? 'Rechazada' : (r.s('estado') == 'prospecto' ? 'Pendiente' : 'Entregada')),
                              IconButton(tooltip: 'Logos y suajes', icon: const Icon(Icons.image_outlined), onPressed: () => _archivos(r)),
                              IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _editar(r)),
                              inactivo
                                  ? IconButton(tooltip: 'Reactivar', icon: const Icon(Icons.restart_alt), onPressed: () => Db.update('clientes', r.id, {'estado': 'activo', 'fechaReactivacion': FieldValue.serverTimestamp()}))
                                  : IconButton(tooltip: 'Dar de baja', icon: const Icon(Icons.person_off_outlined), onPressed: () => _baja(r)),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class _ArchivosDialog extends StatefulWidget {
  final Rec cli;
  const _ArchivosDialog({required this.cli});
  @override
  State<_ArchivosDialog> createState() => _ArchivosDialogState();
}

class _ArchivosDialogState extends State<_ArchivosDialog> {
  String tipo = 'logo';

  Future<void> _subir() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg'], withData: true);
    if (r == null || r.files.single.bytes == null) return;
    final f = r.files.single;
    if (f.bytes!.length > 700 * 1024) return toast(context, 'La imagen pesa más de 700 KB. Reduce su tamaño.', error: true);
    try {
      await Db.col('clientes').doc(widget.cli.id).collection('archivos').add({
        'tipo': tipo,
        'nombre': f.name,
        'dataB64': base64Encode(f.bytes!),
        'size': f.bytes!.length,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': Db.uid,
      });
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Logos y suajes · ${widget.cli.s('nombre')}'),
        content: SizedBox(
          width: 620,
          height: 420,
          child: Column(children: [
            Row(children: [
              SegmentedButton<String>(segments: const [ButtonSegment(value: 'logo', label: Text('Logo')), ButtonSegment(value: 'suaje', label: Text('Suaje'))], selected: {tipo}, onSelectionChanged: (s) => setState(() => tipo = s.first)),
              const SizedBox(width: 12),
              FilledButton.icon(onPressed: _subir, icon: const Icon(Icons.upload), label: const Text('Subir imagen (PNG/JPG ≤ 700 KB)')),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: Db.col('clientes').doc(widget.cli.id).collection('archivos').snapshots(),
                builder: (_, s) {
                  if (!s.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = s.data!.docs;
                  if (docs.isEmpty) return const EmptyState('Aún no hay archivos');
                  return GridView.count(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, children: [
                    for (final d in docs)
                      Card(
                        margin: EdgeInsets.zero,
                        child: Column(children: [
                          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: Image.memory(base64Decode('${d.data()['dataB64']}'), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)))),
                          Text('${d.data()['tipo']} · ${d.data()['nombre']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => d.reference.delete()),
                        ]),
                      ),
                  ]);
                },
              ),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      );
}
