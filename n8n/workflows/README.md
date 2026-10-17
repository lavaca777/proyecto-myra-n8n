# Workflows exportados

Esta carpeta contiene los workflows de n8n exportados a JSON. **Sí se versiona en
git**; es la fuente de verdad para recuperar los flujos si se pierde `n8n/data/`.

## Exportar

```powershell
.\scripts\export-workflows.ps1
```

El script:

1. Exporta a `/tmp/wf-export` dentro del contenedor.
2. Solo si el export fue exitoso, reemplaza los `*.json` de esta carpeta.
3. No toca los archivos que no sean `.json`.

## Importar en una instancia nueva

En n8n: **Workflows → Import from File** y seleccionar cada JSON. También se puede
usar la CLI:

```powershell
docker compose cp .\n8n\workflows\. n8n:/tmp/workflows
docker compose exec -T n8n n8n import:workflow --separate --input=/tmp/workflows
```

> Las credenciales **no** se exportan acá. Hay que recrearlas o restaurarlas desde
> `db/backups/credentials_*.json` con la misma `N8N_ENCRYPTION_KEY`.

## Convención

Los archivos se generan con el nombre del workflow en kebab-case. Si renombras un
workflow en n8n, vuelve a exportar y elimina el archivo viejo.
