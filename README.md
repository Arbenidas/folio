# Folio

Folio es una aplicación de escritorio para macOS que permite escribir y organizar notas Markdown localmente. Puedes elegir el tema y la carpeta donde se guardan las notas.

> **Estado del proyecto:** en desarrollo. Las versiones alfa pueden contener errores y cambiar.

## Funciones

- Crear y renombrar notas con guardado automático.
- Elegir dónde guardar las notas y seleccionar entre cinco temas: Claro, Oscuro, Sepia, Bosque y Gruvbox.
- Editar con atajos de teclado y un subconjunto de comandos Vim.
- Ver una vista previa del Markdown.
- Importar archivos `.md` y `.txt` de hasta 1 MB. La importación crea una copia local y no modifica el original.
- Exportar una nota como archivo Markdown.

## Requisitos

- macOS 12 o posterior.
- Flutter 3.47.4 o posterior con Dart 3.13.3 o posterior.
- Xcode y sus herramientas de línea de comandos.

## Ejecutar desde el código fuente

Con Flutter instalado y este repositorio clonado, ejecuta desde la carpeta del proyecto:

```sh
flutter pub get
flutter run -d macos
```

## Atajos de teclado

### Notas y paneles

| Atajo | Acción |
| --- | --- |
| `Cmd+N` | Crear una nota |
| `Cmd+S` | Guardar la nota actual |
| `Cmd+1` / `Cmd+2` / `Cmd+3` | Enfocar notas / editor / vista previa |
| `Ctrl+H` / `Ctrl+L` | Desde NORMAL, enfocar notas / vista previa |
| `j` / `k` / `Enter` | En notas, elegir una nota / entrar al editor |
| `j` / `k` / `h` | En vista previa, desplazar / volver al editor |
| `?`, `F1` | Abrir la ayuda |

### Edición Vim

Activa el botón **Vim** para usar este modo. Folio implementa un subconjunto propio de Vim. No incluye Neovim, plugins, macros ni todos sus comandos.

| Atajo | Acción |
| --- | --- |
| `h` / `j` / `k` / `l` | Mover el cursor |
| `w` / `b` | Palabra siguiente / anterior |
| `0` / `$` | Inicio / último carácter de la línea |
| `gg` / `G` | Inicio / final del documento |
| `i` / `a` / `I` / `A` | Insertar / después / inicio / final de línea |
| `o` / `O` | Abrir línea debajo / encima |
| `x` / `dd` | Borrar carácter / línea |
| `yy` / `p` | Copiar línea / pegar debajo |
| `u` / `Ctrl+R` | Deshacer / rehacer |
| `/` / `n` / `N` | Buscar / siguiente / anterior |
| `:w` / `:new` / `:help` | Guardar / crear nota / abrir ayuda |

La búsqueda distingue mayúsculas. El historial de deshacer conserva hasta 200 cambios por nota abierta y se reinicia al cambiar de nota. Los movimientos verticales siguen las líneas del texto, incluso cuando una línea se parte visualmente por el ancho del editor.

## Almacenamiento y datos

Las notas se guardan en un archivo `notes.json` dentro de la carpeta seleccionada durante la configuración inicial. Folio necesita acceso a esa carpeta para guardar y volver a abrir las notas.

Si se encuentra un archivo `notebook.json` de una versión anterior y todavía no existe `notes.json`, Folio intenta recuperar esas notas. El archivo anterior se conserva. Al cambiar la carpeta, la aplicación copia las notas y deja la carpeta anterior como respaldo.

La vista previa muestra el texto alternativo de las imágenes Markdown y no descarga recursos externos.

## Desarrollo y comprobaciones

Antes de enviar cambios, ejecuta:

```sh
flutter analyze
flutter test
flutter build macos --debug
```

## Contribuir

Consulta [CONTRIBUTING.md](CONTRIBUTING.md) para reportar errores y proponer cambios.

## Licencia

Folio se distribuye bajo la licencia MIT. Consulta el archivo [LICENSE](LICENSE).

## Flujo de trabajo en GitHub

La rama `main` es la rama estable. Los cambios se proponen desde ramas de trabajo y se integran mediante pull request. No trabajes directamente sobre `main`.

Nombra las ramas según el tipo de cambio, por ejemplo `feature/nombre-corto`, `fix/nombre-corto` o `docs/nombre-corto`. Un flujo habitual es:

```sh
git switch main
git pull origin main
git switch -c feature/nombre-corto
# Haz y comprueba los cambios
git push -u origin feature/nombre-corto
```

Después abre un pull request hacia `main`. Espera a que pase el workflow **CI**, revisa los cambios y completa el merge desde GitHub. Al terminar, actualiza la rama local:

```sh
git switch main
git pull origin main
git branch -d feature/nombre-corto
```

### Configuración inicial del repositorio

Después de crear el repositorio en GitHub y subir la rama `main`, configura lo siguiente en **Settings**:

1. En **General → Pull Requests**, permite **Squash merging**. Puedes desactivar los otros métodos de merge para mantener un historial sencillo.
2. En **Rules → Rulesets**, crea un ruleset activo para la rama `main`.
3. Exige que los cambios entren mediante pull request y que pasen las comprobaciones de estado. Selecciona el check `checks` del workflow **CI**.
4. Bloquea force pushes y la eliminación de `main`.
5. Como el proyecto empieza con una persona mantenedora, no exijas aprobación obligatoria. Actívala cuando haya otra persona disponible para revisar PRs.

El workflow **CI** ejecuta análisis, pruebas y una compilación de macOS en cada pull request hacia `main`. No publica versiones automáticamente. Para la primera alfa, crea manualmente una GitHub Release con la etiqueta `v0.1.0-alpha.1`, márcala como pre-release y adjunta el DMG probado.
