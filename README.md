# Muebles Andrés

Sistema de punto de venta e inventario para una mueblería, hecho a la medida
del negocio real de un cliente. App Android nativa, 100% offline (sin
servidor ni internet), construida con Flutter.

## Qué hace

- **Ventas**: carrito con productos o kits armados, pago mixto (efectivo +
  consignación), comisión automática por vendedor, devoluciones, recibo en PDF.
- **Apartados (layaway)**: abonos parciales a lo largo del tiempo, reserva de
  stock, facturación automática al saldar.
- **Inventario**: existencias en tiempo real, costeo FIFO por lotes (cada
  compra entra a su propio costo; las ventas consumen primero el lote más
  viejo), ingreso manual de inventario sin afectar caja.
- **Compras y proveedores**: compras de contado o a crédito, cuenta por
  proveedor (deuda / pagado), abonos parciales.
- **Consignaciones**: saldo por cuenta bancaria, historial de movimientos
  (de qué venta o abono vino cada pago).
- **Comisiones**: porcentaje predeterminado por vendedor (editable), reporte
  de pendiente por pagar, historial de pagos realizados.
- **Análisis**: ventas, costo, utilidad y margen por semana/mes/año, detalle
  por producto, exportación a PDF.
- **Caja**: libro de movimientos único (ventas, gastos, compras, comisiones,
  devoluciones) que alimenta todos los reportes.

## Stack técnico

- **Flutter** (Dart) — UI y lógica de negocio.
- **Riverpod** — manejo de estado y providers reactivos.
- **Drift** (SQLite) — base de datos local, con migraciones de esquema
  versionadas.
- **pdf** / **printing** — generación de recibos y reportes en PDF.
- Arquitectura **offline-first**: toda la operación funciona sin conexión;
  no hay backend ni sincronización en la nube.

## Notas de diseño

- Costeo por **lotes FIFO**: cada compra crea un lote con su propio costo;
  las ventas consumen el lote más antiguo primero, así el costo y la
  utilidad reportada reflejan lo que realmente costó cada unidad vendida.
- Un único libro de caja (`CashMovements`) registra cada entrada/salida de
  dinero con su origen, para que todos los reportes financieros salgan de
  una sola fuente de verdad.
- Login básico de un solo usuario (pensado para una tablet compartida en el
  punto de venta, no para múltiples cuentas).

## Correr el proyecto

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

Requiere un dispositivo o emulador Android (o Chrome/Windows para explorar
la UI, aunque la base de datos local está pensada para Android).
