# Administración de proyectos (WF-07)

## 1. Historia de usuario

> Como administrador quiero agregar, editar y desactivar proyectos para mantener
> actualizadas las obras disponibles en el bot.

Alcance de esta iteración:

- Proyectos: crear, editar, desactivar, reactivar y listar.
- Clientes: reutilizar existentes o crear uno nuevo con control de duplicados.
- Medios de pago: **fuera de alcance por ahora**.
- Solo `administrador` y `gerencia`.

## 2. Decisión de diseño

El flujo **no** será una secuencia rígida de preguntas. Funcionará de forma similar
a WF-03:

1. La IA interpreta el lenguaje natural.
2. Los nodos deterministas validan y ejecutan.
3. El administrador confirma o corrige antes de guardar.

`/maestras` activa el **modo administración**. Mientras esté activo, los mensajes
de texto del administrador se envían a WF-07 en vez de WF-03.

Ejemplos:

```text
agrega el proyecto Los Robles para el cliente Constructora Andes
```

```text
cambia el nombre de Peñuelas a Obra Peñuelas Norte
```

```text
desactiva la obra La Rinconada
```

```text
reactiva Los Aromos
```

```text
agrega el alias "el robles" al proyecto Los Robles
```

```text
lista los proyectos
```

```text
salir
```

La corrección también será natural:

```text
no, el cliente es Constructora del Norte
```

La IA actualiza solo los campos mencionados y se vuelve a mostrar el resumen.

## 3. Una sola tabla de estado

Se mantiene **una única tabla** para el borrador de la operación:

```sql
admin_pending (
    usuario_id,
    payload,
    actualizado_en
)
```

No se crea una tabla por proyecto ni se modifica el modelo de gastos.

`payload` guarda el borrador que la IA va completando:

```json
{
  "accion": "crear",
  "proyecto": "Los Robles",
  "proyecto_actual": null,
  "nuevo_nombre": null,
  "cliente": "Constructora Andes",
  "alias": [],
  "paso": "confirmar"
}
```

La tabla existe porque el modelo de IA no tiene memoria: si el administrador
corrige un dato, necesitamos el borrador anterior. Es el mismo principio que ya
usa `registros_entrada` para los gastos.

Las migraciones `004_admin_pending.sql` y `005_admin_modo.sql` ya dejan la
estructura actual. Si más adelante se simplifican las columnas, se ajustará la
misma tabla con una migración nueva; no se agregarán más tablas de estado.

## 4. Flujo

### 4.1 Entrada

- `/maestras` o botón **⚙️ Maestras** (solo admin/gerencia).
- Crea o reutiliza una fila en `admin_pending` con `accion='modo'`.
- Muestra un mensaje corto con ejemplos y el botón **Salir**.

### 4.2 Interpretación con IA

El prompt recibe:

- texto del administrador;
- proyectos activos e inactivos con sus alias;
- clientes existentes;
- borrador pendiente, si existe (para correcciones).

La IA devuelve:

```json
{
  "accion": "crear | editar | desactivar | reactivar | listar | salir | otro",
  "proyecto": "nombre mencionado o null",
  "proyecto_actual": "proyecto que se quiere modificar o null",
  "nuevo_nombre": "nombre nuevo o null",
  "cliente": "cliente mencionado o null",
  "alias": ["alias mencionados"],
  "confianza": {
    "accion": 0.95,
    "proyecto": 0.9,
    "cliente": 0.85
  }
}
```

La IA solo extrae. No escribe en la base.

### 4.3 Validación determinista

Antes de mostrar el resumen:

- resolver el proyecto por nombre exacto, alias o similitud;
- si hay ambigüedad, preguntar cuál corresponde;
- verificar que el proyecto exista para editar/desactivar/reactivar;
- validar que el nombre nuevo no choque con otro proyecto;
- resolver el cliente por nombre normalizado;
- si el cliente se parece a uno existente, mostrar la coincidencia;
- si no existe, proponer crearlo;
- validar el rol `administrador` o `gerencia`.

### 4.4 Resumen y confirmación

El mensaje final muestra la operación completa:

```text
🏗️ Nuevo proyecto

Nombre: Los Robles
Cliente: Constructora Andes
Alias: Los Robles, el robles
Estado: activo

[✅ Confirmar] [✏️ Corregir] [❌ Cancelar]
```

Solo se ejecuta la escritura al confirmar.

### 4.5 Corrección

El botón **Corregir** deja el borrador en modo corrección. El administrador puede
escribir otro mensaje natural:

```text
mejor el cliente es Constructora del Norte
```

La IA recibe el borrador anterior y actualiza solo los campos mencionados.

### 4.6 Salir

```text
salir
```

elimina la fila de `admin_pending` y devuelve al menú normal del bot.

## 5. Acciones

### Crear

- Insertar cliente si no existe (reutilizando si el nombre normalizado coincide).
- Insertar proyecto.
- Insertar alias.
- Estado inicial: `activo = true`.

### Editar

- Cambiar nombre del proyecto y/o alias.
- No borrar el proyecto.
- Validar que el nombre nuevo sea único.

### Desactivar / reactivar

- Cambiar `proyectos.activo`.
- No borrar filas.
- Los gastos históricos siguen asociados al proyecto.

### Listar

- Mostrar proyectos activos e inactivos, con cliente y alias.
- No requiere confirmación.

## 6. Duplicados de clientes

Normalización:

1. minúsculas;
2. sin tildes;
3. sin espacios repetidos;
4. sin espacios al inicio/fin.

Regla:

- Si existe un cliente con el mismo nombre normalizado, se reutiliza.
- Si hay uno parecido, se muestra como sugerencia y se pide confirmación.
- Si no hay coincidencia, se propone crear uno nuevo.
- El resumen final siempre muestra el cliente elegido.

## 7. Roles y seguridad

- Solo `administrador` y `gerencia`.
- `jefe_obra` no ve el botón **Maestras**.
- Si escribe `/maestras`, recibe acceso restringido.
- WF-07 no permite modificar gastos ni usuarios.
- La IA no recibe permisos de escritura.

## 8. Impacto técnico

| Elemento | Cambio |
|---|---|
| WF-01 | Si hay `admin_pending` y el mensaje es texto, enviarlo a WF-07 |
| WF-01 | Callbacks `adm:*` se enrutan a WF-07 |
| WF-05 | Botón **Maestras** solo en el menú admin y comando `/maestras` |
| WF-07 | Reemplazar el flujo de pasos por interpretación con IA |
| Base de datos | Mantener solo `admin_pending`; no tocar tablas de gastos |
| IA | Prompt de administración + Gemini para extraer la intención |

No se modifican las tablas `gastos`, `registros_entrada`, `proyectos` ni
`clientes` en su estructura.

## 9. Pruebas de aceptación

- [ ] `jefe_obra` no ve ni puede usar `/maestras`.
- [ ] `administrador` entra con `/maestras`.
- [ ] Crear proyecto con cliente existente.
- [ ] Crear proyecto con cliente nuevo.
- [ ] Reutilizar cliente con nombre normalizado equivalente.
- [ ] Detectar cliente parecido y pedir confirmación.
- [ ] Crear proyecto con alias.
- [ ] Corregir un dato en lenguaje natural y ver el resumen actualizado.
- [ ] Confirmar y verificar el proyecto en `/proyectos`.
- [ ] Intentar crear un proyecto duplicado y recibir error.
- [ ] Editar nombre de proyecto.
- [ ] Desactivar y reactivar un proyecto.
- [ ] Los gastos históricos siguen visibles después de desactivar.
- [ ] `salir` cierra el modo administración.

## 10. Refactor de WF-07

Para evitar que el flujo creciera sin control, se dividió en tres workflows:

| Workflow | Responsabilidad |
|---|---|
| `[MYRA] 07 · Maestras` | Sesión, menú, callbacks, listado, cancelar y salir |
| `[MYRA] 07A · Interpretar operación` | Prompt LLM, parseo, fuzzy matching, validación y borrador |
| `[MYRA] 07B · Ejecutar operación` | Persistencia determinista y respuesta final |

El estado sigue viviendo en `admin_pending`; los sub-workflows se comunican con
`Execute Workflow` y no comparten memoria.

## 11. Operaciones masivas

Además de un proyecto individual, el administrador puede pedir:

```text
desactiva todos los proyectos del cliente Cliente Demo
reactiva todos los proyectos del cliente Cliente Demo
desactiva todos los proyectos
```

Reglas:

- El cliente se resuelve por nombre exacto normalizado.
- Solo se cambian proyectos que estén en el estado opuesto:
  - desactivar → proyectos activos,
  - reactivar → proyectos inactivos.
- Se muestra un resumen con la cantidad y la lista antes de confirmar.
- Si el cliente no existe o hay ambigüedad, se pregunta el nombre exacto.
- La escritura se ejecuta solo al confirmar.

## 12. Estado

Implementado en local y validado con pruebas de los nodos y del SQL. Pendiente:

1. Probar los casos de aceptación completos con datos reales de Supabase.
2. Validar la publicación de los tres workflows en n8n Cloud.
3. Agregar pruebas automatizadas para 07A y 07B.
