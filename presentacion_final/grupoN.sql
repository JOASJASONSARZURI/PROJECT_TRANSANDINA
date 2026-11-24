-- =====================================================================
-- grupoN.sql  -  TransAndina (Proyecto Final BD2)
-- PostgreSQL 16 | script unico | base vacia | sin comandos de psql
-- Basado en transAndinaDBML.dbml (epicas 1 a 5 + anexo de integracion)
--
-- Orden del script:
--   0. Extension
--   1. Funciones puras de validacion (las usan los CHECK)
--   2. Tablas, restricciones e indices
--   3. Triggers (auditoria, solo-insercion, integridad)
--   4. Funciones del contrato tecnico (21 funciones + 1 vista)
--   5. Datos iniciales (tipos de encomienda)
--
-- Decisiones de diseno importantes:
--   * Tramo = int4range(origen_pos, destino_pos) = [origen, destino).
--     Bajar y subir en la misma parada NO se solapa.
--   * Concurrencia (HU-14): la garantia real son las restricciones EXCLUDE
--     de la tabla pasaje (asiento y pasajero). Las funciones tambien
--     verifican antes de insertar para dar un mensaje claro.
--   * Vencimiento de reservas (HU-08): se evalua con clock_timestamp()
--     en cada consulta (nunca con un now() fijo de la transaccion).
--     Como una restriccion EXCLUDE no puede usar la hora actual, al
--     vender/reservar se marcan como 'vencido' las reservas vencidas del
--     mismo asiento/pasajero antes de insertar. Las consultas igual
--     filtran por vence_en, sin depender de esa limpieza.
--   * Los precios (precio_base, precio_vendido) quedan congelados: un
--     trigger impide modificarlos.
-- =====================================================================

-- =====================================================================
-- 0. EXTENSION (necesaria para EXCLUDE con igualdad + rangos)
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- =====================================================================
-- 1. FUNCIONES PURAS DE VALIDACION (IMMUTABLE, usadas en CHECK)
--    Siempre devuelven true/false (nunca NULL: un CHECK acepta NULL).
-- =====================================================================

-- HU-17: forma valida de los datos de una incidencia segun su tipo.
CREATE OR REPLACE FUNCTION fn_incidencia_valida(p_tipo text, p_datos jsonb)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_min numeric;
BEGIN
  IF p_datos IS NULL OR jsonb_typeof(p_datos) IS DISTINCT FROM 'object' THEN
    RETURN false;
  END IF;

  IF p_tipo = 'retraso' THEN
    -- minutos: numero JSON (no texto), entero y mayor que cero
    IF jsonb_typeof(p_datos -> 'minutos') IS DISTINCT FROM 'number' THEN
      RETURN false;
    END IF;
    v_min := (p_datos ->> 'minutos')::numeric;
    IF v_min <= 0 OR v_min <> trunc(v_min) OR v_min > 2147483647 THEN
      RETURN false;
    END IF;
    RETURN COALESCE(jsonb_typeof(p_datos -> 'motivo') = 'string'
                    AND btrim(p_datos ->> 'motivo') <> '', false);

  ELSIF p_tipo = 'averia' THEN
    RETURN COALESCE(jsonb_typeof(p_datos -> 'descripcion') = 'string'
                    AND btrim(p_datos ->> 'descripcion') <> ''
                    AND jsonb_typeof(p_datos -> 'requiere_cambio_bus') = 'boolean', false);

  ELSIF p_tipo = 'control' THEN
    RETURN COALESCE(jsonb_typeof(p_datos -> 'lugar') = 'string'
                    AND btrim(p_datos ->> 'lugar') <> ''
                    AND jsonb_typeof(p_datos -> 'resultado') = 'string'
                    AND (p_datos ->> 'resultado') IN ('sin novedad', 'observado'), false);
  END IF;

  RETURN false;
END;
$$;

-- HU-19: definicion valida de campos de un tipo de encomienda.
-- {"campo": "clase"} con clase en texto | numero | numero_positivo | si_no.
-- 'destinatario' es una clave reservada (se valida aparte en HU-20).
CREATE OR REPLACE FUNCTION fn_campos_validos(p_campos jsonb)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  r record;
BEGIN
  IF p_campos IS NULL OR jsonb_typeof(p_campos) IS DISTINCT FROM 'object' THEN
    RETURN false;
  END IF;
  FOR r IN SELECT key AS k, value AS v FROM jsonb_each(p_campos) LOOP
    IF btrim(r.k) = '' OR r.k = 'destinatario' THEN
      RETURN false;
    END IF;
    IF jsonb_typeof(r.v) <> 'string'
       OR (r.v #>> '{}') NOT IN ('texto', 'numero', 'numero_positivo', 'si_no') THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
END;
$$;

-- HU-20: toda encomienda tiene destinatario.nombre (texto no vacio);
-- destinatario.telefono es opcional; si se envia, debe ser texto.
CREATE OR REPLACE FUNCTION fn_destinatario_valido(p_atributos jsonb)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_d   jsonb;
  v_tel text;
BEGIN
  IF p_atributos IS NULL OR jsonb_typeof(p_atributos) IS DISTINCT FROM 'object' THEN
    RETURN false;
  END IF;
  v_d := p_atributos -> 'destinatario';
  IF jsonb_typeof(v_d) IS DISTINCT FROM 'object' THEN
    RETURN false;
  END IF;
  IF jsonb_typeof(v_d -> 'nombre') IS DISTINCT FROM 'string'
     OR btrim(v_d ->> 'nombre') = '' THEN
    RETURN false;
  END IF;
  v_tel := jsonb_typeof(v_d -> 'telefono');
  RETURN v_tel IS NULL OR v_tel = 'string';
END;
$$;

-- =====================================================================
-- 2. TABLAS
-- =====================================================================

-- ---------- EPICA 1: CONFIGURACION ----------

-- HU-01: catalogo de ciudades (cada ciudad se guarda una sola vez)
CREATE TABLE ciudad (
  nombre text PRIMARY KEY,
  CONSTRAINT ck_ciudad_nombre CHECK (btrim(nombre) <> '')
);

-- HU-01: ruta con codigo unico
CREATE TABLE ruta (
  id_ruta integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo  text NOT NULL,
  CONSTRAINT uq_ruta_codigo UNIQUE (codigo),
  CONSTRAINT ck_ruta_codigo CHECK (btrim(codigo) <> '')
);

-- HU-01: paradas ordenadas. El orden es dato de negocio (columna posicion).
CREATE TABLE ruta_parada (
  ruta_id       integer NOT NULL REFERENCES ruta (id_ruta),
  ciudad_nombre text    NOT NULL REFERENCES ciudad (nombre),
  posicion      integer NOT NULL,
  CONSTRAINT pk_ruta_parada PRIMARY KEY (ruta_id, posicion),
  CONSTRAINT uq_ruta_ciudad UNIQUE (ruta_id, ciudad_nombre),
  CONSTRAINT ck_posicion_positiva CHECK (posicion >= 1)
);

-- HU-02: buses con amenidades variables en JSONB
CREATE TABLE bus (
  id_bus     integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  placa      text    NOT NULL,
  capacidad  integer NOT NULL,
  amenidades jsonb   NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT uq_bus_placa UNIQUE (placa),
  CONSTRAINT ck_bus_placa CHECK (btrim(placa) <> ''),
  CONSTRAINT ck_capacidad CHECK (capacidad BETWEEN 1 AND 80),
  CONSTRAINT ck_amenidades_objeto CHECK (jsonb_typeof(amenidades) = 'object')
);

-- HU-02: asientos 1..capacidad (los genera fn_crear_bus)
CREATE TABLE asiento (
  id_asiento integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bus_id     integer NOT NULL REFERENCES bus (id_bus),
  numero     integer NOT NULL,
  CONSTRAINT uq_asiento_bus_numero UNIQUE (bus_id, numero),
  CONSTRAINT ck_numero_positivo CHECK (numero >= 1)
);

-- HU-03: viaje = ruta recorrida por un bus. Un bus no puede tener viajes
-- cuyos horarios se crucen (EXCLUDE con rangos [salida, llegada)).
CREATE TABLE viaje (
  id_viaje integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ruta_id  integer     NOT NULL REFERENCES ruta (id_ruta),
  bus_id   integer     NOT NULL REFERENCES bus (id_bus),
  salida   timestamptz NOT NULL,
  llegada  timestamptz NOT NULL,
  CONSTRAINT ck_llegada_posterior CHECK (llegada > salida),
  CONSTRAINT ex_viaje_bus_horario
    EXCLUDE USING gist (bus_id WITH =, tstzrange(salida, llegada, '[)') WITH &&)
);

-- HU-04: tarifas historicas (solo insercion). Vigente = mayor id_tarifa del par.
CREATE TABLE tarifa (
  id_tarifa   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ruta_id     integer       NOT NULL,
  origen_pos  integer       NOT NULL,
  destino_pos integer       NOT NULL,
  precio      numeric       NOT NULL,
  creada_en   timestamptz   NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ck_origen_antes_destino CHECK (origen_pos < destino_pos),
  CONSTRAINT ck_precio_positivo CHECK (precio > 0 AND precio < 'Infinity'::numeric),
  CONSTRAINT fk_tarifa_origen  FOREIGN KEY (ruta_id, origen_pos)
    REFERENCES ruta_parada (ruta_id, posicion),
  CONSTRAINT fk_tarifa_destino FOREIGN KEY (ruta_id, destino_pos)
    REFERENCES ruta_parada (ruta_id, posicion)
);

-- ---------- EPICA 2: VENTA ----------

-- HU-07: el pasajero se identifica por su CI
CREATE TABLE pasajero (
  ci     text PRIMARY KEY,
  nombre text NOT NULL,
  CONSTRAINT ck_ci_no_vacio     CHECK (btrim(ci) <> ''),
  CONSTRAINT ck_nombre_no_vacio CHECK (btrim(nombre) <> '')
);

-- HU-16: promociones con condiciones combinables (JSONB)
CREATE TABLE promocion (
  id_promocion integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre       text        NOT NULL,
  porcentaje   numeric     NOT NULL,
  condiciones  jsonb       NOT NULL DEFAULT '{}'::jsonb,
  creada_en    timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ck_promo_nombre CHECK (btrim(nombre) <> ''),
  CONSTRAINT ck_promo_porcentaje CHECK (porcentaje > 0 AND porcentaje < 100),
  CONSTRAINT ck_promo_cond_objeto CHECK (jsonb_typeof(condiciones) = 'object'),
  CONSTRAINT ck_promo_claves_validas CHECK (
    (condiciones - ARRAY['ruta', 'desde', 'hasta', 'dias_semana', 'antelacion_min_dias'])
      = '{}'::jsonb)
);

-- HU-05/08/09/10: ventas y reservas en una sola tabla con estado.
--   pagado | reservado | vencido | anulado   (nunca se borra)
CREATE TABLE pasaje (
  id_pasaje      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  viaje_id       integer     NOT NULL REFERENCES viaje (id_viaje),
  asiento_id     integer     NOT NULL REFERENCES asiento (id_asiento),
  pasajero_ci    text        NOT NULL REFERENCES pasajero (ci),
  origen_pos     integer     NOT NULL,
  destino_pos    integer     NOT NULL,
  precio_base    numeric     NOT NULL,
  precio_vendido numeric     NOT NULL,
  estado         text        NOT NULL,
  vence_en       timestamptz,
  promocion_id   integer     REFERENCES promocion (id_promocion),
  creado_en      timestamptz NOT NULL DEFAULT clock_timestamp(),
  anulado_en     timestamptz,
  CONSTRAINT ck_pasaje_tramo CHECK (origen_pos < destino_pos),
  CONSTRAINT ck_pasaje_precio_base CHECK (precio_base > 0),
  CONSTRAINT ck_pasaje_precio_vendido CHECK (precio_vendido > 0 AND precio_vendido <= precio_base),
  CONSTRAINT ck_pasaje_estado CHECK (estado IN ('pagado', 'reservado', 'vencido', 'anulado')),
  CONSTRAINT ck_reserva_con_vencimiento CHECK (estado NOT IN ('reservado', 'vencido') OR vence_en IS NOT NULL),
  CONSTRAINT ck_anulado_fecha CHECK ((estado = 'anulado') = (anulado_en IS NOT NULL)),
  -- HU-14 / HU-06: un asiento no puede tener tramos solapados activos
  CONSTRAINT ex_pasaje_asiento
    EXCLUDE USING gist (viaje_id WITH =, asiento_id WITH =, int4range(origen_pos, destino_pos) WITH &&)
    WHERE (estado IN ('pagado', 'reservado')),
  -- HU-07: un pasajero no puede ocupar dos asientos en tramos solapados del mismo viaje
  CONSTRAINT ex_pasaje_pasajero
    EXCLUDE USING gist (viaje_id WITH =, pasajero_ci WITH =, int4range(origen_pos, destino_pos) WITH &&)
    WHERE (estado IN ('pagado', 'reservado'))
);

-- ---------- EPICA 3: REPORTES Y CONTROL ----------

-- HU-17: incidencias; la forma de datos depende del tipo (JSONB validado en la base)
CREATE TABLE incidencia (
  id_incidencia integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  viaje_id      integer     NOT NULL REFERENCES viaje (id_viaje),
  tipo          text        NOT NULL,
  datos         jsonb       NOT NULL,
  creada_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ck_incidencia_tipo CHECK (tipo IN ('retraso', 'averia', 'control')),
  CONSTRAINT ck_incidencia_datos_objeto CHECK (jsonb_typeof(datos) = 'object'),
  CONSTRAINT ck_incidencia_datos_validos CHECK (fn_incidencia_valida(tipo, datos))
);

-- HU-13: auditoria (sin FK: el historial debe sobrevivir a cualquier cambio)
CREATE TABLE auditoria (
  id_auditoria     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tabla            text        NOT NULL,
  operacion        text        NOT NULL,
  fecha            timestamptz NOT NULL DEFAULT clock_timestamp(),
  datos_anteriores jsonb,
  datos_nuevos     jsonb,
  CONSTRAINT ck_auditoria_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
  CONSTRAINT ck_auditoria_tabla CHECK (tabla IN ('pasaje', 'tarifa'))
);

-- ---------- EPICA 5: ENCOMIENDAS ----------

-- HU-19: tipos versionados. Redefinir un tipo inserta la version siguiente.
CREATE TABLE tipo_encomienda (
  tipo           text        NOT NULL,
  version        integer     NOT NULL,
  campos         jsonb       NOT NULL DEFAULT '{}'::jsonb,
  vigencia_desde timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT pk_tipo_encomienda PRIMARY KEY (tipo, version),
  CONSTRAINT ck_tipo_no_vacio CHECK (btrim(tipo) <> ''),
  CONSTRAINT ck_tipo_version CHECK (version >= 1),
  CONSTRAINT ck_tipo_campos_objeto CHECK (jsonb_typeof(campos) = 'object'),
  CONSTRAINT ck_tipo_campos_clases CHECK (fn_campos_validos(campos))
);

-- HU-20: encomiendas; apuntan a la version exacta del tipo con que se validaron
CREATE TABLE encomienda (
  id_encomienda integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  viaje_id      integer     NOT NULL REFERENCES viaje (id_viaje),
  origen_pos    integer     NOT NULL,
  destino_pos   integer     NOT NULL,
  tipo          text        NOT NULL,
  tipo_version  integer     NOT NULL,   -- la asigna el trigger BEFORE INSERT
  atributos     jsonb       NOT NULL,
  creada_en     timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT ck_encomienda_tramo CHECK (origen_pos < destino_pos),
  CONSTRAINT ck_encomienda_atributos_objeto CHECK (jsonb_typeof(atributos) = 'object'),
  CONSTRAINT ck_encomienda_destinatario CHECK (fn_destinatario_valido(atributos)),
  CONSTRAINT fk_encomienda_tipo FOREIGN KEY (tipo, tipo_version)
    REFERENCES tipo_encomienda (tipo, version)
);

-- =====================================================================
-- 2b. INDICES (se justifican con EXPLAIN ANALYZE en el informe de rendimiento)
-- Los EXCLUDE de viaje y pasaje ya crean indices GiST utiles.
-- =====================================================================

-- HU-02: filtro de amenidades por contencion (@>)
CREATE INDEX idx_bus_amenidades ON bus USING gin (amenidades jsonb_path_ops);

-- HU-03
CREATE INDEX idx_viaje_bus_salida ON viaje (bus_id, salida);
CREATE INDEX idx_viaje_ruta ON viaje (ruta_id);

-- HU-04: tarifa vigente = mayor id del par
CREATE INDEX idx_tarifa_vigente ON tarifa (ruta_id, origen_pos, destino_pos, id_tarifa);

-- HU-05/06: ocupacion de un asiento por tramo dentro de un viaje
CREATE INDEX idx_pasaje_viaje_asiento ON pasaje (viaje_id, asiento_id, origen_pos, destino_pos);
-- HU-11/12 y manifiesto: pasajes de un viaje por estado
CREATE INDEX idx_pasaje_viaje_estado ON pasaje (viaje_id, estado);
-- HU-07: pasajes de un pasajero en un viaje
CREATE INDEX idx_pasaje_pasajero_viaje ON pasaje (pasajero_ci, viaje_id);
-- HU-18: descuento otorgado (solo pagados)
CREATE INDEX idx_pasaje_promocion ON pasaje (promocion_id) WHERE estado = 'pagado';

-- HU-17
CREATE INDEX idx_incidencia_viaje_tipo ON incidencia (viaje_id, tipo);

-- HU-13
CREATE INDEX idx_auditoria_tabla_fecha ON auditoria (tabla, fecha);

-- HU-20 / HU-21
CREATE INDEX idx_encomienda_atributos ON encomienda USING gin (atributos jsonb_path_ops);
CREATE INDEX idx_encomienda_viaje ON encomienda (viaje_id);

-- =====================================================================
-- 3. TRIGGERS
-- =====================================================================

-- ---------- Tablas de solo insercion (HU-04, HU-13, HU-19) ----------
CREATE OR REPLACE FUNCTION fn_bloquear_cambios()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'La tabla % es historica: no se permite %', TG_TABLE_NAME, TG_OP;
END;
$$;

CREATE TRIGGER trg_tarifa_solo_insercion
  BEFORE UPDATE OR DELETE ON tarifa
  FOR EACH ROW EXECUTE FUNCTION fn_bloquear_cambios();

CREATE TRIGGER trg_auditoria_solo_insercion
  BEFORE UPDATE OR DELETE ON auditoria
  FOR EACH ROW EXECUTE FUNCTION fn_bloquear_cambios();

CREATE TRIGGER trg_tipo_encomienda_solo_insercion
  BEFORE UPDATE OR DELETE ON tipo_encomienda
  FOR EACH ROW EXECUTE FUNCTION fn_bloquear_cambios();

-- HU-10: nunca se borra un registro de venta
CREATE OR REPLACE FUNCTION fn_bloquear_borrado_pasaje()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Los pasajes nunca se borran: use la anulacion (fn_anular_pasaje)';
END;
$$;

CREATE TRIGGER trg_pasaje_no_borrar
  BEFORE DELETE ON pasaje
  FOR EACH ROW EXECUTE FUNCTION fn_bloquear_borrado_pasaje();

-- ---------- HU-13: auditoria generica ----------
CREATE OR REPLACE FUNCTION fn_auditar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Se registran cambios completados; una operacion rechazada revierte su transaccion.
  IF TG_OP = 'INSERT' THEN
    INSERT INTO auditoria (tabla, operacion, datos_anteriores, datos_nuevos)
    VALUES (TG_TABLE_NAME, TG_OP, NULL, to_jsonb(NEW));
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO auditoria (tabla, operacion, datos_anteriores, datos_nuevos)
    VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
  ELSE
    INSERT INTO auditoria (tabla, operacion, datos_anteriores, datos_nuevos)
    VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), NULL);
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_pasaje_auditoria
  AFTER INSERT OR UPDATE OR DELETE ON pasaje
  FOR EACH ROW EXECUTE FUNCTION fn_auditar();

CREATE TRIGGER trg_tarifa_auditoria
  AFTER INSERT OR UPDATE OR DELETE ON tarifa
  FOR EACH ROW EXECUTE FUNCTION fn_auditar();

-- ---------- HU-01: una ruta debe terminar con >= 2 paradas consecutivas ----------
CREATE OR REPLACE FUNCTION fn_ruta_validar_paradas()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_n   integer;
  v_max integer;
BEGIN
  SELECT count(*), max(posicion) INTO v_n, v_max
    FROM ruta_parada WHERE ruta_id = NEW.id_ruta;
  IF v_n < 2 THEN
    RAISE EXCEPTION 'La ruta % debe tener al menos dos paradas', NEW.codigo;
  END IF;
  IF v_max <> v_n THEN
    RAISE EXCEPTION 'Las posiciones de la ruta % deben ser consecutivas desde 1', NEW.codigo;
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_ruta_paradas
  AFTER INSERT ON ruta
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fn_ruta_validar_paradas();

-- ---------- HU-02: la capacidad del bus no cambia (los asientos ya existen) ----------
CREATE OR REPLACE FUNCTION fn_bus_capacidad_fija()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.capacidad <> OLD.capacidad THEN
    RAISE EXCEPTION 'La capacidad de un bus no se puede modificar';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bus_capacidad_fija
  BEFORE UPDATE OF capacidad ON bus
  FOR EACH ROW EXECUTE FUNCTION fn_bus_capacidad_fija();

-- ---------- HU-05: coherencia de un pasaje al insertarlo ----------
CREATE OR REPLACE FUNCTION fn_pasaje_validar_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_ruta integer;
  v_bus  integer;
BEGIN
  SELECT ruta_id, bus_id INTO v_ruta, v_bus FROM viaje WHERE id_viaje = NEW.viaje_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El viaje % no existe', NEW.viaje_id;
  END IF;
  IF NEW.estado NOT IN ('pagado', 'reservado') THEN
    RAISE EXCEPTION 'Un pasaje nuevo solo puede nacer pagado o reservado';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM asiento WHERE id_asiento = NEW.asiento_id AND bus_id = v_bus) THEN
    RAISE EXCEPTION 'El asiento no pertenece al bus del viaje %', NEW.viaje_id;
  END IF;
  IF (SELECT count(*) FROM ruta_parada
       WHERE ruta_id = v_ruta AND posicion IN (NEW.origen_pos, NEW.destino_pos)) <> 2 THEN
    RAISE EXCEPTION 'Origen y destino deben ser paradas de la ruta del viaje';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_pasaje_validar_insert
  BEFORE INSERT ON pasaje
  FOR EACH ROW EXECUTE FUNCTION fn_pasaje_validar_insert();

-- ---------- HU-04/09/10: precios congelados y transiciones validas ----------
--   reservado -> pagado | vencido | anulado ;  pagado -> anulado ;  vencido -> anulado
CREATE OR REPLACE FUNCTION fn_pasaje_validar_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.id_pasaje IS DISTINCT FROM OLD.id_pasaje
     OR NEW.creado_en IS DISTINCT FROM OLD.creado_en
     OR NEW.vence_en IS DISTINCT FROM OLD.vence_en THEN
    RAISE EXCEPTION 'El ID, la fecha de creacion y el vencimiento del pasaje no se modifican';
  END IF;

  IF NEW.viaje_id <> OLD.viaje_id
     OR NEW.asiento_id <> OLD.asiento_id
     OR NEW.pasajero_ci <> OLD.pasajero_ci
     OR NEW.origen_pos <> OLD.origen_pos
     OR NEW.destino_pos <> OLD.destino_pos
     OR NEW.precio_base <> OLD.precio_base
     OR NEW.precio_vendido <> OLD.precio_vendido
     OR NEW.promocion_id IS DISTINCT FROM OLD.promocion_id THEN
    RAISE EXCEPTION 'Los datos de venta de un pasaje (viaje, asiento, pasajero, tramo, precios, promocion) no se modifican';
  END IF;

  IF NEW.estado <> OLD.estado THEN
    IF NOT ((OLD.estado = 'reservado' AND NEW.estado IN ('pagado', 'vencido', 'anulado'))
         OR (OLD.estado = 'pagado'    AND NEW.estado = 'anulado')
         OR (OLD.estado = 'vencido'   AND NEW.estado = 'anulado')) THEN
      RAISE EXCEPTION 'Transicion de estado no permitida: % -> %', OLD.estado, NEW.estado;
    END IF;
  END IF;

  IF NEW.anulado_en IS DISTINCT FROM OLD.anulado_en
     AND NOT (OLD.estado IN ('reservado', 'pagado', 'vencido') AND NEW.estado = 'anulado') THEN
    RAISE EXCEPTION 'La fecha de anulacion solo se establece al anular el pasaje';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_pasaje_validar_update
  BEFORE UPDATE ON pasaje
  FOR EACH ROW EXECUTE FUNCTION fn_pasaje_validar_update();

-- ---------- HU-20: validacion de la encomienda en la base ----------
CREATE OR REPLACE FUNCTION fn_encomienda_validar()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_ruta    integer;
  v_version integer;
  v_campos  jsonb;
  r         record;
  v_val     jsonb;
BEGIN
  SELECT ruta_id INTO v_ruta FROM viaje WHERE id_viaje = NEW.viaje_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El viaje % no existe', NEW.viaje_id;
  END IF;

  IF NEW.atributos IS NULL OR jsonb_typeof(NEW.atributos) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Los atributos de la encomienda deben ser un objeto JSON';
  END IF;

  IF NOT fn_destinatario_valido(NEW.atributos) THEN
    RAISE EXCEPTION 'La encomienda requiere destinatario.nombre (texto no vacio)';
  END IF;

  IF NEW.origen_pos >= NEW.destino_pos
     OR (SELECT count(*) FROM ruta_parada
          WHERE ruta_id = v_ruta AND posicion IN (NEW.origen_pos, NEW.destino_pos)) <> 2 THEN
    RAISE EXCEPTION 'Origen y destino deben ser paradas de la ruta del viaje, con origen antes que destino';
  END IF;

  -- version vigente del tipo (la mayor)
  SELECT t.version, t.campos INTO v_version, v_campos
    FROM tipo_encomienda t
   WHERE t.tipo = NEW.tipo
   ORDER BY t.version DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El tipo de encomienda "%" no esta definido', NEW.tipo;
  END IF;
  NEW.tipo_version := v_version;

  -- cada campo obligatorio, con su clase (jsonb_typeof: "12" como texto NO es numero)
  FOR r IN SELECT key AS k, (value #>> '{}') AS clase FROM jsonb_each(v_campos) LOOP
    v_val := NEW.atributos -> r.k;
    IF v_val IS NULL OR jsonb_typeof(v_val) = 'null' THEN
      RAISE EXCEPTION 'Falta el dato obligatorio "%" del tipo "%"', r.k, NEW.tipo;
    END IF;

    IF r.clase = 'texto' THEN
      IF jsonb_typeof(v_val) <> 'string' OR btrim(v_val #>> '{}') = '' THEN
        RAISE EXCEPTION 'El dato "%" debe ser texto no vacio', r.k;
      END IF;
    ELSIF r.clase = 'numero' THEN
      IF jsonb_typeof(v_val) <> 'number' THEN
        RAISE EXCEPTION 'El dato "%" debe ser un numero', r.k;
      END IF;
    ELSIF r.clase = 'numero_positivo' THEN
      IF jsonb_typeof(v_val) <> 'number' OR (v_val #>> '{}')::numeric <= 0 THEN
        RAISE EXCEPTION 'El dato "%" debe ser un numero mayor que cero', r.k;
      END IF;
    ELSIF r.clase = 'si_no' THEN
      IF jsonb_typeof(v_val) <> 'boolean' THEN
        RAISE EXCEPTION 'El dato "%" debe ser verdadero o falso', r.k;
      END IF;
    ELSE
      RAISE EXCEPTION 'Clase desconocida "%" en la definicion del tipo', r.clase;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_encomienda_validar
  BEFORE INSERT ON encomienda
  FOR EACH ROW EXECUTE FUNCTION fn_encomienda_validar();

-- las encomiendas ya registradas no se reescriben
CREATE OR REPLACE FUNCTION fn_encomienda_inmutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.id_encomienda IS DISTINCT FROM OLD.id_encomienda
     OR NEW.viaje_id IS DISTINCT FROM OLD.viaje_id
     OR NEW.origen_pos IS DISTINCT FROM OLD.origen_pos
     OR NEW.destino_pos IS DISTINCT FROM OLD.destino_pos
     OR NEW.tipo IS DISTINCT FROM OLD.tipo
     OR NEW.tipo_version IS DISTINCT FROM OLD.tipo_version
     OR NEW.atributos IS DISTINCT FROM OLD.atributos
     OR NEW.creada_en IS DISTINCT FROM OLD.creada_en THEN
    RAISE EXCEPTION 'Una encomienda registrada no se modifica';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_encomienda_inmutable
  BEFORE UPDATE ON encomienda
  FOR EACH ROW EXECUTE FUNCTION fn_encomienda_inmutable();

-- =====================================================================
-- 4. FUNCIONES
-- =====================================================================

-- ---------- Auxiliares internas ----------

-- posicion de una ciudad dentro de una ruta (NULL si no pertenece)
CREATE OR REPLACE FUNCTION fn_pos_parada(p_ruta integer, p_ciudad text)
RETURNS integer
LANGUAGE sql STABLE
AS $$
  SELECT posicion FROM ruta_parada WHERE ruta_id = p_ruta AND ciudad_nombre = p_ciudad
$$;

-- HU-16: promocion elegible para un viaje en el instante p_ahora.
-- Mayor descuento; empate -> la mas antigua. Fechas y dias en hora de Bolivia.
CREATE OR REPLACE FUNCTION fn_promocion_elegible(p_viaje integer, p_ahora timestamptz)
RETURNS integer
LANGUAGE sql STABLE
AS $$
  SELECT pr.id_promocion
    FROM viaje v
    JOIN ruta r ON r.id_ruta = v.ruta_id
    CROSS JOIN promocion pr
   WHERE v.id_viaje = p_viaje
     AND (pr.condiciones ->> 'ruta' IS NULL OR pr.condiciones ->> 'ruta' = r.codigo)
     AND (pr.condiciones ->> 'desde' IS NULL
          OR (v.salida AT TIME ZONE 'America/La_Paz')::date >= (pr.condiciones ->> 'desde')::date)
     AND (pr.condiciones ->> 'hasta' IS NULL
          OR (v.salida AT TIME ZONE 'America/La_Paz')::date <= (pr.condiciones ->> 'hasta')::date)
     AND (pr.condiciones -> 'dias_semana' IS NULL
          OR EXISTS (SELECT 1
                       FROM jsonb_array_elements_text(pr.condiciones -> 'dias_semana') AS d(x)
                      WHERE d.x::numeric = extract(isodow FROM (v.salida AT TIME ZONE 'America/La_Paz'))))
     AND (pr.condiciones ->> 'antelacion_min_dias' IS NULL
          OR ((v.salida AT TIME ZONE 'America/La_Paz')::date
              - (p_ahora AT TIME ZONE 'America/La_Paz')::date)
             >= (pr.condiciones ->> 'antelacion_min_dias')::numeric)
   ORDER BY pr.porcentaje DESC, pr.creada_en ASC, pr.id_promocion ASC
   LIMIT 1
$$;

-- Nucleo de HU-05 y HU-08: crea un pasaje pagado o una reserva.
CREATE OR REPLACE FUNCTION fn_pasaje_crear(
  p_viaje    integer,
  p_asiento  integer,
  p_origen   text,
  p_destino  text,
  p_ci       text,
  p_nombre   text,
  p_estado   text,
  p_vigencia interval
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_viaje      viaje%ROWTYPE;
  v_asiento_id integer;
  v_o          integer;
  v_d          integer;
  v_base       numeric;
  v_promo      integer;
  v_pct        numeric;
  v_final      numeric;
  v_ci         text := btrim(p_ci);
  v_nombre     text := btrim(p_nombre);
  v_ahora      timestamptz := clock_timestamp();
  v_id         integer;
BEGIN
  IF p_viaje IS NULL OR p_asiento IS NULL OR p_origen IS NULL OR p_destino IS NULL THEN
    RAISE EXCEPTION 'Viaje, asiento, origen y destino son obligatorios';
  END IF;
  IF v_ci IS NULL OR v_ci = '' THEN
    RAISE EXCEPTION 'El CI del pasajero es obligatorio';
  END IF;
  IF v_nombre IS NULL OR v_nombre = '' THEN
    RAISE EXCEPTION 'El nombre del pasajero es obligatorio';
  END IF;

  SELECT * INTO v_viaje FROM viaje WHERE id_viaje = p_viaje;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El viaje % no existe', p_viaje;
  END IF;
  IF v_viaje.salida <= v_ahora THEN
    RAISE EXCEPTION 'El viaje % ya salio: no se puede vender ni reservar', p_viaje;
  END IF;

  SELECT id_asiento INTO v_asiento_id
    FROM asiento WHERE bus_id = v_viaje.bus_id AND numero = p_asiento;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El asiento % no existe en el bus del viaje %', p_asiento, p_viaje;
  END IF;

  v_o := fn_pos_parada(v_viaje.ruta_id, p_origen);
  v_d := fn_pos_parada(v_viaje.ruta_id, p_destino);
  IF v_o IS NULL THEN
    RAISE EXCEPTION 'El origen "%" no es parada de la ruta del viaje', p_origen;
  END IF;
  IF v_d IS NULL THEN
    RAISE EXCEPTION 'El destino "%" no es parada de la ruta del viaje', p_destino;
  END IF;
  IF v_o >= v_d THEN
    RAISE EXCEPTION 'El origen debe estar antes que el destino en la ruta';
  END IF;

  -- HU-04: tarifa vigente = ultima fijada para el par
  SELECT precio INTO v_base
    FROM tarifa
   WHERE ruta_id = v_viaje.ruta_id AND origen_pos = v_o AND destino_pos = v_d
   ORDER BY id_tarifa DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No hay tarifa para el tramo % - %', p_origen, p_destino;
  END IF;

  -- HU-08: las reservas vencidas del mismo asiento/pasajero dejan de ocupar
  UPDATE pasaje
     SET estado = 'vencido'
   WHERE viaje_id = p_viaje
     AND estado = 'reservado'
     AND vence_en <= v_ahora
     AND (asiento_id = v_asiento_id OR pasajero_ci = v_ci);

  -- HU-05: sin solapamiento en el asiento (pagado o reserva vigente)
  IF EXISTS (SELECT 1 FROM pasaje
              WHERE viaje_id = p_viaje
                AND asiento_id = v_asiento_id
                AND origen_pos < v_d AND destino_pos > v_o
                AND estado IN ('pagado', 'reservado')) THEN
    RAISE EXCEPTION 'El asiento % ya esta ocupado en un tramo que se solapa', p_asiento;
  END IF;

  -- HU-07: el pasajero no ocupa dos asientos en tramos solapados del viaje
  IF EXISTS (SELECT 1 FROM pasaje
              WHERE viaje_id = p_viaje
                AND pasajero_ci = v_ci
                AND origen_pos < v_d AND destino_pos > v_o
                AND estado IN ('pagado', 'reservado')) THEN
    RAISE EXCEPTION 'El pasajero % ya tiene un asiento en un tramo que se solapa', v_ci;
  END IF;

  -- HU-16: promocion de mayor descuento; precio redondeado a centavos y congelado
  v_promo := fn_promocion_elegible(p_viaje, v_ahora);
  v_final := v_base;
  IF v_promo IS NOT NULL THEN
    SELECT porcentaje INTO v_pct FROM promocion WHERE id_promocion = v_promo;
    v_final := LEAST(round(v_base * (1 - v_pct / 100), 2), v_base);
  END IF;
  IF v_final <= 0 THEN
    RAISE EXCEPTION 'El precio final con descuento debe ser mayor que cero';
  END IF;

  -- HU-07: upsert del pasajero por CI (si existe, actualiza el nombre)
  INSERT INTO pasajero (ci, nombre) VALUES (v_ci, v_nombre)
  ON CONFLICT (ci) DO UPDATE SET nombre = EXCLUDED.nombre
  WHERE pasajero.nombre IS DISTINCT FROM EXCLUDED.nombre;

  INSERT INTO pasaje (viaje_id, asiento_id, pasajero_ci, origen_pos, destino_pos,
                      precio_base, precio_vendido, estado, vence_en, promocion_id, creado_en)
  VALUES (p_viaje, v_asiento_id, v_ci, v_o, v_d,
          v_base, v_final, p_estado,
          CASE WHEN p_estado = 'reservado' THEN v_ahora + p_vigencia END,
          v_promo, v_ahora)
  RETURNING id_pasaje INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------- CONFIGURACION ----------

-- HU-01
CREATE OR REPLACE FUNCTION fn_crear_ruta(p_codigo text, p_paradas text[])
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_id integer;
BEGIN
  IF p_codigo IS NULL OR btrim(p_codigo) = '' THEN
    RAISE EXCEPTION 'El codigo de la ruta es obligatorio';
  END IF;
  IF p_paradas IS NULL OR array_ndims(p_paradas) IS DISTINCT FROM 1
     OR cardinality(p_paradas) < 2 THEN
    RAISE EXCEPTION 'Una ruta necesita al menos dos paradas';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(p_paradas) AS c WHERE c IS NULL OR btrim(c) = '') THEN
    RAISE EXCEPTION 'Las paradas no pueden ser vacias';
  END IF;
  IF (SELECT count(DISTINCT c) FROM unnest(p_paradas) AS c) <> cardinality(p_paradas) THEN
    RAISE EXCEPTION 'Una ciudad no puede repetirse dentro de la misma ruta';
  END IF;
  IF EXISTS (SELECT 1 FROM ruta WHERE codigo = p_codigo) THEN
    RAISE EXCEPTION 'Ya existe una ruta con el codigo %', p_codigo;
  END IF;

  INSERT INTO ciudad (nombre)
  SELECT DISTINCT c FROM unnest(p_paradas) AS c
  ON CONFLICT (nombre) DO NOTHING;

  INSERT INTO ruta (codigo) VALUES (p_codigo) RETURNING id_ruta INTO v_id;

  INSERT INTO ruta_parada (ruta_id, ciudad_nombre, posicion)
  SELECT v_id, t.c, t.ord::integer
    FROM unnest(p_paradas) WITH ORDINALITY AS t(c, ord);

  RETURN v_id;
END;
$$;

-- HU-02
CREATE OR REPLACE FUNCTION fn_crear_bus(
  p_placa      text,
  p_capacidad  integer,
  p_amenidades jsonb DEFAULT '{}'
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_id integer;
  v_am jsonb := COALESCE(p_amenidades, '{}'::jsonb);
BEGIN
  IF p_placa IS NULL OR btrim(p_placa) = '' THEN
    RAISE EXCEPTION 'La placa es obligatoria';
  END IF;
  IF p_capacidad IS NULL OR p_capacidad NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'La capacidad debe estar entre 1 y 80 asientos';
  END IF;
  IF jsonb_typeof(v_am) <> 'object' THEN
    RAISE EXCEPTION 'Las amenidades deben ser un objeto JSON';
  END IF;
  IF EXISTS (SELECT 1 FROM bus WHERE placa = btrim(p_placa)) THEN
    RAISE EXCEPTION 'Ya existe un bus con la placa %', p_placa;
  END IF;

  INSERT INTO bus (placa, capacidad, amenidades)
  VALUES (btrim(p_placa), p_capacidad, v_am)
  RETURNING id_bus INTO v_id;

  INSERT INTO asiento (bus_id, numero)
  SELECT v_id, g FROM generate_series(1, p_capacidad) AS g;

  RETURN v_id;
END;
$$;

-- HU-02: filtro por contencion (@>), resultado ordenado por id
CREATE OR REPLACE FUNCTION fn_buses_con_amenidades(p_filtro jsonb)
RETURNS SETOF integer
LANGUAGE sql STABLE
AS $$
  SELECT b.id_bus
    FROM bus b
   WHERE b.amenidades @> COALESCE(p_filtro, '{}'::jsonb)
   ORDER BY b.id_bus
$$;

-- HU-03
CREATE OR REPLACE FUNCTION fn_programar_viaje(
  p_ruta    integer,
  p_bus     integer,
  p_salida  timestamptz,
  p_llegada timestamptz
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_id integer;
BEGIN
  IF p_ruta IS NULL OR NOT EXISTS (SELECT 1 FROM ruta WHERE id_ruta = p_ruta) THEN
    RAISE EXCEPTION 'La ruta % no existe', p_ruta;
  END IF;
  IF p_bus IS NULL OR NOT EXISTS (SELECT 1 FROM bus WHERE id_bus = p_bus) THEN
    RAISE EXCEPTION 'El bus % no existe', p_bus;
  END IF;
  IF p_salida IS NULL OR p_llegada IS NULL THEN
    RAISE EXCEPTION 'La salida y la llegada son obligatorias';
  END IF;
  IF p_llegada <= p_salida THEN
    RAISE EXCEPTION 'La llegada debe ser posterior a la salida';
  END IF;
  IF EXISTS (SELECT 1 FROM viaje
              WHERE bus_id = p_bus
                AND tstzrange(salida, llegada, '[)') && tstzrange(p_salida, p_llegada, '[)')) THEN
    RAISE EXCEPTION 'El bus % ya tiene un viaje que se cruza con ese horario', p_bus;
  END IF;

  INSERT INTO viaje (ruta_id, bus_id, salida, llegada)
  VALUES (p_ruta, p_bus, p_salida, p_llegada)
  RETURNING id_viaje INTO v_id;

  RETURN v_id;
END;
$$;

-- HU-04
CREATE OR REPLACE FUNCTION fn_fijar_tarifa(
  p_ruta    integer,
  p_origen  text,
  p_destino text,
  p_precio  numeric
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_o  integer;
  v_d  integer;
  v_id integer;
BEGIN
  IF p_ruta IS NULL OR NOT EXISTS (SELECT 1 FROM ruta WHERE id_ruta = p_ruta) THEN
    RAISE EXCEPTION 'La ruta % no existe', p_ruta;
  END IF;
  v_o := fn_pos_parada(p_ruta, p_origen);
  v_d := fn_pos_parada(p_ruta, p_destino);
  IF v_o IS NULL OR v_d IS NULL THEN
    RAISE EXCEPTION 'Origen y destino deben ser paradas de la ruta';
  END IF;
  IF v_o >= v_d THEN
    RAISE EXCEPTION 'El origen debe estar antes que el destino en la ruta';
  END IF;
  IF p_precio IS NULL OR NOT (p_precio > 0 AND p_precio < 'Infinity'::numeric) THEN
    RAISE EXCEPTION 'El precio debe ser mayor que cero';
  END IF;

  INSERT INTO tarifa (ruta_id, origen_pos, destino_pos, precio)
  VALUES (p_ruta, v_o, v_d, p_precio)
  RETURNING id_tarifa INTO v_id;

  RETURN v_id;
END;
$$;

-- ---------- VENTA Y PROMOCIONES ----------

-- HU-05
CREATE OR REPLACE FUNCTION fn_vender_pasaje(
  p_viaje   integer,
  p_asiento integer,
  p_origen  text,
  p_destino text,
  p_ci      text,
  p_nombre  text
) RETURNS integer
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN fn_pasaje_crear(p_viaje, p_asiento, p_origen, p_destino,
                         p_ci, p_nombre, 'pagado', NULL);
END;
$$;

-- HU-08
CREATE OR REPLACE FUNCTION fn_reservar(
  p_viaje    integer,
  p_asiento  integer,
  p_origen   text,
  p_destino  text,
  p_ci       text,
  p_nombre   text,
  p_vigencia interval
) RETURNS integer
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_vigencia IS NULL OR p_vigencia <= interval '0' THEN
    RAISE EXCEPTION 'La vigencia de la reserva debe ser mayor que cero';
  END IF;
  RETURN fn_pasaje_crear(p_viaje, p_asiento, p_origen, p_destino,
                         p_ci, p_nombre, 'reservado', p_vigencia);
END;
$$;

-- HU-09: se cobra el precio congelado de la reserva (no se recalcula)
CREATE OR REPLACE FUNCTION fn_pagar_reserva(p_reserva integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_p pasaje%ROWTYPE;
BEGIN
  SELECT * INTO v_p FROM pasaje WHERE id_pasaje = p_reserva FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La reserva % no existe', p_reserva;
  END IF;
  IF v_p.estado = 'pagado' THEN
    RAISE EXCEPTION 'El pasaje % ya esta pagado', p_reserva;
  END IF;
  IF v_p.estado = 'anulado' THEN
    RAISE EXCEPTION 'El pasaje % esta anulado', p_reserva;
  END IF;
  IF v_p.estado = 'vencido' OR v_p.vence_en <= clock_timestamp() THEN
    RAISE EXCEPTION 'La reserva % esta vencida', p_reserva;
  END IF;

  UPDATE pasaje SET estado = 'pagado' WHERE id_pasaje = p_reserva;
  RETURN p_reserva;
END;
$$;

-- HU-10: anula un pasaje o una reserva antes de la salida; no borra la fila
CREATE OR REPLACE FUNCTION fn_anular_pasaje(p_pasaje integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_p      pasaje%ROWTYPE;
  v_salida timestamptz;
BEGIN
  SELECT * INTO v_p FROM pasaje WHERE id_pasaje = p_pasaje FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El pasaje % no existe', p_pasaje;
  END IF;
  IF v_p.estado = 'anulado' THEN
    RAISE EXCEPTION 'El pasaje % ya esta anulado', p_pasaje;
  END IF;

  SELECT salida INTO v_salida FROM viaje WHERE id_viaje = v_p.viaje_id;
  IF v_salida <= clock_timestamp() THEN
    RAISE EXCEPTION 'El viaje ya salio: el pasaje % no se puede anular', p_pasaje;
  END IF;

  UPDATE pasaje
     SET estado = 'anulado', anulado_en = clock_timestamp()
   WHERE id_pasaje = p_pasaje;
END;
$$;

-- HU-16
CREATE OR REPLACE FUNCTION fn_crear_promocion(
  p_nombre      text,
  p_porcentaje  numeric,
  p_condiciones jsonb
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_c     jsonb := COALESCE(p_condiciones, '{}'::jsonb);
  v_key   text;
  v_el    jsonb;
  v_n     numeric;
  v_desde date;
  v_hasta date;
  v_id    integer;
BEGIN
  IF p_nombre IS NULL OR btrim(p_nombre) = '' THEN
    RAISE EXCEPTION 'El nombre de la promocion es obligatorio';
  END IF;
  IF p_porcentaje IS NULL OR NOT (p_porcentaje > 0 AND p_porcentaje < 100) THEN
    RAISE EXCEPTION 'El porcentaje debe ser mayor que 0 y menor que 100';
  END IF;
  IF jsonb_typeof(v_c) <> 'object' THEN
    RAISE EXCEPTION 'Las condiciones deben ser un objeto JSON';
  END IF;

  -- solo claves conocidas
  FOR v_key IN SELECT jsonb_object_keys(v_c) LOOP
    IF v_key NOT IN ('ruta', 'desde', 'hasta', 'dias_semana', 'antelacion_min_dias') THEN
      RAISE EXCEPTION 'Condicion desconocida: %', v_key;
    END IF;
  END LOOP;

  -- ruta: codigo existente
  IF v_c ? 'ruta' THEN
    IF jsonb_typeof(v_c -> 'ruta') <> 'string'
       OR NOT EXISTS (SELECT 1 FROM ruta WHERE codigo = v_c ->> 'ruta') THEN
      RAISE EXCEPTION 'La ruta de la condicion no existe';
    END IF;
  END IF;

  -- desde / hasta: fechas AAAA-MM-DD validas, y desde <= hasta
  IF v_c ? 'desde' THEN
    IF jsonb_typeof(v_c -> 'desde') <> 'string'
       OR (v_c ->> 'desde') !~ '^\d{4}-\d{2}-\d{2}$' THEN
      RAISE EXCEPTION 'La fecha "desde" debe tener formato AAAA-MM-DD';
    END IF;
    BEGIN
      v_desde := (v_c ->> 'desde')::date;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'La fecha "desde" no es valida';
    END;
  END IF;
  IF v_c ? 'hasta' THEN
    IF jsonb_typeof(v_c -> 'hasta') <> 'string'
       OR (v_c ->> 'hasta') !~ '^\d{4}-\d{2}-\d{2}$' THEN
      RAISE EXCEPTION 'La fecha "hasta" debe tener formato AAAA-MM-DD';
    END IF;
    BEGIN
      v_hasta := (v_c ->> 'hasta')::date;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'La fecha "hasta" no es valida';
    END;
  END IF;
  IF v_desde IS NOT NULL AND v_hasta IS NOT NULL AND v_desde > v_hasta THEN
    RAISE EXCEPTION 'El rango de fechas esta invertido (desde > hasta)';
  END IF;

  -- dias_semana: arreglo no vacio de enteros 1..7
  IF v_c ? 'dias_semana' THEN
    IF jsonb_typeof(v_c -> 'dias_semana') <> 'array'
       OR jsonb_array_length(v_c -> 'dias_semana') = 0 THEN
      RAISE EXCEPTION 'dias_semana debe ser un arreglo no vacio de enteros entre 1 y 7';
    END IF;
    FOR v_el IN SELECT value FROM jsonb_array_elements(v_c -> 'dias_semana') LOOP
      IF jsonb_typeof(v_el) <> 'number' THEN
        RAISE EXCEPTION 'dias_semana solo admite numeros entre 1 y 7';
      END IF;
      v_n := (v_el #>> '{}')::numeric;
      IF v_n <> trunc(v_n) OR v_n < 1 OR v_n > 7 THEN
        RAISE EXCEPTION 'dias_semana solo admite enteros entre 1 y 7';
      END IF;
    END LOOP;
  END IF;

  -- antelacion_min_dias: entero >= 0
  IF v_c ? 'antelacion_min_dias' THEN
    IF jsonb_typeof(v_c -> 'antelacion_min_dias') <> 'number' THEN
      RAISE EXCEPTION 'antelacion_min_dias debe ser un entero mayor o igual que cero';
    END IF;
    v_n := (v_c ->> 'antelacion_min_dias')::numeric;
    IF v_n <> trunc(v_n) OR v_n < 0 OR v_n > 36500 THEN
      RAISE EXCEPTION 'antelacion_min_dias debe ser un entero mayor o igual que cero';
    END IF;
  END IF;

  INSERT INTO promocion (nombre, porcentaje, condiciones)
  VALUES (btrim(p_nombre), p_porcentaje, v_c)
  RETURNING id_promocion INTO v_id;

  RETURN v_id;
END;
$$;

-- HU-16: promocion registrada en el pasaje (NULL si no hubo)
CREATE OR REPLACE FUNCTION fn_promocion_aplicada(p_pasaje integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_promo integer;
BEGIN
  SELECT promocion_id INTO v_promo FROM pasaje WHERE id_pasaje = p_pasaje;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El pasaje % no existe', p_pasaje;
  END IF;
  RETURN v_promo;
END;
$$;

-- ---------- REPORTES Y CONTROL ----------

-- HU-06: asientos libres para un tramo (reservas vencidas no ocupan)
CREATE OR REPLACE FUNCTION fn_asientos_disponibles(
  p_viaje   integer,
  p_origen  text,
  p_destino text
) RETURNS SETOF integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_ruta  integer;
  v_bus   integer;
  v_o     integer;
  v_d     integer;
  v_ahora timestamptz := clock_timestamp();
BEGIN
  SELECT ruta_id, bus_id INTO v_ruta, v_bus FROM viaje WHERE id_viaje = p_viaje;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El viaje % no existe', p_viaje;
  END IF;
  v_o := fn_pos_parada(v_ruta, p_origen);
  v_d := fn_pos_parada(v_ruta, p_destino);
  IF v_o IS NULL OR v_d IS NULL THEN
    RAISE EXCEPTION 'Origen y destino deben ser paradas de la ruta del viaje';
  END IF;
  IF v_o >= v_d THEN
    RAISE EXCEPTION 'El origen debe estar antes que el destino en la ruta';
  END IF;

  RETURN QUERY
  SELECT a.numero
    FROM asiento a
   WHERE a.bus_id = v_bus
     AND NOT EXISTS (SELECT 1 FROM pasaje p
                      WHERE p.viaje_id = p_viaje
                        AND p.asiento_id = a.id_asiento
                        AND p.origen_pos < v_d AND p.destino_pos > v_o
                        AND (p.estado = 'pagado'
                             OR (p.estado = 'reservado' AND p.vence_en > v_ahora)))
   ORDER BY a.numero;
END;
$$;

-- HU-11: una fila por segmento (paradas consecutivas), en orden de ruta
CREATE OR REPLACE FUNCTION fn_ocupacion(p_viaje integer)
RETURNS TABLE (desde text, hasta text, ocupados integer)
LANGUAGE plpgsql
AS $$
#variable_conflict use_column
DECLARE
  v_ahora timestamptz := clock_timestamp();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM viaje WHERE id_viaje = p_viaje) THEN
    RAISE EXCEPTION 'El viaje % no existe', p_viaje;
  END IF;

  RETURN QUERY
  SELECT pa.ciudad_nombre,
         pb.ciudad_nombre,
         c.n::integer
    FROM viaje v
    JOIN ruta_parada pa ON pa.ruta_id = v.ruta_id
    JOIN ruta_parada pb ON pb.ruta_id = v.ruta_id AND pb.posicion = pa.posicion + 1
    CROSS JOIN LATERAL (
      SELECT count(*) AS n
        FROM pasaje p
       WHERE p.viaje_id = v.id_viaje
         AND p.origen_pos <= pa.posicion
         AND p.destino_pos >= pb.posicion
         AND (p.estado = 'pagado'
              OR (p.estado = 'reservado' AND p.vence_en > v_ahora))
    ) c
   WHERE v.id_viaje = p_viaje
   ORDER BY pa.posicion;
END;
$$;

-- HU-12: suma solo pasajes pagados, al precio con que se vendieron
CREATE OR REPLACE FUNCTION fn_ingresos_viaje(p_viaje integer)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_total numeric;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM viaje WHERE id_viaje = p_viaje) THEN
    RAISE EXCEPTION 'El viaje % no existe', p_viaje;
  END IF;
  SELECT COALESCE(sum(precio_vendido), 0) INTO v_total
    FROM pasaje
   WHERE viaje_id = p_viaje AND estado = 'pagado';
  RETURN v_total;
END;
$$;

-- HU-18: suma (precio sin descuento - cobrado) solo de pasajes pagados
CREATE OR REPLACE FUNCTION fn_descuento_otorgado(p_promocion integer)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_total numeric;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM promocion WHERE id_promocion = p_promocion) THEN
    RAISE EXCEPTION 'La promocion % no existe', p_promocion;
  END IF;
  SELECT COALESCE(sum(precio_base - precio_vendido), 0) INTO v_total
    FROM pasaje
   WHERE promocion_id = p_promocion AND estado = 'pagado';
  RETURN v_total;
END;
$$;

-- HU-17
CREATE OR REPLACE FUNCTION fn_registrar_incidencia(
  p_viaje integer,
  p_tipo  text,
  p_datos jsonb
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_id integer;
BEGIN
  IF p_viaje IS NULL OR NOT EXISTS (SELECT 1 FROM viaje WHERE id_viaje = p_viaje) THEN
    RAISE EXCEPTION 'El viaje % no existe', p_viaje;
  END IF;
  IF p_tipo IS NULL OR p_tipo NOT IN ('retraso', 'averia', 'control') THEN
    RAISE EXCEPTION 'Tipo de incidencia desconocido: %', p_tipo;
  END IF;
  IF NOT fn_incidencia_valida(p_tipo, p_datos) THEN
    RAISE EXCEPTION 'Datos invalidos para la incidencia de tipo %', p_tipo;
  END IF;

  INSERT INTO incidencia (viaje_id, tipo, datos)
  VALUES (p_viaje, p_tipo, p_datos)
  RETURNING id_incidencia INTO v_id;

  RETURN v_id;
END;
$$;

-- HU-17: suma de minutos de los retrasos del viaje (0 si no hay)
CREATE OR REPLACE FUNCTION fn_retraso_total(p_viaje integer)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_total integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM viaje WHERE id_viaje = p_viaje) THEN
    RAISE EXCEPTION 'El viaje % no existe', p_viaje;
  END IF;
  SELECT COALESCE(sum(((datos ->> 'minutos')::numeric)::integer), 0)::integer INTO v_total
    FROM incidencia
   WHERE viaje_id = p_viaje AND tipo = 'retraso';
  RETURN v_total;
END;
$$;

-- HU-13: vista de auditoria
CREATE OR REPLACE VIEW v_auditoria AS
SELECT tabla, operacion, fecha, datos_anteriores, datos_nuevos
  FROM auditoria
 ORDER BY id_auditoria;

-- ---------- ENCOMIENDAS ----------

-- HU-19: define o REDEFINE un tipo (inserta una version nueva; las anteriores no se tocan)
CREATE OR REPLACE FUNCTION fn_definir_tipo_encomienda(p_tipo text, p_campos jsonb)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_tipo text := btrim(p_tipo);
  v_ver  integer;
BEGIN
  IF v_tipo IS NULL OR v_tipo = '' THEN
    RAISE EXCEPTION 'El nombre del tipo de encomienda es obligatorio';
  END IF;
  IF NOT fn_campos_validos(p_campos) THEN
    RAISE EXCEPTION 'Campos invalidos: se espera {"campo": "clase"} con clase en texto, numero, numero_positivo o si_no';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('tipo_encomienda:' || v_tipo));

  SELECT COALESCE(max(version), 0) + 1 INTO v_ver
    FROM tipo_encomienda WHERE tipo = v_tipo;

  INSERT INTO tipo_encomienda (tipo, version, campos)
  VALUES (v_tipo, v_ver, p_campos);
END;
$$;

-- HU-20: la validacion de datos la hace el trigger trg_encomienda_validar
CREATE OR REPLACE FUNCTION fn_registrar_encomienda(
  p_viaje     integer,
  p_origen    text,
  p_destino   text,
  p_tipo      text,
  p_atributos jsonb
) RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_ruta integer;
  v_o    integer;
  v_d    integer;
  v_id   integer;
BEGIN
  SELECT ruta_id INTO v_ruta FROM viaje WHERE id_viaje = p_viaje;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El viaje % no existe', p_viaje;
  END IF;

  v_o := fn_pos_parada(v_ruta, p_origen);
  v_d := fn_pos_parada(v_ruta, p_destino);
  IF v_o IS NULL OR v_d IS NULL THEN
    RAISE EXCEPTION 'Origen y destino deben ser paradas de la ruta del viaje';
  END IF;
  IF v_o >= v_d THEN
    RAISE EXCEPTION 'El origen debe estar antes que el destino en la ruta';
  END IF;

  INSERT INTO encomienda (viaje_id, origen_pos, destino_pos, tipo, atributos)
  VALUES (p_viaje, v_o, v_d, btrim(p_tipo), p_atributos)
  RETURNING id_encomienda INTO v_id;

  RETURN v_id;
END;
$$;

-- HU-21: contiene todos los datos buscados (@>), ordenado por id
CREATE OR REPLACE FUNCTION fn_buscar_encomiendas(p_filtro jsonb)
RETURNS SETOF integer
LANGUAGE sql STABLE
AS $$
  SELECT e.id_encomienda
    FROM encomienda e
   WHERE e.atributos @> p_filtro
   ORDER BY e.id_encomienda
$$;

-- ---------- INTEGRACION ----------

-- Manifiesto: lista (arreglo JSON) de pasajeros a bordo = pasajes PAGADOS del viaje,
-- ordenados por asiento y tramo. FORMATO A CONFIRMAR con el docente (anexo).
CREATE OR REPLACE FUNCTION fn_manifiesto(p_viaje integer)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_ruta integer;
  v_res  jsonb;
BEGIN
  SELECT ruta_id INTO v_ruta FROM viaje WHERE id_viaje = p_viaje;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El viaje % no existe', p_viaje;
  END IF;

  SELECT COALESCE(
           jsonb_agg(
             jsonb_build_object(
               'id_pasaje', p.id_pasaje,
               'asiento',   a.numero,
               'ci',        p.pasajero_ci,
               'nombre',    pj.nombre,
               'origen',    po.ciudad_nombre,
               'destino',   pd.ciudad_nombre,
               'precio',    p.precio_vendido)
             ORDER BY a.numero, p.origen_pos, p.id_pasaje),
           '[]'::jsonb)
    INTO v_res
    FROM pasaje p
    JOIN asiento a      ON a.id_asiento = p.asiento_id
    JOIN pasajero pj    ON pj.ci = p.pasajero_ci
    JOIN ruta_parada po ON po.ruta_id = v_ruta AND po.posicion = p.origen_pos
    JOIN ruta_parada pd ON pd.ruta_id = v_ruta AND pd.posicion = p.destino_pos
   WHERE p.viaje_id = p_viaje AND p.estado = 'pagado';

  RETURN v_res;
END;
$$;

-- =====================================================================
-- 5. DATOS INICIALES (HU-19): catalogo base requerido, no son datos de prueba.
-- =====================================================================
INSERT INTO tipo_encomienda (tipo, version, campos) VALUES
  ('documento', 1, '{}'::jsonb),
  ('paquete',   1, '{"peso_kg": "numero_positivo"}'::jsonb),
  ('perecible', 1, '{"peso_kg": "numero_positivo", "temperatura_max_c": "numero"}'::jsonb);
