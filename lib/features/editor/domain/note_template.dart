enum NoteTemplate {
  study(
    'Estudio',
    'Comprende un tema y conviértelo en preguntas para repasarlo.',
    '# Tema de estudio\n\n**Materia:** \n**Fuente o clase:** \n\n## Idea principal\n\n¿Qué estoy intentando entender?\n\n## Notas\n\n\n## Conceptos clave y preguntas\n\n- **Concepto:** ¿Qué significa?\n\n## Explicación en mis palabras\n\n\n## Resumen\n\n\n## Repaso activo\n\n- [ ] ¿Qué puedo explicar sin mirar mis notas?\n- [ ] ¿Qué necesito repasar otra vez?\n',
  ),
  idea(
    'Idea',
    'Aclara el problema, la propuesta y cómo podrías probarla.',
    '# Idea\n\n**Estado:** Idea inicial\n**Fecha:** \n\n## Problema u oportunidad\n\n¿Qué necesidad o situación quiero mejorar?\n\n## ¿Para quién?\n\n\n## Propuesta\n\nDescribe la idea en una frase:\n\n## ¿Por qué podría funcionar?\n\n\n## Suposiciones y riesgos\n\n- **Suposición:** \n- **Riesgo:** \n\n## Primer experimento\n\n¿Cuál es la prueba más pequeña que me daría información útil?\n\n- [ ] Próximo paso:\n\n## Notas\n\n',
  ),
  requirements(
    'Requisitos',
    'Define alcance, necesidades, criterios de aceptación y dudas.',
    '# Requisitos: [nombre del proyecto o función]\n\n**Responsable:** \n**Estado:** Borrador\n**Fecha:** \n\n## Objetivo\n\n¿Qué resultado queremos conseguir?\n\n## Problema y contexto\n\n\n## Usuarios y necesidades\n\n- **Usuario:** \n- **Necesidad:** \n\n## Alcance\n\n### Incluye\n- \n\n### Fuera de alcance\n- \n\n## Requisitos funcionales\n\n- [ ] El sistema debe...\n\n## Requisitos de calidad\n\nRendimiento, accesibilidad, seguridad, compatibilidad u otras restricciones.\n\n- \n\n## Criterios de aceptación\n\n- [ ] Dado que..., cuando..., entonces...\n\n## Dependencias y restricciones\n\n\n## Preguntas abiertas\n\n- [ ] \n',
  );

  const NoteTemplate(this.title, this.description, this.content);

  final String title;
  final String description;
  final String content;

  String get example => switch (this) {
    study =>
      '''
# Entender las promesas en JavaScript

**Materia:** Programación web

## Idea principal

Una promesa representa el resultado futuro de una operación.

## Notas

- Puede estar pendiente, cumplida o rechazada.
- `await` espera el resultado dentro de una función asíncrona.

## Conceptos clave y preguntas

- ¿Cómo manejo un error al usar `await`?

## Explicación en mis palabras

Es como pedir un café y seguir con otra cosa hasta que me avisen.

## Resumen

Las promesas ayudan a organizar operaciones que toman tiempo.

## Repaso activo

- [x] Explicar los tres estados sin mirar mis notas.
- [ ] Escribir un ejemplo con `try` y `catch`.
''',
    idea =>
      '''
# Recordatorios para repasar notas

**Estado:** Idea inicial

## Problema u oportunidad

Guardo apuntes útiles y luego olvido volver a leerlos.

## ¿Para quién?

Personas que estudian por su cuenta y llevan apuntes en Folio.

## Propuesta

Añadir una fecha de repaso a cada nota y mostrar las próximas en una lista.

## ¿Por qué podría funcionar?

Una lista corta ayuda a decidir qué tema retomar al abrir el cuaderno.

## Suposiciones y riesgos

- **Suposición:** Elegir una fecha tarda pocos segundos.
- **Riesgo:** Se acumulan demasiados recordatorios.

## Primer experimento

- [ ] Simular la lista durante una semana con cinco notas.

## Notas

Registrar cuántas veces vuelvo a un tema en la fecha prevista.
''',
    requirements =>
      '''
# Requisitos de búsqueda en notas

**Estado:** Borrador

## Objetivo

Encontrar una nota aunque no recuerde su título.

## Problema y contexto

Los cuadernos grandes son difíciles de recorrer carpeta por carpeta.

## Usuarios y necesidades

- Quien toma apuntes necesita recuperar una frase que escribió.

## Alcance

- **Incluye:** Buscar por título y contenido en el cuaderno actual.
- **Fuera de alcance:** Buscar dentro de imágenes adjuntas.

## Requisitos funcionales

- [ ] Mostrar el título y el fragmento donde aparece la coincidencia.

## Requisitos de calidad

- Permitir elegir un resultado con el teclado.

## Criterios de aceptación

- [ ] Al buscar «promesa», aparece una nota que contiene esa palabra en el cuerpo.

## Dependencias y restricciones

La búsqueda funciona con las notas locales.

## Preguntas abiertas

- [ ] ¿Cómo ordenar coincidencias de título y de contenido?
''',
  };
}
