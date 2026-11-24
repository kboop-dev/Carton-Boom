import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/db.dart';
import '../../core/session.dart';
import '../../core/utils.dart';
import '../../core/widgets.dart';

class UsuariosPage extends StatelessWidget {
  const UsuariosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Usuarios y roles',
      subtitle: 'Aprueba registros nuevos y asigna permisos por rol',
      child: RecStream(
        stream: Db.stream('users'),
        builder: (c, users) {
          users.sort((a, b) => (a.s('activo') == 'false' ? 0 : 1).compareTo(b.s('activo') == 'false' ? 0 : 1));
          if (users.isEmpty) return const EmptyState('Sin usuarios');
          return Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final u in users)
                ListTile(
                  leading: CircleAvatar(child: Text(u.s('nombre', '?').isEmpty ? '?' : u.s('nombre', '?')[0].toUpperCase())),
                  title: Text(u.s('nombre')),
                  subtitle: Text('${u.s('email')} · alta ${fmtDate(u.dt('createdAt'))}'),
                  trailing: Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(
                      width: 190,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: Roles.asignables.contains(u.s('role')) ? u.s('role') : null,
                        hint: const Text('Asignar rol'),
                        items: [for (final r in Roles.asignables) DropdownMenuItem(value: r, child: Text(Roles.etiquetas[r]!))],
                        onChanged: u.id == Db.uid ? null : (r) => Db.update('users', u.id, {'role': r, 'activo': true}),
                      ),
                    ),
                    Switch(
                      value: u.b('activo'),
                      onChanged: u.id == Session.I.fbUser?.uid
                          ? null
                          : (v) async {
                              if (v && !Roles.asignables.contains(u.s('role'))) {
                                toast(context, 'Asigna un rol primero.', error: true);
                                return;
                              }
                              await Db.update('users', u.id, {'activo': v});
                            },
                    ),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}
