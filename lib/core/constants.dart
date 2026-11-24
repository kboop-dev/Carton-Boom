class Roles {
  static const admin = 'admin';
  static const ventas = 'ventas';
  static const almacen = 'almacen';
  static const operador = 'operador';
  static const supervisor = 'supervisor';
  static const pendiente = 'pendiente';

  static const asignables = [admin, ventas, almacen, operador, supervisor];
  static const etiquetas = {
    admin: 'Administrador',
    ventas: 'Ventas',
    almacen: 'Almacén',
    operador: 'Operador de planta',
    supervisor: 'Supervisor',
    pendiente: 'Pendiente de aprobación',
  };

  /// Módulo -> roles con acceso (el admin siempre accede).
  static const modulos = <String, List<String>>{
    'dashboard': [ventas, almacen, operador, supervisor],
    'cotizador': [ventas, supervisor],
    'crm': [ventas, supervisor],
    'clientes': [ventas, supervisor],
    'ordenes': [ventas, supervisor, almacen, operador],
    'planta': [supervisor, almacen, operador],
    'inventario': [almacen, supervisor],
    'mermas': [supervisor, almacen, operador],
    'pendientes': [ventas, almacen, operador, supervisor],
    'parametros': [supervisor],
    'usuarios': [],
    'admin': [],
  };

  static bool puede(String role, String modulo) =>
      role == admin || (modulos[modulo]?.contains(role) ?? false);
}

class EstadoCot {
  static const pendiente = 'Pendiente';
  static const aprobada = 'Aprobada';
  static const produccion = 'En Producción';
  static const entregada = 'Entregada';
  static const rechazada = 'Rechazada';
  static const pipeline = [pendiente, aprobada, produccion, entregada];
  static const todos = [pendiente, aprobada, produccion, entregada, rechazada];
}

class EstadoOt {
  static const pendienteMp = 'Pendiente MP';
  static const mpAsignada = 'MP Asignada';
  static const impresion = 'En Impresión/Corte';
  static const calidad = 'Calidad Registrada';
  static const armado = 'En Armado';
  static const finalizado = 'Finalizado';
  static const listo = 'Listo para Entrega';
  static const entregada = 'Entregada';
  static const flujo = [pendienteMp, mpAsignada, impresion, calidad, armado, finalizado, listo, entregada];
  static const checkpoint = {
    pendienteMp: 0, mpAsignada: 1, impresion: 2, calidad: 3, armado: 4, finalizado: 4, listo: 5, entregada: 5,
  };
}

class TiposCaja {
  static const crr = 'Caja Regular Ranurada (CRR)';
  static const suajado = 'Suajado';
  static const charola = 'Charola';
  static const mediasCajas = 'CRR Medias Cajas';
  static const traslapada = 'CRR Traslapada';
  static const charolaAuto = 'Charola Automática';
  static const sinTapas = 'CRR Sin Tapas';
  static const separador = 'Separador';
  static const todos = [crr, suajado, charola, mediasCajas, traslapada, charolaAuto, sinTapas, separador];

  /// Tipos cuyo desarrollo se captura directo (troquelados / suajados).
  static const desarrolloDirecto = [suajado, separador, charolaAuto];
  static const conAdhesivo = [crr, mediasCajas, traslapada, sinTapas];
}

class Catalogos {
  static const flautas = ['C', 'B', 'BC', 'E'];
  static const flautaNombre = {
    'C': 'C (corrugado sencillo)',
    'B': 'B (corrugado sencillo)',
    'BC': 'BC (doble)',
    'E': 'E (microcorrugado)',
  };
  static const materiales = ['Kraft', 'Blanco'];
  static const acabados = ['Pegada', 'Grapada', 'Troquelada', 'Sin acabado'];
  static const tiposMerma = ['Ajuste de máquina', 'Corte defectuoso', 'Impresión defectuosa', 'Manejo / daño', 'Material defectuoso', 'Producción', 'Otro'];
  static const motivosBaja = ['Precio', 'Calidad', 'Servicio / entrega', 'Cambió de proveedor', 'Cerró su negocio', 'Sin pedidos', 'Otro'];
}
