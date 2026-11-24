Te voy a explicar cada entidad desde cero, qué representa, para qué sirve y cómo se relaciona con las demás. Imagina que estamos diseñando la base de datos de una **empresa de transporte de pasajeros que vende viajes en bus entre diferentes ciudades**.

Primero, debes entender algo: una **entidad** es algo sobre lo que necesitamos guardar información en nuestra base de datos. En SQL, normalmente la representamos mediante una tabla.

# **1. ¿Cómo funciona todo el sistema?**

Imagina que una empresa ofrece viajes entre estas ciudades:

- Cochabamba
- Santa Cruz
- Sucre
- La Paz

Tiene varios buses, cada uno con sus asientos, y ofrece viajes en diferentes horarios.

La base de datos necesita guardar:

- Las rutas que ofrece la empresa.
- Las ciudades por las que pasa cada ruta.
- Los buses disponibles.
- Los asientos de cada bus.
- Los viajes programados.
- Los precios de los pasajes.

Ahora vamos entidad por entidad.

# **2. Entidades principales**

## **1. RUTA**

Tabla: RUTA

Una ruta representa un recorrido que realiza un bus entre varias ciudades.

Por ejemplo:

Un recorrido desde Cochabamba hasta Santa Cruz, pasando por Sucre.

Sus campos son:

| Campo     | ¿Qué significa?                 |
| --------- | ------------------------------- |
| `id_ruta` | Identificador único de la ruta. |
| `codigo`  | Código que identifica la ruta.  |

Ejemplo:

| id_ruta | codigo |
| ------- | ------ |
| 1       | R001   |
| 2       | R002   |
| 3       | R003   |

**¿Por qué necesitamos esta tabla?**

Porque una empresa puede tener muchas rutas diferentes y necesitamos identificarlas sin confundirlas.

Por ejemplo, R001 puede ser Cochabamba - Santa Cruz y R002 puede ser La Paz - Sucre.

## **2. CIUDAD**

Tabla: CIUDAD

Esta tabla almacena todas las ciudades que utiliza el sistema.

Ejemplo:

| nombre     |
| ---------- |
| Cochabamba |
| Santa Cruz |
| Sucre      |
| La Paz     |

Aquí aparece algo importante:

**¿Por qué no guardamos las ciudades directamente dentro de RUTA?**

Porque una misma ciudad puede aparecer en muchas rutas.

Por ejemplo:

- La ruta R001 pasa por Cochabamba.
- La ruta R002 también pasa por Cochabamba.
- La ruta R003 también puede pasar por Cochabamba.

Si guardáramos el nombre de Cochabamba en cada ruta, estaríamos repitiendo información.

Por eso creamos una tabla independiente llamada CIUDAD.

## **3. RUTA_PARADA**

Tabla de relación

Esta es una de las tablas más importantes porque conecta RUTA con CIUDAD.

Su función es indicar qué ciudades forman parte de una ruta y en qué orden aparecen.

Por ejemplo:

La ruta R001 tiene este recorrido:

1. Cochabamba.
2. Sucre.
3. Santa Cruz.

La tabla RUTA_PARADA quedaría así:

| ruta_id | ciudad_nombre | posicion |
| ------- | ------------- | -------- |
| 1       | Cochabamba    | 1        |
| 1       | Sucre         | 2        |
| 1       | Santa Cruz    | 3        |

Ahora imaginemos otra ruta:

| ruta_id | ciudad_nombre | posicion |
| ------- | ------------- | -------- |
| 2       | La Paz        | 1        |
| 2       | Cochabamba    | 2        |
| 2       | Sucre         | 3        |

**¿Para qué sirve&#x20;**`posicion`**?**

Para conocer el orden en el que el bus pasa por las ciudades.

No es lo mismo:

Cochabamba → Sucre → Santa Cruz

Que:

Santa Cruz → Sucre → Cochabamba.

El orden importa para el funcionamiento del negocio.

### **¿Qué significan las restricciones?**

Hay tres restricciones importantes:

**A. UNIQUE (ruta_id, ciudad_nombre)**

Evita que una ciudad aparezca dos veces en la misma ruta.

Ejemplo incorrecto:

| ruta_id | ciudad_nombre | posicion |
| ------- | ------------- | -------- |
| 1       | Cochabamba    | 1        |
| 1       | Sucre         | 2        |
| 1       | Cochabamba    | 3        |

**B. UNIQUE (ruta_id, posicion)**

Evita que dos ciudades ocupen la misma posición en una ruta.

Ejemplo incorrecto:

| ruta_id | ciudad_nombre | posicion |
| ------- | ------------- | -------- |
| 1       | Cochabamba    | 1        |
| 1       | Sucre         | 1        |

**C. La ruta debe tener al menos dos paradas.**

Una ruta no tiene sentido si solamente contiene una ciudad. Debe existir como mínimo un origen y un destino.

## **4. BUS**

Tabla: BUS

Esta tabla almacena la información de los buses que tiene la empresa.

| Campo        | ¿Qué significa?                |
| ------------ | ------------------------------ |
| `id_bus`     | Identificador único del bus.   |
| `placa`      | Matrícula del vehículo.        |
| `capacidad`  | Cantidad máxima de pasajeros.  |
| `amenidades` | Servicios adicionales del bus. |

Ejemplo:

| id_bus | placa   | capacidad |
| ------ | ------- | --------- |
| 1      | 1234ABC | 40        |
| 2      | 5678XYZ | 50        |
| 3      | 9876DEF | 30        |

### **¿Qué es JSONB?**

Es un tipo de dato de PostgreSQL que permite almacenar información estructurada en formato JSON.

Por ejemplo, el campo `amenidades` podría almacenar:

```
{
  "wifi": true,
  "aire_acondicionado": true,
  "bano": true,
  "asientos_reclinables": true
}
```

Así podemos guardar las características del bus sin crear una columna diferente para cada amenidad.

### **¿Qué significa capacidad entre 1 y 80?**

Que el sistema no permitirá registrar un bus con capacidad de 0 pasajeros o de 100 pasajeros.

La capacidad debe estar entre 1 y 80.

## **5. ASIENTO**

Tabla relacionada con BUS

Esta tabla almacena los asientos que tiene cada bus.

Por ejemplo, imaginemos que tenemos un bus con capacidad para 40 pasajeros.

El sistema debe registrar:

| bus_id | numero |
| ------ | ------ |
| 1      | 1      |
| 1      | 2      |
| 1      | 3      |
| 1      | 4      |
| ...    | ...    |
| 1      | 40     |

**¿Por qué no guardamos solamente la capacidad del bus?**

Porque necesitamos identificar cada asiento individualmente.

Por ejemplo, cuando un pasajero compra un pasaje, el sistema debe saber si está ocupando el asiento 15 o el asiento 20.

### **¿Qué significa UNIQUE (bus_id, numero)?**

Evita que un mismo bus tenga dos asientos con el mismo número.

Por ejemplo, no podemos tener dos asientos número 15 en el bus 1.

### **¿Qué significa crear los asientos mediante&#x20;**`fn_crear_bus`**?**

Significa que podemos crear una función en PostgreSQL que haga automáticamente dos cosas:

1. Registre el bus.
2. Genere todos sus asientos según su capacidad.

Por ejemplo, si registramos un bus con capacidad de 40, la función crea automáticamente los asientos del 1 al 40.

## **6. VIAJE**

Tabla: VIAJE

Aquí debemos diferenciar algo muy importante:

- **RUTA:** es el recorrido que ofrece la empresa.
- **VIAJE:** es una ejecución de esa ruta en una fecha y horario determinados.

Por ejemplo:

La ruta R001 es Cochabamba → Sucre → Santa Cruz.

Pero la empresa puede realizar ese recorrido todos los días.

Entonces podemos tener:

| id_viaje | ruta_id | bus_id | salida      | llegada     |
| -------- | ------- | ------ | ----------- | ----------- |
| 1        | 1       | 1      | 20/11 08:00 | 20/11 18:00 |
| 2        | 1       | 2      | 20/11 20:00 | 21/11 06:00 |
| 3        | 1       | 3      | 21/11 08:00 | 21/11 18:00 |

Los campos son:

| Campo      | Significado                |
| ---------- | -------------------------- |
| `id_viaje` | Identificador del viaje.   |
| `ruta_id`  | Ruta que realizará el bus. |
| `bus_id`   | Bus asignado al viaje.     |
| `salida`   | Fecha y hora de salida.    |
| `llegada`  | Fecha y hora de llegada.   |

### **¿Qué significa&#x20;**`timestamptz`**?**

Es un tipo de dato de PostgreSQL que almacena una fecha y hora teniendo en cuenta la zona horaria.

### **¿Qué significan las restricciones?**

**A. llegada > salida**

El viaje no puede terminar antes de comenzar.

Ejemplo incorrecto:

- Salida: 20/11 a las 20:00.
- Llegada: 20/11 a las 10:00.

**B. Un bus no puede tener viajes con horarios cruzados.**

Imagina que el bus 1 tiene asignado:

- Viaje A: 08:00 a 18:00.
- Viaje B: 15:00 a 22:00.

Esto es incorrecto porque el bus estaría realizando dos viajes al mismo tiempo.

El sistema debe impedir esa situación.

## **7. TARIFA**

Tabla: TARIFA

Esta tabla almacena los precios de los pasajes según el origen y el destino dentro de una ruta.

Por ejemplo, tenemos esta ruta:

Cochabamba → Sucre → Santa Cruz.

La empresa puede establecer diferentes precios:

| Origen     | Destino    | Precio |
| ---------- | ---------- | ------ |
| Cochabamba | Sucre      | 50 Bs  |
| Sucre      | Santa Cruz | 70 Bs  |
| Cochabamba | Santa Cruz | 100 Bs |

Los campos son:

| Campo         | Significado                                |
| ------------- | ------------------------------------------ |
| `id_tarifa`   | Identificador de la tarifa.                |
| `ruta_id`     | Ruta a la que pertenece el precio.         |
| `origen_pos`  | Posición de la ciudad de origen.           |
| `destino_pos` | Posición de la ciudad de destino.          |
| `precio`      | Costo del pasaje.                          |
| `creada_en`   | Fecha y hora en que se registró el precio. |

### **¿Por qué utilizamos posiciones?**

Porque anteriormente creamos RUTA_PARADA.

Recordemos:

| Ciudad     | Posición |
| ---------- | -------- |
| Cochabamba | 1        |
| Sucre      | 2        |
| Santa Cruz | 3        |

Entonces:

- Cochabamba → Sucre: origen_pos = 1, destino_pos = 2.
- Sucre → Santa Cruz: origen_pos = 2, destino_pos = 3.
- Cochabamba → Santa Cruz: origen_pos = 1, destino_pos = 3.

### **¿Qué significa&#x20;**`origen_pos < destino_pos`**?**

Significa que el destino debe estar después del origen en el recorrido.

Por ejemplo:

- Origen 1, destino 3: correcto.
- Origen 3, destino 1: incorrecto.

### **¿Qué significa que TARIFA sea append-only?**

Esta es una característica muy importante.

Significa que **no se deben modificar ni eliminar las tarifas anteriores**.

Imagina que inicialmente el pasaje de Cochabamba a Santa Cruz cuesta 100 Bs.

| id_tarifa | origen_pos | destino_pos | precio |
| --------- | ---------- | ----------- | ------ |
| 1         | 1          | 3           | 100    |

Después, la empresa decide aumentar el precio a 120 Bs.

En lugar de modificar los 100 Bs, se agrega un nuevo registro:

| id_tarifa | origen_pos | destino_pos | precio |
| --------- | ---------- | ----------- | ------ |
| 1         | 1          | 3           | 100    |
| 2         | 1          | 3           | 120    |

Así conservamos el historial de precios.

**¿Cuál es la tarifa vigente?**

La última registrada para ese mismo origen y destino.

En este caso, 120 Bs.

Esto permite saber cuánto costaba un pasaje anteriormente y cuándo cambió su precio.

# **3. ¿Cómo se relacionan todas las tablas?**

Esta es la parte más importante para comprender el diseño de la base de datos.

## **Relaciones del sistema**

**RUTA**

Identifica cada recorrido

1 a muchos

**RUTA_PARADA**

Relaciona rutas con ciudades y establece el orden

Muchos a 1

**CIUDAD**

Almacena las ciudades

**RUTA**

**TARIFA**

Precios por tramo

**RUTA**

**VIAJE**

Programación del recorrido

**BUS**

**ASIENTO**

Asientos de cada bus

**BUS**

**VIAJE**

Bus asignado al viaje

# **4. Resumen para que lo entiendas y puedas explicarlo**

| Entidad     | Función principal                                |
| ----------- | ------------------------------------------------ |
| RUTA        | Define el recorrido.                             |
| CIUDAD      | Guarda las ciudades disponibles.                 |
| RUTA_PARADA | Indica las ciudades de cada ruta y su orden.     |
| BUS         | Guarda los vehículos de la empresa.              |
| ASIENTO     | Registra los asientos de cada bus.               |
| VIAJE       | Programa una ruta en una fecha y horario.        |
| TARIFA      | Guarda los precios de cada tramo y su historial. |

# **5. Comprueba si entendiste**

Te dejo tres preguntas para comprobar que comprendiste cómo funciona el diseño.

**1. ¿Para qué sirve la tabla RUTA_PARADA?**

Guardar los buses disponibles

Relacionar ciudades con rutas y establecer su orden

Guardar los precios de los pasajes

**2. ¿Cuál es la diferencia entre RUTA y VIAJE?**

Son exactamente lo mismo

RUTA guarda los pasajeros y VIAJE los buses

RUTA define el recorrido y VIAJE programa cuándo se realiza

**3. Si una tarifa cambia de 100 Bs a 120 Bs, ¿qué sucede?**

Se modifica el precio anterior

Se agrega una nueva tarifa y se conserva la anterior

Se elimina toda la tabla

Comprobar respuestas

**Mi recomendación:** antes de pasar a crear el código SQL, asegúrate de comprender especialmente RUTA_PARADA, VIAJE y TARIFA. Son las tres entidades cuya lógica de negocio es más importante en este diseño.