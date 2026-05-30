# godev

Imagen de desarrollo basada en Debian para proyectos de Go y Node.js.

## Contenido de la imagen

- Go `1.26.0`
- Node.js `22.x`
- pnpm vía `corepack`
- PostgreSQL client
- zsh + Oh My Zsh + plugins
- `gopls`, `dlv` y `golangci-lint`
- `zoxide`, `git`, `jq`, `vim`, `make`, `unzip`

## Construir la imagen

Desde la raíz del repo:

```bash
docker build --pull -t godev:bookworm-slim .
```

## Ejecutar el contenedor para desarrollo

Ejemplo montando tu proyecto en `/workspace` y persistiendo el historial de shell:

```bash
docker run --rm -it \
	--name godev \
	-v "$PWD":/workspace \
	-v godev_history:/commandhistory \
	godev:bookworm-slim
```

## Reconstruir y recrear el contenedor

Si cambias el `Dockerfile`, debes reconstruir la imagen y volver a crear el contenedor.
Con el contenedor anterior corriendo, puedes hacerlo así:

```bash
docker rm -f godev 2>/dev/null || true
docker build --pull -t godev:bookworm-slim .
docker run --rm -it \
	--name godev \
	-v "$PWD":/workspace \
	-v godev_history:/commandhistory \
	godev:bookworm-slim
```

## Configuración del entorno

- Directorio de trabajo: `/workspace`
- Shell por defecto: `zsh`
- Usuario dentro del contenedor: `vscode`
- Historial compartido de zsh en `/commandhistory/.zsh_history`
- Cache de Go: `GOMODCACHE=/go/pkg/mod` y `GOCACHE=/home/vscode/.cache/go-build`
- Cache de Node: `PNPM_STORE_DIR=/home/vscode/.local/share/pnpm/store` y `NPM_CONFIG_CACHE=/home/vscode/.cache/npm`

## Verificación rápida

Dentro del contenedor puedes validar el entorno con:

```bash
go version
node --version
pnpm --version
psql --version
zsh --version
```
