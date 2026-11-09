# Folio

Folio es una aplicación de escritorio para macOS que permite escribir y organizar notas Markdown localmente. Puedes elegir el tema y la carpeta donde se guardan las notas.

> **Estado del proyecto:** en desarrollo. Las versiones alfa pueden contener errores y cambiar.

## Funciones

- Crear y renombrar notas con guardado automático.
- Elegir dónde guardar las notas, combinar tres estilos visuales con siete temas de color y cambiar el tamaño de la ventana con doble clic en la barra superior.
- Editar con atajos de teclado y un subconjunto de comandos Vim.
- Buscar dentro de todas las notas con `Cmd+K` y saltar a la coincidencia.
- Crear notas de estudio, ideas y requisitos desde **Archivo → Nueva nota desde plantilla**, con una vista previa antes de elegir.
- Marcar y desmarcar tareas Markdown directamente en la vista previa.
- Pegar capturas con `Cmd+V` en el editor y verlas en la vista previa.
- Restaurar notas eliminadas desde **Archivo → Papelera**.
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
| `Cmd+K` | Buscar notas, carpetas y contenido |
| `Cmd+V` | Pegar texto o una captura en la nota |
| `Cmd+1` / `Cmd+2` / `Cmd+3` | Enfocar notas / editor / vista previa |
| `Ctrl+H` / `Ctrl+L` | Con Vim activado, enfocar notas / vista previa desde cualquier panel |
| `j` / `k` / `Enter` | En notas, elegir una nota / entrar al editor |
| `j` / `k` / `h` | En vista previa, desplazar / volver al editor |
| `?`, `F1` | Abrir la ayuda |

### Edición Vim

Activa el botón **Vim** para usar este modo. Folio recuerda tu preferencia y la última búsqueda entre sesiones. Folio implementa un subconjunto propio de Vim. No incluye Neovim, plugins, macros ni todos sus comandos.

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

La configuración inicial te da la bienvenida y después permite elegir una carpeta principal y un tema. Folio crea o reutiliza `<carpeta elegida>/Folio/`. Dentro, cada nota es un archivo `.md` normal y las carpetas de la barra lateral son carpetas reales, visibles también desde Finder. Los archivos contienen solo el texto Markdown, sin metadatos JSON.

Folio observa los cambios en esa carpeta mientras está abierto. Si un cambio externo choca con texto que aún no se había guardado, conserva una copia en **Archivo → Notas recuperadas**. Los borradores recuperados se guardan en el espacio privado de Folio, no dentro del cuaderno.

Los datos anteriores de `Notas Folio`, `notes.json` y `notebook.json` no se migran ni se borran; el nuevo cuaderno comienza en la carpeta `Folio/`. Al cambiar la ubicación desde Ajustes, Folio copia la estructura Markdown a la nueva carpeta y conserva el cuaderno anterior como respaldo.


Las capturas pegadas se guardan como PNG en `.folio-assets` junto a la nota. Al exportar una nota con capturas, elige una carpeta para guardar el Markdown y sus imágenes juntos. La vista previa muestra texto alternativo para imágenes externas y nunca las descarga.

Las notas que envías a la papelera se guardan en `.folio-trash` dentro del cuaderno. Si ya existe una nota con el mismo nombre al restaurar, Folio conserva ambas.

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

El workflow **CI** ejecuta análisis, pruebas y una compilación de macOS en cada pull request hacia `main`. El workflow **Release** compila y publica cada etiqueta `v*` como una GitHub Release, y actualiza el feed que consulta Sparkle.

Para habilitar las publicaciones automáticas, exporta la clave privada de Sparkle desde el Llavero de macOS y guárdala como el secreto `SPARKLE_PRIVATE_KEY` en **Settings → Secrets and variables → Actions** del repositorio. Codifica el archivo exportado en Base64 para guardarlo como secreto. No subas la clave ni el archivo exportado al repositorio. La clave pública ya está en `Info.plist`.

Para publicar una versión, actualiza `version` en `pubspec.yaml` e incrementa el número de compilación después de `+`. Añade sus notas en una nueva sección de `CHANGELOG.md` con el encabezado `## [versión] - fecha`. Crea y sube una etiqueta `v` que coincida con esa versión, por ejemplo `v0.1.0-alpha.1`. Actions generará el ZIP de actualización, firmará el feed y publicará las notas del release. Sparkle mostrará las novedades y ofrecerá instalar la actualización. La primera instalación todavía puede requerir autorización manual en macOS porque la app no está notarizada.
