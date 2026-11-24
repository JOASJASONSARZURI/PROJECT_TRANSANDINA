# Contexto completo: Proyecto Final BD2 – TransAndina

## 1. Qué es y qué se espera

Grupos de 3 diseñan y construyen en 4 semanas la base de datos de una empresa de buses (PostgreSQL 16). Parten de un backlog, no de un enunciado técnico: **el modelo lo deciden ustedes**. Pero hay un **contrato técnico fijo**: 21 funciones y 1 vista con nombres, parámetros y tipos exactos. Si una firma no coincide, esa prueba oculta falla.

**Hoy es 11 de noviembre.** Si estás en la semana 3 o 4, el tiempo apremia; revisa el cronograma al final.

## 2. Entregables (grupoN.zip)

| Archivo | Contenido clave |
|---|---|
| `grupoN.sql` | Script único, corre en base vacía sin errores, **sin comandos `\` de psql**. Si no carga: 0 en pruebas automáticas (35 pts) |
| `grupoN_diagrama.pdf` | ER en crow's foot + tabla de trazabilidad (historia → tablas/restricciones) + justificación columnas vs tablas vs JSONB |
| `grupoN_pruebas.sql` | Mínimo 2 casos por historia (1 que funciona, 1 que falla), comentados con resultado esperado |
| `grupoN_rendimiento.pdf` | Tiempos del generador, EXPLAIN ANALYZE con/sin índice de las 2 consultas más costosas y de `fn_buscar_encomiendas`, justificación de cada índice |
| `grupoN_bitacora.pdf` | 8–15 entradas + 3 párrafos de reflexión |

## 3. Reglas sobre la IA

- Pueden usarla todo lo que quieran, **pero la defensa es sin IA**.
- Cada integrante debe poder explicar cada tabla, restricción y función.
- "Lo hizo la IA" no justifica ningún diseño.
- Si un integrante no explica ninguna parte del script, **la nota grupal se reduce a la mitad**.

## 4. Rúbrica (100 pts)

| Criterio | Pts |
|---|---:|
| Pruebas automáticas (ocultas) | 35 |
| Diagrama y trazabilidad | 15 |
| Pruebas propias | 10 |
| Rendimiento | 10 |
| Bitácora de IA | 10 |
| Defensa oral (individual) | 20 |

## 5. El negocio en una frase

Venta de pasajes **por tramo** en rutas con varias paradas: un mismo asiento se vende por partes (Cbba→Caracollo y luego Caracollo→La Paz). Además: reservas con vencimiento, tarifas históricas, anulaciones sin borrar, encomiendas con tipos dinámicos, promociones, incidencias y auditoría.

**Concepto clave:** dos tramos se solapan si comparten al menos un *segmento* entre paradas consecutivas. Bajar y subir en la misma parada **no** es solapamiento.

## 6. Contrato técnico (lo que debe existir exacto)

**Configuración**
- `fn_crear_ruta(p_codigo text, p_paradas text[]) RETURNS int`
- `fn_crear_bus(p_placa text, p_capacidad int, p_amenidades jsonb DEFAULT '{}') RETURNS int`
- `fn_buses_con_amenidades(p_filtro jsonb) RETURNS SETOF int`
- `fn_programar_viaje(p_ruta int, p_bus int, p_salida timestamptz, p_llegada timestamptz) RETURNS int`
- `fn_fijar_tarifa(p_ruta int, p_origen text, p_destino text, p_precio numeric) RETURNS int`

**Venta y promociones**
- `fn_vender_pasaje(p_viaje, p_asiento, p_origen, p_destino, p_ci, p_nombre) RETURNS int`
- `fn_reservar(..., p_vigencia interval) RETURNS int`
- `fn_pagar_reserva(p_reserva int) RETURNS int`
- `fn_anular_pasaje(p_pasaje int) RETURNS void`
- `fn_crear_promocion(p_nombre text, p_porcentaje numeric, p_condiciones jsonb) RETURNS int`
- `fn_promocion_aplicada(p_pasaje int) RETURNS int` (NULL si no hubo)

**Reportes y control**
- `fn_asientos_disponibles(p_viaje, p_origen, p_destino) RETURNS SETOF int`
- `fn_ocupacion(p_viaje) RETURNS TABLE (desde text, hasta text, ocupados int)`
- `fn_ingresos_viaje(p_viaje) RETURNS numeric`
- `fn_descuento_otorgado(p_promocion) RETURNS numeric`
- `fn_registrar_incidencia(p_viaje, p_tipo text, p_datos jsonb) RETURNS int`
- `fn_retraso_total(p_viaje) RETURNS int`
- `VIEW v_auditoria (tabla, operacion, fecha, datos_anteriores jsonb, datos_nuevos jsonb)`

**Encomiendas**
- `fn_definir_tipo_encomienda(p_tipo text, p_campos jsonb) RETURNS void`
- `fn_registrar_encomienda(p_viaje, p_origen, p_destino, p_tipo, p_atributos jsonb) RETURNS int`
- `fn_buscar_encomiendas(p_filtro jsonb) RETURNS SETOF int`

**Integración**
- `fn_manifiesto(p_viaje int) RETURNS jsonb` (lista de pasajeros a bordo; **el anexo de integración no venía en el documento que pegaste**, así que el formato exacto del JSON está por confirmar con el docente)

**Reglas generales:** toda violación de negocio → `RAISE EXCEPTION`; ciudades por nombre exacto; IDs devueltos son enteros.

## 7. Reglas de negocio por historia (lo que las pruebas ocultas verificarán)

**Épica 1 – Configuración**
- **HU-01:** código único, ≥2 paradas, orden conservado, ciudad no repetida en la misma ruta (sí en varias rutas).
- **HU-02:** placa única, capacidad 1–80, asientos 1..capacidad. Amenidades en JSONB (extensibles). Filtrar por una o varias, **incluyendo el detalle** (ej. televisor con pantalla en cada asiento) → operador de contención `@>`. Resultados ordenados por id.
- **HU-03:** llegada > salida; un bus no puede tener viajes con horarios cruzados (usar exclusión con `tstzrange`/GiST); viajes no cruzados sí se aceptan.
- **HU-04:** origen antes que destino, precio > 0; **histórico** (no se borra); vigente = el último fijado; sin tarifa no se vende ni reserva; el pasaje conserva su precio.

**Épica 2 – Venta**
- **HU-05:** asiento existe en el bus del viaje; origen/destino válidos y en orden; sin solapamiento con pasaje/reserva vigente; mismo asiento en tramos no solapados sí; no vender si ya salió; devuelve id.
- **HU-06:** disponibilidad depende del tramo; reservas vencidas no ocupan; orden por número.
- **HU-07:** pasajero por CI (upsert: si existe, actualiza nombre); no puede ocupar dos asientos en tramos solapados del mismo viaje; sí en consecutivos.
- **HU-08:** vigencia > 0; bloquea como venta mientras vigente; **vence sola** (sin jobs: calcular con `now() > vence_en`); precio = vigente al reservar.
- **HU-09:** solo reserva vigente; cobra el precio de la reserva; no se paga dos veces.
- **HU-10:** solo antes de la salida; libera el asiento; **no se borra** (estado anulado); no anular dos veces.
- **HU-16 Promociones:** % entre 0 y 100 exclusivo; condiciones combinables (ruta por código existente, fecha desde/hasta, días de semana 1–7, antelación mínima en días enteros); condición desconocida, ruta inexistente o rango invertido → rechazo; **fechas y días según hora de salida en Bolivia** (`AT TIME ZONE 'America/La_Paz'`); se aplica la de **mayor descuento**, empate → **más antigua**; solo una; precio redondeado a centavos y congelado; el pasaje registra la promoción aplicada.

**Épica 3 – Reportes**
- **HU-11:** una fila por segmento, en orden de ruta; cuenta pagados + reservas vigentes.
- **HU-12:** suma solo pagados al precio vendido; sin ventas → 0.
- **HU-13 Auditoría:** trigger en pasajes y tarifas (INSERT/UPDATE/DELETE), con tabla, operación, fecha, fila completa anterior y nueva (`to_jsonb(OLD/NEW)`).
- **HU-17 Incidencias:** retraso (minutos entero >0 + motivo), avería (descripción + requiere_cambio_bus booleano), control (lugar + resultado ∈ {"sin novedad","observado"}). Tipo desconocido, dato faltante o mal tipado (minutos como texto) → rechazo. Retraso total = suma, sin retrasos = 0.
- **HU-18:** suma (precio sin descuento − cobrado) solo de pagados; sin uso → 0.

**Épica 4 – Confiabilidad**
- **HU-14:** dos ventas conflictivas simultáneas → exactamente una gana, **aunque las transacciones estén abiertas a la vez** → necesitas protección a nivel de base: `EXCLUDE USING gist` (asiento + rango de segmentos) o bloqueo (`FOR UPDATE` / advisory lock) sobre el asiento/viaje. La exclusión constraint es la más robusta.
- **HU-15:** generador < 10 min; consultas < 5 ms promedio; búsqueda de encomiendas < 2 ms (con ~90.000 pasajes y 40.000 encomiendas).

**Épica 5 – Encomiendas**
- **HU-19:** tipos iniciales: documento (sin datos), paquete (peso_kg número positivo), perecible (peso_kg positivo + temperatura máxima °C). Clases: texto | numero | numero_positivo | si_no; clase desconocida → rechazo. Un tipo se puede **redefinir**: lo nuevo aplica a registros futuros; **los anteriores no se tocan**.
- **HU-20:** destinatario con nombre no vacío (teléfono opcional); validar obligatorios del tipo **con clase correcta** (`"12"` como texto se rechaza → usar `jsonb_typeof`); datos extra no obligatorios se conservan; tipo no definido → rechazo; origen/destino válidos y en orden; **validación en la base**, no en la app.
- **HU-21:** búsqueda por varios datos a la vez, incluidos anidados (destinatario.telefono); coincide si contiene todos → `@>`; orden por id; sin coincidencias → vacío.

## 8. Decisiones de diseño que debes poder defender

- **JSONB vs columnas vs tablas:** amenidades y atributos de encomienda → JSONB (forma variable); tipos de encomienda y su definición → tabla (con versionado para HU-19); lo demás → columnas/tablas normalizadas.
- **Índice GIN** sobre atributos de encomienda y amenidades (`jsonb_path_ops` suele bastar para `@>`).
- **Orden de paradas:** tabla `ruta_parada` con posición; UNIQUE(ruta, ciudad) y UNIQUE(ruta, posición).
- **Tarifas:** tabla append-only con fecha de fijación; "vigente" = última.
- **Pasajes/reservas:** idealmente una tabla con estado (pagado/reservado/anulado) y `vence_en`; nunca DELETE (conviene un trigger que lo bloquee o revocar).
- **Defensa en vivo:** el docente cambiará un requisito; debes saber explicar qué cambia en el modelo y por qué.

## 9. Rendimiento

El docente entrega `generar_volumen.sql` (90.000 pasajes, 40.000 encomiendas, 3.000 incidencias, 2.000 viajes, usando solo las funciones del contrato). Pasos: cargar tu script en base vacía → ejecutar el generador → anotar tiempo total y los NOTICE de tiempos promedio → EXPLAIN ANALYZE con/sin índice. Si tarda mucho: faltan índices (por ejemplo en pasajes por viaje/asiento, encomiendas GIN).

## 10. Bitácora de IA

8–15 entradas con: fecha, herramienta, historia, prompt, qué propuso la IA, ¿era correcto?, cómo verificaste, qué cambiaste. Más 3 párrafos: error de IA más difícil de detectar, qué decidieron contra la IA, qué contexto le dieron y cómo mejoró la calidad. **Afirmar que la IA nunca se equivocó = insuficiente.** Registra errores reales a medida que ocurren.

## 11. Cronograma

| Sem | Trabajo | Control |
|---|---|---|
| 1 | Backlog, diagrama, trazabilidad | Diagrama revisado |
| 2 | Épicas 1 y 2 (tablas, restricciones, funciones) | Demo de venta por tramos |
| 3 | Reportes, auditoría, promociones, incidencias, encomiendas, concurrencia, pruebas propias | Revisión con agente revisor |
| 4 | Volumen, índices, rendimiento, bitácora | Entrega y defensa |

## 12. Trampas frecuentes (las pruebas ocultas las buscarán)

1. Firma distinta a la del contrato (nombres de parámetros, tipos, `DEFAULT '{}'`).
2. Tratar bajar y subir en la misma parada como solapamiento.
3. Reservas vencidas contando como ocupadas (en disponibilidad, ocupación, solapamiento).
4. Precio recalculado en vez de congelado (tarifa, promoción, pago de reserva).
5. Usar `now()` fijo en vez de evaluar vencimiento en tiempo de consulta.
6. Aceptar `"12"` (string) como número en JSONB.
7. Condiciones de promoción desconocidas aceptadas silenciosamente.
8. Zona horaria: días de semana y fechas deben calcularse en hora de Bolivia, no UTC.
9. Redondeo a centavos y desempate de promociones.
10. Script con `\` de psql o que falla al correr de nuevo en base vacía.
11. Mensajes con `RAISE EXCEPTION` faltantes (un error de tipo/constraint genérico a veces vale, pero verifica que no se cuele algo inválido).
12. Concurrencia solo "verificada en app" en vez de a nivel de base.

## 13. Qué falta o conviene confirmar

- El **anexo de integración** (formato exacto de `fn_manifiesto`) no está en el documento pegado: pídeselo al docente.
- El archivo `generar_volumen.sql` lo entrega el docente.

## 14. Plan de acción sugerido

1. Diseñar el modelo y el diagrama (si aún no).
2. Implementar tablas + restricciones (EXCLUDE para solapamientos de tramo y de viajes por bus).
3. Escribir las 21 funciones y la vista, respetando firmas.
4. Triggers de auditoría y bloqueo de DELETE.
5. Probar con `grupoN_pruebas.sql` (caso OK + caso fallo por historia).
6. Ejecutar el generador, medir, indexar, repetir con EXPLAIN ANALYZE.
7. Documentar bitácora desde ya, no al final.
8. Cada integrante practica explicar sus partes **sin IA** y ensaya posibles cambios de requisito (nueva condición de promoción, nuevo tipo de tramo, cambio de política de reservas, etc.).

Si quieres, puedo ayudarte con cualquier parte concreta: el modelo y el diagrama, el esquema SQL, una función específica, el diseño de concurrencia o la estrategia de índices. ¿Por dónde empezamos?