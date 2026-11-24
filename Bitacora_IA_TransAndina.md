# Bitácora de uso de inteligencia artificial

Proyecto: **TransAndina**  
Curso: **Bases de Datos II**  
Integrantes del grupo:

- Sarzuri Mamani Joas Jason

## Instrucciones de uso

Agregar una fila o una sección cada vez que se utilice una herramienta de inteligencia artificial.

En la columna **¿Era correcto?** escribir únicamente una conclusión que pueda demostrarse con el documento, el SQL o una prueba ejecutada.

Si una propuesta fue rechazada o modificada, explicar qué se cambió y por qué.

## 1. Registro de uso de inteligencia artificial

| N. | Fecha | Integrante | Herramienta | Historia o tema | Prompt realizado | Respuesta o propuesta recibida | ¿Era correcto? | Cómo se verificó | Cambios o decisión final |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | 20-11-2026 | Sarzuri Mamani Joas Jason | Claude (Sonnet 5.5) | HU-01 a HU-04 | Compartir el diseño de la Épica 1 y pedir el código DBML. | Propuso el modelo de rutas, ciudades, paradas, buses, asientos, viajes y tarifas, con restricciones, JSONB e índices; anotó reglas que DBML no expresa. | Parcial; en una revisión posterior se señalaron dos problemas (entrada 2). | Según la bitácora de Claude, no se documentó una prueba ejecutada; completar con la revisión y pruebas reales del grupo. | Véase la entrada 2; no considerar el diseño probado hasta validarlo. |
| 2 | 23-11-2026 | Sarzuri Mamani Joas Jason | Claude (Sonnet 5.5) | HU-04 | Preguntar si el backlog modificaba la respuesta anterior de DBML. | La IA identificó que usar `creada_en` para determinar la tarifa vigente podía empatar dentro de una transacción y que `numeric(10,2)` redondea valores sin avisar. | Parcial; los problemas se detectaron mediante revisión, no con pruebas documentadas. | La bitácora de Claude propone probar dos llamadas a `fn_fijar_tarifa` dentro de una transacción; esa prueba queda pendiente. | Se registró usar el mayor `id_tarifa` como vigente, `numeric` sin precisión fija y `clock_timestamp()` para `creada_en`. |
| 3 | 23-11-2026 | Sarzuri Mamani Joas Jason | Claude (Sonnet 5.5) | HU-01 a HU-04 | Pedir el código completo listo para copiar y pegar. | Entregó el DBML consolidado de la Épica 1. | Pendiente de validar completamente. | La bitácora de Claude indica que falta confirmar que dbdiagram.io acepta los bloques `checks`. | Completar con el resultado real de importar el modelo. |
| 4 | 23-11-2026 | Sarzuri Mamani Joas Jason | Claude (Sonnet 5.5) | HU-05 a HU-10 y HU-16 | Compartir las entidades PASAJERO, PASAJE y PROMOCION y las historias de la Épica 2. | Propuso una tabla `pasaje` para ventas y reservas, condiciones JSONB para promociones, bloqueo de solapes y un `id_asiento` para una FK simple. | Parcial; la estrategia de bloqueo se revisó después (entrada 6). | La bitácora de Claude deja pendientes las pruebas y la decisión del grupo sobre `id_asiento`. | Se documentó la revisión posterior de concurrencia; el grupo debe decidir si mantiene el identificador de asiento. |
| 5 | 23-11-2026 | Sarzuri Mamani Joas Jason | Claude (Sonnet 5.5) | HU-11, HU-12, HU-13, HU-17 y HU-18 | Compartir las entidades INCIDENCIA y AUDITORIA y las historias de la Épica 3. | Propuso validación de incidencias, auditoría sin FK a las tablas auditadas, triggers y reportes sobre `pasaje`; advirtió una posible tensión entre auditar DELETE y no borrar ventas. | Sin verificar. | La bitácora de Claude propone probar valores y orden de creación; las pruebas quedan pendientes. | Completar después de validar el SQL y decidir cómo resolver el conflicto señalado. |
| 6 | 23-11-2026 | Sarzuri Mamani Joas Jason | Claude (Sonnet 5.5) | HU-07 y HU-14 | Compartir la Épica 4 sobre venta simultánea y rendimiento. | Revisó la propuesta de bloqueo y planteó restricciones `EXCLUDE` con rangos para evitar solapes de asiento y pasajero; propuso estado `vencido` para reservas vencidas. | Pendiente de probar. | La bitácora de Claude propone una prueba con dos sesiones simultáneas; no se registra como ejecutada. | La solución y sus estados deben validarse con la prueba concurrente antes de darlos por correctos. |
| 7 | 23-11-2026 | Sarzuri Mamani Joas Jason | Claude (Sonnet 5.5) | HU-19, HU-20 y HU-21 | Compartir los tipos de encomienda, encomiendas y las historias de la Épica 5. | Propuso tipos versionados, validación de destinatario y tipo, y búsqueda con `@>` e índice GIN; añadió una regla sobre nombres de campos reservados que no estaba en el backlog. | Sin verificar; la regla extra requiere decisión del grupo. | La bitácora de Claude deja pendientes las pruebas con datos inválidos y redefinición de tipos. | Completar pruebas y decidir si se conserva la regla adicional. |
| 8 | 23-11-2026 | Sarzuri Mamani Joas Jason | GitHub Copilot (VS Code) | Revisión del DBML, HU-01 a HU-04 | Preguntar si el DBML tenía incoherencias y pedir corregir los errores pequeños. | Señalé que `tarifa.ruta_id` no declaraba FK directa a `ruta` y que la nota del índice GIN mencionaba `jsonb_path_ops` sin configurarlo explícitamente; propuse añadir la FK y aclarar la nota. | Parcial; la FK directa es clara, pero aclarar una nota no configura la clase de operador del índice. | Revisión visual del DBML; no se ejecutó en dbdiagram.io ni en PostgreSQL. Al actualizar esta bitácora, la versión actual consultada ya no muestra la FK directa ni la nota aclarada; confirmar cuál es el modelo definitivo. | Se hicieron esas ediciones en una versión anterior. Revisar si deben reaplicarse; no afirmar que `jsonb_path_ops` está configurado por la nota. |
| 9 | 23-11-2026 | Sarzuri Mamani Joas Jason | GitHub Copilot (VS Code) | Bitácora de uso de IA, Épicas 1 a 5 | Pedir que se actualice la bitácora con la bitácora de Claude y se agreguen las interacciones de Copilot; también se señaló que faltaba registrar Épica 2. | Se integraron las siete entradas atribuidas a Claude y se añadieron las interacciones de Copilot, conservando explícitamente las verificaciones pendientes. | Sí, como registro documental; no valida técnicamente las propuestas. | Comparación de las entradas con `bitacora_claude.md` y con el historial de esta conversación; conteo de nueve registros. | Se consolidaron las entradas en esta tabla. Completar nombres y actualizar estados solo con evidencia de pruebas reales. |

> Mantener entre 8 y 15 entradas antes de entregar el documento. Agregar o eliminar filas según el trabajo real del grupo.

## 2. Ejemplos para completar las columnas

### Fecha

Registrar la fecha en formato `DD-MM-AAAA`.

### Historia o tema

Usar referencias como `HU-01`, `HU-05 y HU-14`, `Índices`, `Diagrama ER`, `Pruebas SQL` o `Rendimiento`.

### Prompt realizado

No es necesario copiar la conversación completa, pero sí debe quedar claro qué pidió el integrante a la herramienta.

Ejemplo:

> ¿Cómo puedo evitar que dos ventas simultáneas ocupen un asiento en tramos solapados?

### Respuesta o propuesta recibida

Describir brevemente qué sugirió la herramienta.

Ejemplo:

> Propuso usar rangos de segmentos y una restricción EXCLUDE.

### Verificación

Escribir exactamente cómo se comprobó:

- Revisión del criterio de aceptación.
- Consulta ejecutada en PostgreSQL.
- Prueba propia exitosa.
- Prueba propia fallida.
- EXPLAIN ANALYZE.
- Comparación con el contrato técnico.
- Revisión del diagrama o del script por el grupo.

### Cambio realizado

Registrar si se aceptó, rechazó o modificó la propuesta.

## 3. Reflexión sobre el error más difícil de detectar

[Completar con un error real encontrado durante el proyecto.]

Puede responder:

- ¿Qué sugirió inicialmente la inteligencia artificial?
- ¿Por qué parecía correcta?
- ¿Qué requisito no se estaba considerando?
- ¿Cómo se descubrió el problema?
- ¿Qué cambio realizó el grupo?
- ¿Qué prueba demuestra que quedó corregido?

## 4. Decisiones tomadas en contra de propuestas de la IA

[Completar con decisiones reales del grupo.]

Registrar al menos una situación en la que no se aceptó una propuesta. Puede incluir:

- Una alternativa de modelado rechazada.
- Una validación que inicialmente se hizo en la aplicación.
- Un tipo de dato que no era adecuado.
- Un índice innecesario.
- Una función que no cumplía la firma exacta.
- Una consulta más costosa que una alternativa normalizada.

Incluir el motivo técnico y el enfoque final adoptado.

## 5. Contexto proporcionado a la inteligencia artificial

[Completar con el contexto real que recibió la herramienta.]

Indicar:

- Qué documentos o fragmentos del proyecto se proporcionaron.
- Qué requisitos se comunicaron.
- Qué restricción técnica se indicó.
- Qué limitaciones se incluyeron.
- Qué formatos o firmas debían respetarse.

Explicar en qué mejoró la calidad de las respuestas o qué información faltó.

## 6. Evidencia técnica del trabajo

- [ ] Casos de prueba exitosos.
- [ ] Casos de prueba con resultados de error.
- [ ] Archivo SQL de pruebas.
- [ ] Diagrama revisado.
- [ ] Trazabilidad completada.
- [ ] EXPLAIN ANALYZE con índices.
- [ ] EXPLAIN ANALYZE sin índices.
- [ ] Tiempos del generador de volumen.
- [ ] Capturas o resultados exportados.
- [ ] Formato de `fn_manifiesto` confirmado, si corresponde.

## 7. Preparación para la defensa

Cada integrante debe poder explicar:

- [ ] Cada tabla que diseñó.
- [ ] Las llaves primarias y foráneas.
- [ ] Las restricciones que implementó.
- [ ] Los campos JSONB y su justificación.
- [ ] Las funciones que escribió.
- [ ] Los índices que agregó.
- [ ] Las pruebas que ejecutó.
- [ ] Los errores detectados con ayuda de la IA.
- [ ] Qué decisiones tomó el grupo y por qué.
