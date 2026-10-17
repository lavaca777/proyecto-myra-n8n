# Migración desde la carpeta anterior

Fecha: 2026-10-17
Origen: `C:\Users\HP\Downloads\UCN 2026-2\gestion de proyectos de I.A\proyecto`
Destino: `C:\Users\HP\Downloads\GitHub\proyecto-myra-n8n`

La carpeta de origen **no se modificó**. Se copiaron los datos y se dejó como respaldo
histórico.

## Qué se migró

| Elemento | Origen | Destino |
|---|---|---|
| Base SQLite de n8n | `n8n\database.sqlite` + WAL | `n8n\data\database.sqlite` (WAL consolidado) |
| Workflows | 2 borradores | `n8n\workflows\*.json` |
| Credenciales | Telegram, Gemini, Postgres | mismo `n8n\data` (misma encryption key) |
| Esquema PostgreSQL | `Myra_db\schema_postgres.sql` | `db/migrations/001..003` |
| Volumen PostgreSQL | `myra_db_pg_data` | reutilizado por el nuevo compose |
| Charter | `proyect\ charter\` | `docs\charter\` |
| Entrevistas | `grabaciones\*.txt` | `docs\entrevistas\` |
| Modelo relacional | `modelo relacional.png` | `docs\db\modelo-relacional.png` |

## Cambios técnicos

1. **Compose único.** Antes había dos formas de arrancar n8n: `start-all.ps1`
   (docker run + bind mount) y `Myra_db\docker-compose.yml` (volumen nombrado).
   Ahora todo vive en `docker-compose.yml`.
2. **Credencial de Postgres.** Se reescribió de `host.docker.internal:5433` a
   `postgres:5432`, que es el nombre del servicio dentro de la red de Compose.
   La contraseña y el usuario no cambiaron.
3. **Encryption key.** Se conservó la clave original
   (`n8n\data\config` → `LciPfm...`). El `.env` local usa la misma. Sin esa clave,
   las credenciales no se pueden descifrar.
4. **WAL consolidado.** Se copió la base con su WAL y se aplicó
   `PRAGMA wal_checkpoint(TRUNCATE)` para dejar un archivo SQLite limpio.
5. **Esquema versionado.** El `schema_postgres.sql` original se dividió en
   migraciones idempotentes y se agregó `pg_trgm`/`unaccent` para el fuzzy matching.
6. **Secretos.** `.env`, `n8n\data`, `db\backups` y los audios quedaron en
   `.gitignore`.

## Qué no se copió

- Audios de entrevistas (`Voz *.m4a`): pesan ~70 MB y no deben ir a GitHub. Siguen en
  la carpeta original.
- `n8n - copia`, `*.txt` duplicados, logs, `hola.txt`, `crash.journal`: eran residuos
  del proceso anterior.
- `EXCEL PARA ESTUDIANTES UCN.xlsx`: se copió a `assets\referencia`, pero está
  ignorado por git por si contiene datos institucionales.

## Importante

- **No uses más los scripts de la carpeta anterior.** El nuevo punto de entrada es
  `scripts\start.ps1`.
- El stack anterior (`myra_db-postgres-1`) se detuvo para liberar el puerto 5433 y
  reutilizar el volumen. No se borró nada.
- Hay commits locales pendientes de `git push` (requiere tus credenciales de GitHub).

## Cómo verificar

```powershell
.\scripts\start.ps1
.\scripts\db-migrate.ps1
docker compose ps
```

- n8n: <http://localhost:5678>
- PostgreSQL: `localhost:5433`, base `myra`
- Workflows: 2 borradores exportados en `n8n\workflows\`
- Credenciales: 3 (Telegram, Gemini, Postgres) con la key original
- Migraciones: 4 registradas en `schema_migrations`
