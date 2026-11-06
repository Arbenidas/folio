# Dictado local para Apuntes

Investigación: 2 de noviembre de 2026. Uso elegido: dictar con el micrófono e insertar texto en las notas. Equipo: Mac M4, 16 GB de memoria unificada.

## Primera opción para evaluar

**Whisper large-v3-turbo con WhisperKit**, preferiblemente la variante comprimida `large-v3-v20240930_626MB`. WhisperKit la recomienda para precisión multilingüe y ofrece integración nativa en Swift/Core ML. Permite ejecutar la transcripción localmente después de descargar los modelos, sin pagar por petición.

Los 626 MB del nombre describen la variante, no el consumo total de RAM durante la ejecución. La velocidad y la precisión con español salvadoreño y términos como Flutter, widget o HTTP aún no se han medido en este equipo.

- [Modelo Whisper large-v3-turbo](https://huggingface.co/openai/whisper-large-v3-turbo)
- [WhisperKit: instalación y variantes recomendadas](https://github.com/argmaxinc/argmax-oss-swift#whisperkit)

## Alternativas

| Modelo | Motivo para probarlo | Integración posible |
| --- | --- | --- |
| Parakeet TDT 0.6B v3 | Admite español, puntuación y 25 idiomas; candidato para dictado ágil. | FluidAudio en Swift/Core ML, con procesamiento por ventanas. |
| Qwen3-ASR 0.6B | Modelo especializado en reconocimiento de voz, incluye español. Es distinto del Qwen de texto instalado anteriormente. | Evaluar un runtime compatible con Apple Silicon; no asumir que Ollama lo ejecuta. |

- [Ficha oficial de Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- [FluidAudio: modelos, procesamiento local y streaming](https://github.com/FluidInference/FluidAudio)
- [Ficha oficial de Qwen3-ASR](https://huggingface.co/Qwen/Qwen3-ASR-0.6B)

FluidAudio también publica variantes más recientes (Ultra y Redux). No se ha comprobado su rendimiento ni calidad con la voz del usuario. Los benchmarks publicados para M4 Pro no son una medida del M4 de este proyecto.

## Integración propuesta, en pasos pequeños

1. Probar frases cortas en español, silencio y términos técnicos; medir tiempo de respuesta y memoria en este Mac.
2. Añadir un único botón de micrófono: iniciar → detener → transcribir → insertar en la posición de inicio. Para empezar, procesar al detener evita reescribir continuamente el texto mientras se habla.
3. Mantener una sesión asociada al ID de la nota y a la selección inicial. Si el usuario cambia de nota o modifica esa región, ofrecer el resultado para insertar en vez de escribirlo en una ubicación incorrecta.
4. Agregar cancelación y estados de descarga, escucha, transcripción y error. Solicitar permiso de micrófono solo al iniciar dictado.
5. Después evaluar transcripción por fragmentos para mostrar texto mientras se habla.

Organizarlo como `features/dictation`: interfaz de transcripción en dominio, implementación nativa en datos, controlador y botón en presentación. Un canal Flutter–Swift conecta con el motor local. El procesamiento de audio no debe bloquear el hilo de la interfaz.

WhisperKit declara macOS 14+ y Xcode 16+. La app actualmente declara macOS 12: al integrar habrá que establecer el nuevo mínimo o proteger la funcionalidad por versión. También serán necesarios el permiso de micrófono, su entitlement y una estrategia de descarga/caché del modelo. No se han cambiado esos requisitos ni se han descargado modelos en esta tarea.
