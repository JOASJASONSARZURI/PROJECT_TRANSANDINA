# Proyecto Final BD2 — TransAndina

## Consigna

Cada grupo de 3 integrantes diseña y construye en 4 semanas la base de datos de TransAndina, una empresa de buses interdepartamentales. Parten de un backlog, no de un enunciado técnico: ustedes deciden el modelo.

**Uso de inteligencia artificial.** Pueden usar toda la IA que quieran, en cualquier etapa. A cambio:

-   Cada integrante responde por cada tabla, restricción y función del script. En la defensa no se usa IA.
-   La bitácora de IA es obligatoria y se califica (ver plantilla al final).
-   "Lo hizo la IA" no es una justificación válida para ningún diseño.

**Cómo se califica la parte técnica.** Su script se probará automáticamente con pruebas que ustedes no conocen, derivadas de los criterios de aceptación del backlog. Las pruebas usan solo las funciones del contrato técnico. Si una firma no coincide exactamente, esa prueba falla.

**Entregables (una sola carpeta comprimida, grupoN.zip):**

1.  grupoN.sql: script único que se ejecuta de principio a fin en una base vacía de PostgreSQL 16, sin errores. Sin comandos de psql (nada que empiece con \\).
2.  grupoN\_diagrama.pdf: diagrama entidad-relación en notación crow's foot, con una tabla de trazabilidad: qué historia de usuario cubre cada tabla y cada restricción. Para los datos cuya forma cambia según el tipo, incluye por qué eligieron columnas, tablas o JSONB.
3.  grupoN\_pruebas.sql: sus propias pruebas, al menos dos casos por historia de usuario (uno que debe funcionar y uno que debe fallar), comentados.
4.  grupoN\_rendimiento.pdf: resultados del generador de volumen, planes de ejecución (EXPLAIN ANALYZE) de sus dos consultas más costosas y de fn\_buscar\_encomiendas, con y sin su índice, y justificación de cada índice.
5.  grupoN\_bitacora.pdf: bitácora de IA.

La defensa oral dura 15 minutos por grupo. El docente cambiará un requisito en vivo y el grupo explicará qué cambia en el modelo y por qué.

## El negocio

TransAndina vende pasajes en rutas con varias paradas, y un mismo asiento se puede vender por partes. Por ejemplo, la ruta Cochabamba – Caracollo – Patacamaya – La Paz permite que un pasajero viaje de Cochabamba a Caracollo y que otro use ese mismo asiento de Caracollo a La Paz.

Hoy todo se anota en cuadernos en cada terminal. Los problemas más frecuentes son asientos vendidos dos veces, reservas telefónicas que nunca se pagan y bloquean asientos, y reclamos porque nadie sabe a qué precio se vendió un pasaje después de un cambio de tarifa.

Lo que la gerencia sabe del negocio:

-   Cada ruta tiene un código y una lista ordenada de paradas. Una misma ciudad puede aparecer en varias rutas.
-   Cada bus tiene placa, una cantidad fija de asientos numerados desde 1 y comodidades que varían entre buses (wifi, baño, enchufes, aire acondicionado, entre otras).
-   Un viaje es una ruta recorrida por un bus con hora de salida y de llegada estimada.
-   El precio depende del par origen-destino, no de la suma de tramos: Cochabamba – La Paz no cuesta lo mismo que la suma de sus partes.
-   Las tarifas cambian con frecuencia, por temporada o por el precio del combustible.
-   Un pasaje se puede vender pagado al momento o reservar por un tiempo limitado.
-   Los pasajes se pueden anular antes de la salida. La gerencia exige que nunca se borre un registro de venta.

Además de pasajeros, los buses llevan encomiendas, y la empresa quiere atraer clientes con promociones:

-   Hoy se reciben documentos, paquetes y perecibles. Cada tipo pide datos distintos: un paquete, su peso; un perecible, su peso y la temperatura máxima que soporta; un documento, solo el destinatario. La empresa agrega tipos nuevos varias veces al año, como mascotas o electrodomésticos, y no quiere esperar a un programador cada vez.
-   En las terminales buscan encomiendas por cualquier dato que dé el cliente, sobre todo el teléfono del destinatario.
-   Marketing lanza promociones con condiciones combinables: una ruta, un rango de fechas de viaje, ciertos días de la semana o una compra anticipada. Quiere saber cuánto descuento otorgó cada una.
-   En cada viaje ocurren retrasos, averías y controles en carretera que hoy nadie registra, y la gerencia quiere medir la puntualidad.
-   La aplicación de control en carretera necesita la lista de pasajeros a bordo de cada viaje (ver el anexo de integración).

## Product backlog

El backlog tiene 5 épicas, 21 historias de usuario y un anexo de integración. Cada criterio de aceptación es verificable: si su base no lo cumple, una prueba lo detectará.

**Definición clave.** Un tramo es el recorrido entre una parada de subida y una de bajada. Dos tramos se solapan si comparten al menos un segmento entre paradas consecutivas. Bajar en Caracollo y que otro pasajero suba en Caracollo no es solapamiento.

### Épica 1: Configuración del servicio

**HU-01 Registrar rutas.** Como jefe de operaciones quiero registrar rutas con sus paradas en orden para poder vender pasajes por tramo.

-   Una ruta tiene un código único y al menos dos paradas.
-   El orden de las paradas se conserva tal como se registró.
-   Una ciudad no se repite dentro de la misma ruta, pero sí puede estar en varias rutas.

**HU-02 Registrar buses.** Como jefe de operaciones quiero registrar cada bus con su configuración de asientos y sus comodidades para mostrarlas al cliente.

-   La placa es única y la capacidad está entre 1 y 80 asientos.
-   Los asientos se numeran desde 1 hasta la capacidad.
-   Las comodidades varían entre buses, y la empresa incorpora comodidades nuevas que hoy no conoce sin esperar cambios en el sistema.
-   Los clientes filtran buses por una o varias comodidades, incluido el detalle de cada una, por ejemplo televisor con pantalla en cada asiento. Los resultados se ordenan por identificador.

**HU-03 Programar viajes.** Como jefe de operaciones quiero asignar un bus a una ruta con fecha y hora para abrir la venta.

-   La llegada estimada es posterior a la salida.
-   Un bus no puede estar asignado a dos viajes cuyos horarios se crucen.
-   Dos viajes del mismo bus que no se cruzan se aceptan.

**HU-04 Fijar tarifas.** Como gerente quiero fijar el precio de cada par origen-destino de una ruta para cobrar lo que corresponde.

-   El origen va antes que el destino en la ruta y el precio es mayor que cero.
-   Fijar una tarifa nueva no borra la anterior: se conserva el histórico.
-   El precio vigente de un par es el último que se fijó.
-   Si un par no tiene tarifa, no se puede vender ni reservar ese tramo.
-   Un pasaje conserva el precio con el que se vendió, aunque la tarifa cambie después.

### Épica 2: Venta

**HU-05 Vender pasaje.** Como cajero quiero vender un asiento para un tramo del viaje para cobrar al pasajero.

-   El asiento debe existir en el bus asignado al viaje.
-   Origen y destino deben ser paradas de la ruta, y el origen debe estar antes que el destino.
-   No se vende un asiento en un tramo que se solape con otro pasaje o reserva vigente del mismo asiento.
-   Sí se vende el mismo asiento en tramos que no se solapan.
-   No se vende en un viaje cuya hora de salida ya pasó.
-   La venta devuelve el identificador del pasaje.

**HU-06 Consultar disponibilidad.** Como cajero quiero ver qué asientos están libres para un tramo para ofrecerlos al cliente.

-   La consulta depende del tramo: un asiento ocupado de Cochabamba a Caracollo está libre de Caracollo a La Paz.
-   Las reservas vencidas no ocupan asiento.
-   Los asientos se devuelven ordenados por número.

**HU-07 Registrar pasajeros.** Como cajero quiero identificar al pasajero por su CI para no registrarlo dos veces.

-   Un pasajero se identifica por su CI. Si el CI ya existe, se actualiza el nombre.
-   Un pasajero no puede ocupar dos asientos en tramos que se solapan del mismo viaje.
-   Sí puede tener pasajes en tramos consecutivos del mismo viaje.

**HU-08 Reservar asiento.** Como cajero quiero reservar un asiento por un tiempo limitado para que el cliente pague después.

-   La reserva tiene una vigencia mayor que cero, definida al reservar.
-   Mientras está vigente, bloquea el asiento igual que una venta.
-   Cuando vence, el asiento queda libre sin que nadie intervenga.
-   El precio de la reserva es el vigente al momento de reservar.

**HU-09 Pagar reserva.** Como cajero quiero cobrar una reserva para convertirla en pasaje.

-   Solo se paga una reserva vigente. Una reserva vencida se rechaza.
-   Se cobra el precio del momento de la reserva, aunque la tarifa haya cambiado.
-   Una reserva no se paga dos veces.

**HU-10 Anular pasaje.** Como supervisor quiero anular un pasaje o una reserva para liberar el asiento.

-   Solo se anula antes de la salida del viaje.
-   El asiento queda libre para venderse de nuevo.
-   El registro no se borra: queda con estado anulado.
-   Un pasaje ya anulado no se anula otra vez.

**HU-16 Aplicar promociones.** Como responsable de marketing quiero crear promociones con condiciones para atraer pasajeros en fechas y rutas de baja demanda.

-   Una promoción tiene un nombre y un porcentaje de descuento mayor que 0 y menor que 100.
-   Puede tener cualquier combinación de estas condiciones, y la que no tenga no limita: ruta (por su código, que debe existir), fecha de viaje desde y hasta, días de la semana del viaje (1 = lunes, 7 = domingo) y anticipación mínima de compra en días enteros.
-   Cualquier otra condición, una ruta inexistente o un rango de fechas invertido se rechazan.
-   Fechas y días se cuentan según la hora de salida en Bolivia.
-   Al vender o reservar se aplica sola la promoción con mayor descuento que cumpla todas sus condiciones; si hay empate, la más antigua. Solo se aplica una.
-   El precio con descuento se redondea a centavos y queda congelado, aunque después se creen otras promociones.
-   Cada pasaje registra qué promoción se le aplicó, si hubo alguna.

### Épica 3: Reportes y control

**HU-11 Ocupación por segmento.** Como jefe de operaciones quiero ver cuántos asientos van ocupados entre cada par de paradas consecutivas para saber dónde sobra capacidad.

-   Una fila por segmento, en el orden de la ruta.
-   Cuenta pasajes pagados y reservas vigentes. No cuenta anulados ni vencidos.

**HU-12 Ingresos por viaje.** Como gerente quiero saber cuánto recaudó un viaje para controlar caja.

-   Suma solo pasajes pagados, al precio con que se vendieron.
-   Las reservas sin pagar y los pasajes anulados no suman.
-   Un viaje sin ventas devuelve 0.

**HU-13 Auditoría.** Como auditor quiero un registro de cada cambio en pasajes y tarifas para investigar reclamos.

-   Cada inserción, modificación o eliminación queda registrada con tabla, operación y fecha.
-   Se guardan los datos anteriores y nuevos de la fila completa.
-   El registro se genera en la base, sin depender de que la aplicación lo haga.

**HU-17 Registrar incidencias.** Como jefe de operaciones quiero registrar lo que ocurre en cada viaje para medir la puntualidad.

-   Un retraso registra los minutos (entero mayor que cero) y el motivo.
-   Una avería registra la descripción y si obliga a cambiar de bus (sí o no).
-   Un control en carretera registra el lugar y el resultado, que solo puede ser "sin novedad" u "observado".
-   Cualquier otro tipo de incidencia, o un dato faltante o mal escrito, se rechaza; por ejemplo, minutos escritos como texto.
-   El retraso total de un viaje es la suma de los minutos de sus retrasos. Sin retrasos, el total es 0.

**HU-18 Descuento otorgado.** Como gerente quiero saber cuánto dinero dejó de cobrarse por cada promoción para decidir si conviene mantenerla.

-   Es la suma de la diferencia entre el precio sin descuento y el precio cobrado, solo de pasajes pagados.
-   Las reservas sin pagar y los pasajes anulados no cuentan. Una promoción sin uso devuelve 0.

### Épica 4: Operación confiable

**HU-14 Venta simultánea.** Como gerente quiero que dos cajeros vendiendo a la vez nunca vendan el mismo asiento en tramos solapados.

-   Si dos ventas en conflicto ocurren al mismo tiempo, exactamente una tiene éxito.
-   Debe cumplirse aunque las dos transacciones estén abiertas al mismo tiempo.

**HU-15 Rendimiento.** Como gerente quiero que el sistema siga rápido con un año de ventas.

-   El generador de volumen termina en menos de 10 minutos.
-   Disponibilidad, ocupación, ingresos y manifiesto responden en menos de 5 ms promedio, y la búsqueda de encomiendas en menos de 2 ms, con unos 90 000 pasajes y 40 000 encomiendas.

### Épica 5: Encomiendas

**HU-19 Definir tipos de encomienda.** Como encargado de carga quiero definir tipos nuevos de encomienda y los datos que exige cada uno para empezar a recibirlos el mismo día, sin esperar cambios en el sistema.

-   Al comenzar existen tres tipos: documento (sin datos adicionales), paquete (peso en kg, número mayor que cero) y perecible (peso en kg mayor que cero y temperatura máxima en °C).
-   Cada dato obligatorio tiene una clase: texto, número, número positivo o sí/no. Una clase desconocida se rechaza.
-   Un tipo se puede redefinir. Lo nuevo se exige a las encomiendas registradas desde ese momento; las anteriores no se modifican ni se invalidan.

**HU-20 Registrar encomiendas.** Como encargado de carga quiero registrar encomiendas en un viaje con los datos que exige su tipo para no perder información del envío.

-   Toda encomienda registra el nombre del destinatario (texto no vacío) y puede registrar su teléfono.
-   Se exigen los datos obligatorios del tipo, con su clase correcta. Un peso escrito como texto, por ejemplo "12", se rechaza.
-   Se aceptan y conservan datos adicionales no obligatorios, como fragilidad o dimensiones.
-   Un tipo no definido se rechaza.
-   Origen y destino son paradas de la ruta, y el origen va antes que el destino.
-   La validación la hace la base de datos, no la aplicación.

**HU-21 Buscar encomiendas.** Como encargado de terminal quiero buscar encomiendas con cualquier combinación de datos para atender reclamos.

-   Se busca por uno o varios datos a la vez, incluidos los del destinatario, como su teléfono. Una encomienda coincide si tiene todos los datos buscados, aunque tenga otros.
-   Los resultados se ordenan por identificador. Sin coincidencias, el resultado es vacío.

## Contrato técnico

El modelo es de ustedes, pero estas 21 funciones y 1 vista deben existir con exactamente estos nombres, parámetros y tipos de retorno. Pueden crear todas las tablas, funciones auxiliares, triggers e índices que quieran.

Reglas generales:

-   Toda violación de una regla de negocio se rechaza con RAISE EXCEPTION. El mensaje es libre.
-   Las ciudades se reciben por su nombre exacto, por ejemplo 'La Paz'.
-   Los identificadores devueltos son enteros.

Varias funciones reciben o devuelven objetos JSON porque así se comunican las aplicaciones de la empresa. Eso fija el formato de intercambio, no el almacenamiento: ustedes deciden si cada dato se guarda en columnas, en tablas o en JSONB, y lo justifican en el diagrama.

\-- Configuración  
fn\_crear\_ruta(p\_codigo text, p\_paradas text\[\]) RETURNS int  
fn\_crear\_bus(p\_placa text, p\_capacidad int, p\_amenidades jsonb DEFAULT '{}') RETURNS int  
fn\_buses\_con\_amenidades(p\_filtro jsonb) RETURNS SETOF int  
fn\_programar\_viaje(p\_ruta int, p\_bus int, p\_salida timestamptz, p\_llegada timestamptz) RETURNS int  
fn\_fijar\_tarifa(p\_ruta int, p\_origen text, p\_destino text, p\_precio numeric) RETURNS int  
  
\-- Venta y promociones  
fn\_vender\_pasaje(p\_viaje int, p\_asiento int, p\_origen text, p\_destino text,  
p\_ci text, p\_nombre text) RETURNS int  
fn\_reservar(p\_viaje int, p\_asiento int, p\_origen text, p\_destino text,  
p\_ci text, p\_nombre text, p\_vigencia interval) RETURNS int  
fn\_pagar\_reserva(p\_reserva int) RETURNS int  
fn\_anular\_pasaje(p\_pasaje int) RETURNS void  
fn\_crear\_promocion(p\_nombre text, p\_porcentaje numeric, p\_condiciones jsonb) RETURNS int  
\-- condiciones posibles: {"ruta": "CBBA-LPZ", "desde": "2026-12-01", "hasta": "2026-12-31",  
\-- "dias\_semana": \[6, 7\], "antelacion\_min\_dias": 7}  
fn\_promocion\_aplicada(p\_pasaje int) RETURNS int -- NULL si no hubo promoción  
  
\-- Reportes y control  
fn\_asientos\_disponibles(p\_viaje int, p\_origen text, p\_destino text) RETURNS SETOF int  
fn\_ocupacion(p\_viaje int) RETURNS TABLE (desde text, hasta text, ocupados int)  
fn\_ingresos\_viaje(p\_viaje int) RETURNS numeric  
fn\_descuento\_otorgado(p\_promocion int) RETURNS numeric  
fn\_registrar\_incidencia(p\_viaje int, p\_tipo text, p\_datos jsonb) RETURNS int  
\-- p\_tipo: 'retraso' {"minutos", "motivo"} | 'averia' {"descripcion", "requiere\_cambio\_bus"}  
\-- | 'control' {"lugar", "resultado"}  
fn\_retraso\_total(p\_viaje int) RETURNS int  
VIEW v\_auditoria (tabla text, operacion text, fecha timestamptz,  
datos\_anteriores jsonb, datos\_nuevos jsonb)  
  
\-- Encomiendas  
fn\_definir\_tipo\_encomienda(p\_tipo text, p\_campos jsonb) RETURNS void  
\-- p\_campos: {"peso\_kg": "numero\_positivo", "especie": "texto", "vacunada": "si\_no"}  
\-- clases: texto | numero | numero\_positivo | si\_no  
fn\_registrar\_encomienda(p\_viaje int, p\_origen text, p\_destino text,  
p\_tipo text, p\_atributos jsonb) RETURNS int  
\-- p\_atributos: {"destinatario": {"nombre": "...", "telefono": "..."}, ...datos del tipo}  
fn\_buscar\_encomiendas(p\_filtro jsonb) RETURNS SETOF int  
  
\-- Integración (anexo)  
fn\_manifiesto(p\_viaje int) RETURNS jsonb

## Volumen y rendimiento

El docente entrega el archivo generar\_volumen.sql. Crea unos 90 000 pasajes, 40 000 encomiendas y 3 000 incidencias en 2 000 viajes usando solo las funciones del contrato, y al final mide el tiempo promedio de cinco consultas.

Cómo usarlo:

1.  Creen una base vacía y carguen grupoN.sql.
2.  Ejecuten generar\_volumen.sql sobre esa base y anoten el tiempo total.
3.  Copien los tiempos promedio que aparecen al final como avisos (NOTICE).

Metas, según HU-15:


## Metas de rendimiento

| Medida | Meta |
|---|---|
| Generación completa | Menos de 10 minutos |
| `fn_asientos_disponibles` | Menos de 5 ms promedio |
| `fn_ocupacion` | Menos de 5 ms promedio |
| `fn_ingresos_viaje` | Menos de 5 ms promedio |
| `fn_manifiesto` | Menos de 5 ms promedio |
| `fn_buscar_encomiendas` | Menos de 2 ms promedio |


Si la generación tarda mucho más, su base está revisando toda la tabla de pasajes en cada venta. Eso se resuelve con índices, no con un equipo más rápido. En el informe expliquen qué índice agregaron y muestren el EXPLAIN ANALYZE antes y después.

## Rúbrica

La nota total es 100 puntos: 80 son grupales y 20 son de la defensa, que es individual.


## Criterios de evaluación

| Criterio | Puntos | Logrado | Insuficiente |
|---|---:|---|---|
| Pruebas automáticas | 35 | Se asigna en proporción al puntaje de las pruebas ocultas (0 a 100). | El script no carga en una base vacía: 0 puntos en este criterio. |
| Diagrama y trazabilidad | 15 | Modelo normalizado; cada historia está cubierta por tablas o restricciones identificadas; cada decisión entre columnas, tablas y JSONB está justificada. | Tablas sin relación con el backlog, datos repetidos o decisiones de almacenamiento sin justificar. |
| Pruebas propias | 10 | Al menos dos casos por historia, incluidos casos que deben fallar, con resultado esperado comentado. | Solo casos donde todo funciona. |
| Rendimiento | 10 | Cumple las metas de HU-15 y justifica cada índice con planes de ejecución antes y después. | Sin índices justificados o sin mediciones. |
| Bitácora de IA | 10 | Registra prompts clave, errores de la IA detectados por el grupo y cómo los corrigieron. | Lista de prompts sin análisis, o afirma que la IA no se equivocó nunca. |
| Defensa oral (individual) | 20 | Explica su parte y adapta el modelo ante el cambio de requisito propuesto en vivo. | No puede explicar tablas o funciones de su propio script. |
| **Total** | **100** | | |

Regla adicional: si un integrante no puede explicar ninguna parte del script, su nota grupal se reduce a la mitad.

## Bitácora de IA

Registren cada interacción importante con la IA, no todas. Una entrada útil muestra qué propuso la IA, qué estaba mal y cómo lo descubrieron. Se esperan entre 8 y 15 entradas.


## Bitácora de uso de inteligencia artificial

| N.º | Fecha | Herramienta | Historia | Qué le pediste (prompt) | Qué propuso la IA | ¿Era correcto? | Cómo verificaste | Qué cambiaste |
|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | |
| 2 | | | | | | | | |
| 3 | | | | | | | | |


Al final, respondan en un párrafo cada una:

1.  ¿Qué error de la IA les costó más detectar y por qué?
2.  ¿Qué parte del modelo decidieron ustedes en contra de lo que propuso la IA?
3.  ¿Qué contexto le dieron a la IA (backlog, diagrama, código) y cómo cambió la calidad de sus respuestas?

## Cronograma

Cada semana termina con un punto de control breve en clase. El punto de control no lleva nota, pero sin él no hay retroalimentación del docente.


## Cronograma de trabajo

| Semana | Trabajo del grupo | Punto de control |
|---|---|---|
| 1 | Leer el backlog, diseñar el diagrama y la tabla de trazabilidad. | Diagrama revisado en clase. |
| 2 | Script con tablas, restricciones y funciones de las épicas 1 y 2. | Demostración de venta por tramos. |
| 3 | Reportes, auditoría, promociones, incidencias, encomiendas, concurrencia y pruebas propias. | Revisión con el agente revisor. |
| 4 | Volumen, índices, informe de rendimiento y bitácora. | Entrega y defensa oral. |
