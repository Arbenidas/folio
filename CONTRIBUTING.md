# Contribuir a Folio

Gracias por considerar una contribución. Los reportes y cambios pequeños ayudan a mejorar Folio.

## Antes de empezar

Para ejecutar Folio desde el código necesitas macOS 12 o posterior, Flutter 3.38.4 o posterior, Dart 3.13.3 o posterior y Xcode con sus herramientas de línea de comandos. Consulta [README.md](README.md#ejecutar-desde-el-código-fuente) para iniciar la aplicación.

Si quieres proponer un cambio grande, abre primero un issue para conversar sobre el alcance y evitar trabajo que no encaje con la dirección del proyecto.

## Reportar un error

Abre un issue e incluye, cuando sea posible:

- Qué esperabas que ocurriera y qué ocurrió en realidad.
- Pasos breves para reproducir el problema.
- Versión de Folio, versión de macOS y arquitectura del equipo.
- Captura de pantalla o mensaje de error, si ayuda a entenderlo.

No adjuntes notas privadas ni datos personales. Reemplaza el contenido de las notas por texto de ejemplo antes de compartir capturas o archivos.

## Proponer un cambio

1. Actualiza `main` y crea una rama `feature/`, `fix/` o `docs/` según el cambio.
2. Mantén el cambio acotado y describe su motivo.
3. Ejecuta las comprobaciones pertinentes antes de abrir el pull request:

   ```sh
   flutter analyze
   flutter test
   flutter build macos --debug
   ```

4. Sube tu rama y abre un pull request hacia `main` con un resumen, las comprobaciones ejecutadas y cualquier efecto en el guardado, importación o exportación de notas.
5. Si cambia la interfaz, añade una captura o una descripción del resultado.

Si una comprobación no se puede ejecutar, indícalo en el pull request y explica por qué. No incluyas compilaciones locales, archivos de notas, credenciales ni secretos.

## Licencia

Al enviar una contribución, aceptas que se distribuya bajo la licencia MIT de Folio. Conserva los avisos de licencia y autoría de recursos de terceros que incorpores.
