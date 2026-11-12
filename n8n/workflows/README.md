# Workflows exportados

Esta carpeta contiene los workflows de n8n exportados a JSON. **Sí se versiona en
git**; es la fuente de verdad para recuperar los flujos si se pierde `n8n/data/`.

## Exportar

En desarrollo local:

```powershell
.\scripts\export-workflows.ps1
```

El script detiene n8n, exporta con un contenedor temporal y vuelve a levantar n8n.
Esto evita el bloqueo de SQLite en Windows.

En n8n Cloud, exportar desde la UI del workflow. El script es solo para la instancia
local.

## Importar en n8n Cloud (producción)

En n8n Cloud: **Workflows → Import from File** y seleccionar cada JSON. Después:

1. Recrear las credenciales (Telegram, Gemini, Groq y Postgres/Supabase).
2. Asignar las credenciales nuevas a cada nodo.
3. Publicar también los sub-workflows: WF-00, WF-02, WF-03, WF-04, WF-05, WF-06,
   WF-07, WF-07A y WF-07B.
4. Activar WF-01 y verificar el webhook de Telegram.

Los IDs de workflows y credenciales del entorno local no se reutilizan en Cloud.
Los workflows de administración actuales son `myra-07-maestras.json`,
`myra-07a-interpretar.json` y `myra-07b-ejecutar.json`.

## Importar en una instancia local (desarrollo)

En n8n local: **Workflows → Import from File** o usar la CLI:

```powershell
docker compose cp .\n8n\workflows\. n8n:/tmp/workflows
docker compose exec -T n8n n8n import:workflow --separate --input=/tmp/workflows
```

> Las credenciales **no** se exportan aquí. Hay que recrearlas o restaurarlas desde
> `db/backups/credentials_*.json` con la misma `N8N_ENCRYPTION_KEY`.

## Convención

Los archivos se generan con el nombre del workflow en kebab-case. Si renombras un
workflow en n8n, vuelve a exportar y elimina el archivo viejo.
