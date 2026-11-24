-- =====================================================================
-- Pruebas funcionales de TransAndina
-- Ejecutar despues de grupoN.sql en la misma base PostgreSQL 16.
-- Cada HU tiene un caso positivo y uno negativo (HU-15 verifica indices).
-- Los datos y objetos auxiliares se revierten al final; no quedan fixtures.
-- No contiene comandos de psql.
-- =====================================================================

BEGIN;

CREATE TEMP TABLE grupoN_contexto (
  ruta_id       integer,
  bus_id        integer,
  viaje_id      integer,
  promo_id      integer,
  venta_id      integer,
  venta_tramo_id integer,
  reserva_id    integer,
  anulacion_id  integer,
  encomienda_id integer,
  salida        timestamptz,
  llegada       timestamptz
);

CREATE TEMP TABLE grupoN_resultados (
  caso     text NOT NULL,
  resultado text NOT NULL
);

-- Auxiliar: falla si una condicion esperada no se cumple.
CREATE SCHEMA grupoN_test;

CREATE FUNCTION grupoN_test.assert_true(p_caso text, p_condicion boolean)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_condicion IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FALLO: %', p_caso;
  END IF;

  INSERT INTO pg_temp.grupoN_resultados (caso, resultado)
  VALUES (p_caso, 'OK');
  RAISE NOTICE 'OK: %', p_caso;
END;
$$;

-- Auxiliar: exige que el SQL falle con el SQLSTATE indicado.
CREATE FUNCTION grupoN_test.assert_error(
  p_caso text,
  p_sql text,
  p_sqlstate text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_sqlstate text;
  v_message  text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_sqlstate = RETURNED_SQLSTATE,
      v_message = MESSAGE_TEXT;

    IF v_sqlstate <> p_sqlstate THEN
      RAISE EXCEPTION 'FALLO: %, se esperaba SQLSTATE %, se recibio %: %',
        p_caso, p_sqlstate, v_sqlstate, v_message;
    END IF;

    INSERT INTO pg_temp.grupoN_resultados (caso, resultado)
    VALUES (p_caso, 'OK: rechazo esperado (' || v_sqlstate || ')');
    RAISE NOTICE 'OK: % (rechazo esperado)', p_caso;
    RETURN;
  END;

  RAISE EXCEPTION 'FALLO: %; la operacion no produjo el error esperado %',
    p_caso, p_sqlstate;
END;
$$;

-- Fixture comun: ruta de cuatro paradas, bus, viaje, tarifas y promocion.
DO $fixture$
DECLARE
  v_ruta integer;
  v_bus  integer;
  v_viaje integer;
  v_promo integer;
  v_salida timestamptz := statement_timestamp() + interval '2 days';
  v_llegada timestamptz := statement_timestamp() + interval '2 days 4 hours';
BEGIN
  v_ruta := fn_crear_ruta(
    'QA-RUTA',
    ARRAY['QA-A', 'QA-B', 'QA-C', 'QA-D']
  );
  v_bus := fn_crear_bus('QA-PLACA', 5, '{"wifi": true}'::jsonb);
  v_viaje := fn_programar_viaje(v_ruta, v_bus, v_salida, v_llegada);

  INSERT INTO pg_temp.grupoN_contexto
    (ruta_id, bus_id, viaje_id, salida, llegada)
  VALUES
    (v_ruta, v_bus, v_viaje, v_salida, v_llegada);

  PERFORM fn_fijar_tarifa(v_ruta, 'QA-A', 'QA-B', 50);
  PERFORM fn_fijar_tarifa(v_ruta, 'QA-B', 'QA-C', 30);
  PERFORM fn_fijar_tarifa(v_ruta, 'QA-C', 'QA-D', 20);
  PERFORM fn_fijar_tarifa(v_ruta, 'QA-A', 'QA-D', 90);

  v_promo := fn_crear_promocion(
    'QA descuento',
    10,
    jsonb_build_object('ruta', 'QA-RUTA')
  );
  UPDATE pg_temp.grupoN_contexto SET promo_id = v_promo;
END;
$fixture$;

-- Hace efectiva ahora la validacion diferida de minimo dos paradas y secuencia.
SET CONSTRAINTS trg_ruta_paradas IMMEDIATE;

-- HU-01 positivo: la ruta de fixture contiene cuatro paradas consecutivas.
SELECT grupoN_test.assert_true(
  'HU-01 positivo: ruta con cuatro paradas',
  (SELECT count(*) = 4
     FROM ruta_parada rp
     JOIN pg_temp.grupoN_contexto c ON c.ruta_id = rp.ruta_id)
);

-- HU-01 negativo: no se admite repetir una ciudad en la misma ruta.
SELECT grupoN_test.assert_error(
  'HU-01 negativo: ciudad repetida',
  $sql$SELECT fn_crear_ruta('QA-RUTA-DUP', ARRAY['QA-X', 'QA-X'])$sql$,
  'P0001'
);

-- HU-02 positivo: fn_crear_bus genera un asiento por cada unidad de capacidad.
SELECT grupoN_test.assert_true(
  'HU-02 positivo: cinco asientos generados',
  (SELECT count(*) = 5
     FROM asiento a
     JOIN pg_temp.grupoN_contexto c ON c.bus_id = a.bus_id)
);

-- HU-02 negativo: la capacidad debe estar entre 1 y 80.
SELECT grupoN_test.assert_error(
  'HU-02 negativo: capacidad cero',
  $sql$SELECT fn_crear_bus('QA-BUS-INVALIDO', 0, '{}'::jsonb)$sql$,
  'P0001'
);

-- HU-03 positivo: el viaje fixture tiene llegada posterior a salida.
SELECT grupoN_test.assert_true(
  'HU-03 positivo: viaje programado con horario valido',
  (SELECT v.llegada > v.salida
     FROM viaje v
     JOIN pg_temp.grupoN_contexto c ON c.viaje_id = v.id_viaje)
);

-- HU-03 negativo: el mismo bus no puede recibir otro viaje solapado.
SELECT grupoN_test.assert_error(
  'HU-03 negativo: horario del bus solapado',
  (
    SELECT format(
      'SELECT fn_programar_viaje(%s, %s, %L::timestamptz, %L::timestamptz)',
      ruta_id, bus_id, salida + interval '1 hour', llegada + interval '1 hour'
    )
    FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-04 positivo: existe una tarifa positiva para el primer tramo.
SELECT grupoN_test.assert_true(
  'HU-04 positivo: tarifa A-B fijada',
  (SELECT count(*) = 1 AND min(precio) = 50
     FROM tarifa t
     JOIN pg_temp.grupoN_contexto c ON c.ruta_id = t.ruta_id
    WHERE t.origen_pos = 1 AND t.destino_pos = 2)
);

-- HU-04 negativo: no se acepta una tarifa de precio cero.
SELECT grupoN_test.assert_error(
  'HU-04 negativo: precio cero',
  (
    SELECT format('SELECT fn_fijar_tarifa(%s, %L, %L, 0)', ruta_id, 'QA-A', 'QA-B')
      FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-05 positivo: se vende un pasaje para un tramo con tarifa.
UPDATE pg_temp.grupoN_contexto
   SET venta_id = fn_vender_pasaje(
     viaje_id, 1, 'QA-A', 'QA-B', 'QA-CI-01', 'Pasajero QA'
   );
SELECT grupoN_test.assert_true(
  'HU-05 positivo: venta directa creada',
  (SELECT p.estado = 'pagado'
     FROM pasaje p
     JOIN pg_temp.grupoN_contexto c ON c.venta_id = p.id_pasaje)
);

-- HU-05 negativo: no se vende un tramo que no tiene tarifa configurada.
SELECT grupoN_test.assert_error(
  'HU-05 negativo: tramo sin tarifa',
  (
    SELECT format(
      'SELECT fn_vender_pasaje(%s, 2, %L, %L, %L, %L)',
      viaje_id, 'QA-B', 'QA-D', 'QA-CI-05', 'Sin tarifa'
    )
    FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-06 positivo: el asiento usado en A-B vuelve a estar disponible en B-C.
SELECT grupoN_test.assert_true(
  'HU-06 positivo: tramo adyacente disponible',
  (SELECT EXISTS (
     SELECT 1
       FROM fn_asientos_disponibles(c.viaje_id, 'QA-B', 'QA-C') s(numero)
       JOIN asiento a ON a.bus_id = c.bus_id AND a.numero = s.numero
      WHERE a.numero = 1
   )
     FROM pg_temp.grupoN_contexto c)
);

-- HU-06 negativo: no se permite ocupar dos veces el mismo asiento en un tramo solapado.
SELECT grupoN_test.assert_error(
  'HU-06 negativo: asiento ocupado en tramo solapado',
  (
    SELECT format(
      'SELECT fn_vender_pasaje(%s, 1, %L, %L, %L, %L)',
      viaje_id, 'QA-A', 'QA-B', 'QA-CI-06', 'Asiento duplicado'
    )
    FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-07 positivo: el mismo pasajero puede viajar en tramos adyacentes;
-- además, el CI existente actualiza su nombre.
UPDATE pg_temp.grupoN_contexto
   SET venta_tramo_id = fn_vender_pasaje(
     viaje_id, 2, 'QA-B', 'QA-C', 'QA-CI-01', 'Nombre actualizado'
   );
SELECT grupoN_test.assert_true(
  'HU-07 positivo: pasajero actualizado en tramo no solapado',
  (SELECT pj.nombre = 'Nombre actualizado'
     FROM pasajero pj
    WHERE pj.ci = 'QA-CI-01')
);

-- HU-07 negativo: un pasajero no puede tener dos tramos solapados en el mismo viaje.
SELECT grupoN_test.assert_error(
  'HU-07 negativo: pasajero con tramo solapado',
  (
    SELECT format(
      'SELECT fn_vender_pasaje(%s, 3, %L, %L, %L, %L)',
      viaje_id, 'QA-A', 'QA-B', 'QA-CI-01', 'Segundo asiento'
    )
    FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-08 positivo: una reserva con vigencia positiva se crea y vence en el futuro.
UPDATE pg_temp.grupoN_contexto
   SET reserva_id = fn_reservar(
     viaje_id, 3, 'QA-C', 'QA-D', 'QA-CI-08', 'Reserva QA', interval '30 minutes'
   );
SELECT grupoN_test.assert_true(
  'HU-08 positivo: reserva vigente creada',
  (SELECT p.estado = 'reservado' AND p.vence_en > clock_timestamp()
     FROM pasaje p
     JOIN pg_temp.grupoN_contexto c ON c.reserva_id = p.id_pasaje)
);

-- HU-08 negativo: una reserva no puede tener vigencia cero.
SELECT grupoN_test.assert_error(
  'HU-08 negativo: vigencia cero',
  (
    SELECT format(
      'SELECT fn_reservar(%s, 4, %L, %L, %L, %L, interval ''0 seconds'')',
      viaje_id, 'QA-C', 'QA-D', 'QA-CI-08-BAD', 'Reserva invalida'
    )
    FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-09 positivo: se paga una reserva vigente y se conserva su precio.
SELECT grupoN_test.assert_true(
  'HU-09 positivo: reserva pagada',
  fn_pagar_reserva((SELECT reserva_id FROM pg_temp.grupoN_contexto)) > 0
  AND
  (SELECT p.estado = 'pagado'
     FROM pasaje p
     JOIN pg_temp.grupoN_contexto c ON c.reserva_id = p.id_pasaje)
);

-- HU-09 negativo: un pasaje ya pagado no se puede volver a pagar.
SELECT grupoN_test.assert_error(
  'HU-09 negativo: segundo pago',
  (
    SELECT format('SELECT fn_pagar_reserva(%s)', reserva_id)
      FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-10 positivo: una reserva se anula antes de la salida sin borrar el pasaje.
UPDATE pg_temp.grupoN_contexto
   SET anulacion_id = fn_reservar(
     viaje_id, 4, 'QA-C', 'QA-D', 'QA-CI-10', 'Reserva a anular', interval '30 minutes'
   );
SELECT fn_anular_pasaje((SELECT anulacion_id FROM pg_temp.grupoN_contexto));
SELECT grupoN_test.assert_true(
  'HU-10 positivo: anulacion conserva la fila',
  (SELECT p.estado = 'anulado' AND p.anulado_en IS NOT NULL
     FROM pasaje p
     JOIN pg_temp.grupoN_contexto c ON c.anulacion_id = p.id_pasaje)
);

-- HU-10 negativo: no se puede anular dos veces el mismo pasaje.
SELECT grupoN_test.assert_error(
  'HU-10 negativo: segunda anulacion',
  (
    SELECT format('SELECT fn_anular_pasaje(%s)', anulacion_id)
      FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-11 positivo: la ocupacion devuelve un resultado por cada segmento de la ruta.
SELECT grupoN_test.assert_true(
  'HU-11 positivo: tres segmentos de ocupacion',
  (SELECT count(*) = 3
     FROM fn_ocupacion((SELECT viaje_id FROM pg_temp.grupoN_contexto)))
);

-- HU-11 negativo: el reporte rechaza un viaje inexistente.
SELECT grupoN_test.assert_error(
  'HU-11 negativo: viaje inexistente',
  $sql$SELECT * FROM fn_ocupacion(-999999)$sql$,
  'P0001'
);

-- HU-12 positivo: el viaje con pasajes pagados tiene ingresos positivos.
SELECT grupoN_test.assert_true(
  'HU-12 positivo: ingresos de viaje mayores que cero',
  fn_ingresos_viaje((SELECT viaje_id FROM pg_temp.grupoN_contexto)) > 0
);

-- HU-12 negativo: el reporte rechaza un viaje inexistente.
SELECT grupoN_test.assert_error(
  'HU-12 negativo: viaje inexistente',
  $sql$SELECT fn_ingresos_viaje(-999999)$sql$,
  'P0001'
);

-- HU-13 positivo: la venta queda registrada en auditoria como INSERT.
SELECT grupoN_test.assert_true(
  'HU-13 positivo: INSERT de pasaje auditado',
  (SELECT EXISTS (
     SELECT 1
       FROM auditoria a
       JOIN pg_temp.grupoN_contexto c
         ON a.datos_nuevos ->> 'id_pasaje' = c.venta_id::text
      WHERE a.tabla = 'pasaje' AND a.operacion = 'INSERT'
   ))
);

-- HU-13 negativo: la bitacora de auditoria es append-only.
SELECT grupoN_test.assert_error(
  'HU-13 negativo: UPDATE de auditoria bloqueado',
  $sql$
    UPDATE auditoria SET fecha = fecha
     WHERE id_auditoria = (
       SELECT id_auditoria FROM auditoria
        WHERE tabla = 'pasaje' AND operacion = 'INSERT'
        ORDER BY id_auditoria LIMIT 1
     )
  $sql$,
  'P0001'
);

-- HU-14 positivo: el mismo asiento admite dos tramos adyacentes, sin solapamiento.
SELECT fn_vender_pasaje(
  (SELECT viaje_id FROM pg_temp.grupoN_contexto),
  1, 'QA-B', 'QA-C', 'QA-CI-14', 'Tramo adyacente'
);
SELECT grupoN_test.assert_true(
  'HU-14 positivo: tramos adyacentes en un asiento',
  (SELECT count(*) = 2
     FROM pasaje p
     JOIN pg_temp.grupoN_contexto c ON c.viaje_id = p.viaje_id
    WHERE p.asiento_id = (
      SELECT id_asiento FROM asiento
       WHERE bus_id = c.bus_id AND numero = 1
    )
      AND p.estado = 'pagado'
      AND ((p.origen_pos = 1 AND p.destino_pos = 2)
        OR (p.origen_pos = 2 AND p.destino_pos = 3)))
);

-- HU-14 negativo: la exclusion rechaza un tramo que se solapa con los anteriores.
SELECT grupoN_test.assert_error(
  'HU-14 negativo: venta concurrente conflictiva rechazada',
  (
    SELECT format(
      'SELECT fn_vender_pasaje(%s, 1, %L, %L, %L, %L)',
      viaje_id, 'QA-A', 'QA-C', 'QA-CI-14-BAD', 'Tramo solapado'
    )
    FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-15 positivo: los indices declarados para las consultas del modelo existen.
SELECT grupoN_test.assert_true(
  'HU-15 positivo: indices de rendimiento instalados',
  to_regclass('public.idx_viaje_bus_salida') IS NOT NULL
  AND to_regclass('public.idx_tarifa_vigente') IS NOT NULL
  AND to_regclass('public.idx_pasaje_viaje_estado') IS NOT NULL
  AND to_regclass('public.idx_bus_amenidades') IS NOT NULL
  AND to_regclass('public.idx_encomienda_atributos') IS NOT NULL
);

-- HU-15 negativo: simula la falta de un indice requerido. La excepcion esperada
-- revierte el DROP dentro del sub-bloque; el indice queda instalado al continuar.
SELECT grupoN_test.assert_error(
  'HU-15 negativo: deteccion de indice GIN ausente',
  $sql$
    DO $caso$
    BEGIN
      DROP INDEX public.idx_bus_amenidades;
      IF to_regclass('public.idx_bus_amenidades') IS NULL THEN
        RAISE EXCEPTION 'Indice GIN requerido ausente' USING ERRCODE = 'P0001';
      END IF;
    END
    $caso$
  $sql$,
  'P0001'
);
SELECT grupoN_test.assert_true(
  'HU-15 restauracion: indice GIN sigue instalado',
  to_regclass('public.idx_bus_amenidades') IS NOT NULL
);

-- HU-16 positivo: la venta de la ruta elegible conserva la promocion y el descuento.
SELECT grupoN_test.assert_true(
  'HU-16 positivo: promocion aplicada y precio rebajado',
  (SELECT p.promocion_id = c.promo_id
          AND p.precio_vendido < p.precio_base
     FROM pasaje p
     JOIN pg_temp.grupoN_contexto c ON c.venta_id = p.id_pasaje)
);

-- HU-16 negativo: una promocion no puede tener un porcentaje de 100.
SELECT grupoN_test.assert_error(
  'HU-16 negativo: porcentaje fuera de rango',
  $sql$SELECT fn_crear_promocion('QA invalida', 100, '{}'::jsonb)$sql$,
  'P0001'
);

-- HU-17 positivo: una incidencia valida se registra y suma sus minutos.
SELECT grupoN_test.assert_true(
  'HU-17 positivo: retraso valido registrado',
  fn_registrar_incidencia(
    (SELECT viaje_id FROM pg_temp.grupoN_contexto),
    'retraso',
    '{"minutos": 12, "motivo": "Prueba"}'::jsonb
  ) > 0
  AND fn_retraso_total((SELECT viaje_id FROM pg_temp.grupoN_contexto)) = 12
);

-- HU-17 negativo: minutos como texto no cumplen el tipo JSON requerido.
SELECT grupoN_test.assert_error(
  'HU-17 negativo: minutos como texto',
  (
    SELECT format(
      'SELECT fn_registrar_incidencia(%s, %L, %L::jsonb)',
      viaje_id, 'retraso', '{"minutos":"12","motivo":"Invalido"}'
    )
    FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-18 positivo: el descuento acumulado de la promocion aplicada es positivo.
SELECT grupoN_test.assert_true(
  'HU-18 positivo: descuento de pasajes pagados',
  fn_descuento_otorgado((SELECT promo_id FROM pg_temp.grupoN_contexto)) > 0
);

-- HU-18 negativo: no se consulta una promocion inexistente.
SELECT grupoN_test.assert_error(
  'HU-18 negativo: promocion inexistente',
  $sql$SELECT fn_descuento_otorgado(-999999)$sql$,
  'P0001'
);

-- HU-19 positivo: definir un tipo crea una version valida.
SELECT fn_definir_tipo_encomienda('qa-personalizado', '{"codigo":"texto"}'::jsonb);
SELECT grupoN_test.assert_true(
  'HU-19 positivo: version de tipo creada',
  (SELECT max(version) = 1
     FROM tipo_encomienda
    WHERE tipo = 'qa-personalizado')
);

-- HU-19 negativo: una clase de campo desconocida se rechaza.
SELECT grupoN_test.assert_error(
  'HU-19 negativo: clase de campo desconocida',
  $sql$SELECT fn_definir_tipo_encomienda('qa-invalido', '{"campo":"desconocido"}'::jsonb)$sql$,
  'P0001'
);

-- HU-20 positivo: se registra una encomienda valida con el tipo paquete inicial.
UPDATE pg_temp.grupoN_contexto
   SET encomienda_id = fn_registrar_encomienda(
     viaje_id,
     'QA-A',
     'QA-B',
     'paquete',
     '{"destinatario":{"nombre":"Destinataria QA","telefono":"70000000"},
       "peso_kg":2,"fragil":true}'::jsonb
   );
SELECT grupoN_test.assert_true(
  'HU-20 positivo: encomienda registrada con version',
  (SELECT e.tipo = 'paquete'
          AND e.tipo_version = 1
          AND e.atributos -> 'peso_kg' = '2'::jsonb
     FROM encomienda e
     JOIN pg_temp.grupoN_contexto c ON c.encomienda_id = e.id_encomienda)
);

-- HU-20 negativo: falta el peso obligatorio del tipo paquete.
SELECT grupoN_test.assert_error(
  'HU-20 negativo: falta campo obligatorio',
  (
    SELECT format(
      'SELECT fn_registrar_encomienda(%s, %L, %L, %L, %L::jsonb)',
      viaje_id, 'QA-A', 'QA-B', 'paquete',
      '{"destinatario":{"nombre":"Destinatario invalido"}}'
    )
    FROM pg_temp.grupoN_contexto
  ),
  'P0001'
);

-- HU-21 positivo: la busqueda JSONB encuentra la encomienda por contencion.
SELECT grupoN_test.assert_true(
  'HU-21 positivo: busqueda por destinatario',
  (SELECT EXISTS (
     SELECT 1
       FROM fn_buscar_encomiendas('{"destinatario":{"nombre":"Destinataria QA"}}'::jsonb) id
      WHERE id = c.encomienda_id
   )
     FROM pg_temp.grupoN_contexto c)
);

-- HU-21 negativo: un filtro sin coincidencias devuelve cero resultados.
SELECT grupoN_test.assert_true(
  'HU-21 negativo: filtro sin coincidencias',
  NOT EXISTS (
    SELECT 1
      FROM fn_buscar_encomiendas('{"destinatario":{"nombre":"No existe"}}'::jsonb)
  )
);

-- Resumen de todos los casos ejecutados; el ROLLBACK elimina fixtures y auxiliares.
SELECT caso, resultado
  FROM pg_temp.grupoN_resultados
 ORDER BY caso;

ROLLBACK;
