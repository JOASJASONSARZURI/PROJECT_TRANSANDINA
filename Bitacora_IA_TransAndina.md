# Bitácora de uso de inteligencia artificial

Proyecto: **TransAndina**  
Curso: **Bases de Datos II**  
Integrantes del grupo:

- [Nombre 1]
- [Nombre 2]
- [Nombre 3]

## Instrucciones de uso

Agregar una fila o una sección cada vez que se utilice una herramienta de inteligencia artificial.

En la columna **¿Era correcto?** escribir únicamente una conclusión que pueda demostrarse con el documento, el SQL o una prueba ejecutada.

Si una propuesta fue rechazada o modificada, explicar qué se cambió y por qué.

## 1. Registro de uso de inteligencia artificial

| N. | Fecha | Integrante | Herramienta | Historia o tema | Prompt realizado | Respuesta o propuesta recibida | ¿Era correcto? | Cómo se verificó | Cambios o decisión final |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | DD-MM-AAAA | [Nombre] | [Herramienta] | [HU o tema] | [Resumen fiel del prompt] | [Resumen de la propuesta] | [Sí / Parcialmente / No / Pendiente] | [Documento, consulta, prueba o revisión usada] | [Qué decidió el grupo] |
| 2 | DD-MM-AAAA | [Nombre] | [Herramienta] | [HU o tema] | [Resumen fiel del prompt] | [Resumen de la propuesta] | [Sí / Parcialmente / No / Pendiente] | [Documento, consulta, prueba o revisión usada] | [Qué decidió el grupo] |
| 3 | DD-MM-AAAA | [Nombre] | [Herramienta] | [HU o tema] | [Resumen fiel del prompt] | [Resumen de la propuesta] | [Sí / Parcialmente / No / Pendiente] | [Documento, consulta, prueba o revisión usada] | [Qué decidió el grupo] |
| 4 | DD-MM-AAAA | [Nombre] | [Herramienta] | [HU o tema] | [Resumen fiel del prompt] | [Resumen de la propuesta] | [Sí / Parcialmente / No / Pendiente] | [Documento, consulta, prueba o revisión usada] | [Qué decidió el grupo] |
| 5 | DD-MM-AAAA | [Nombre] | [Herramienta] | [HU o tema] | [Resumen fiel del prompt] | [Resumen de la propuesta] | [Sí / Parcialmente / No / Pendiente] | [Documento, consulta, prueba o revisión usada] | [Qué decidió el grupo] |
| 6 | DD-MM-AAAA | [Nombre] | [Herramienta] | Épica 1: HU-01, HU-02, HU-03 y HU-04 | Solicitar un esquema DBML para el diagrama crow's foot de la configuración del servicio en dbdiagram.io. | Propuso las tablas `ciudad`, `ruta`, `ruta_parada`, `bus`, `asiento`, `viaje` y `tarifa`; restricciones únicas y CHECK; JSONB para amenidades; EXCLUDE para viajes cruzados; relaciones compuestas para tarifas. | Pendiente | Completar con revisión del diagrama, ejecución del modelo y pruebas de las HU-01 a HU-04. | Completar después de comparar el DBML con el modelo SQL definitivo y corregir cualquier diferencia. |

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

Explicar en qué mejoraó la calidad de las respuestas o qué información faltó.

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
