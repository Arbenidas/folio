enum TemplateCategory {
  organization('Organización'),
  projects('Proyectos'),
  creativity('Aprendizaje y creación');

  const TemplateCategory(this.label);

  final String label;
}

enum NoteTemplate {
  daily(
    'Plan diario',
    'Enfoca tu día con 3 prioridades, bloques de tiempo y cierre.',
    TemplateCategory.organization,
    '# Plan diario\n\n#diario\n\n## Top 3 prioridades\n\n- [ ] Prioridad 1:\n- [ ] Prioridad 2:\n- [ ] Prioridad 3:\n\n## Bloques de enfoque\n\n- **Mañana:** \n- **Tarde:** \n- **Pendientes rápidos:** \n\n## Notas del día\n\n\n## Cierre y reflexión\n\n- **¿Qué salió bien hoy?** \n- **¿Qué dejo listo para mañana?** \n',
  ),
  weekly(
    'Revisión semanal',
    'Cierra tu semana con claridad, revisa avances y planea la siguiente.',
    TemplateCategory.organization,
    '# Revisión semanal\n\n#semanal #organizacion\n\n## Logros de la semana\n\n- \n- \n\n## Proyectos y avance\n\n- **Proyecto 1:** \n- **Proyecto 2:** \n\n## Qué soltar o mejorar\n\n- \n\n## Objetivos próxima semana\n\n- [ ] Objetivo principal:\n- [ ] Objetivo secundario:\n- [ ] Hábito a proteger:\n',
  ),
  goals(
    'Metas y hábitos',
    'Convierte un objetivo grande en pasos medibles y hábitos diarios.',
    TemplateCategory.organization,
    '# Meta: [nombre de la meta]\n\n#metas #habitos\n\n**Horizonte:** \n**Estado:** En marcha\n\n## Por qué importa\n\n\n## Cómo sabré que lo logré\n\n- [ ] Indicador 1:\n- [ ] Indicador 2:\n\n## Hábitos y sistema semanal\n\n- **Frecuencia:** \n- **Momento fijo:** \n\n## Próximos pasos concretos\n\n- [ ] Paso 1:\n- [ ] Paso 2:\n\n## Obstáculos y plan B\n\n- **Si pasa:** … → **Entonces haré:** …\n',
  ),
  project(
    'Plan de proyecto',
    'Organiza objetivos, hitos, tareas clave y enlaces en un solo lugar.',
    TemplateCategory.projects,
    '# Proyecto: [nombre]\n\n#proyecto\n\n**Estado:** Activo\n**Objetivo:** \n**Fecha meta:** \n\n## Resumen\n\n¿Qué problema resuelve este proyecto y qué resultado buscamos?\n\n## Hitos\n\n- [ ] **Hito 1:** \n- [ ] **Hito 2:** \n- [ ] **Lanzamiento:** \n\n## Tareas inmediatas\n\n- [ ] \n- [ ] \n\n## Decisiones y notas\n\n- \n\n## Enlaces y recursos\n\n- \n',
  ),
  meeting(
    'Minuta de reunión',
    'Captura agenda, acuerdos claros y responsables sin perder detalle.',
    TemplateCategory.projects,
    '# Reunión: [tema]\n\n#reunion\n\n**Fecha:** \n**Participantes:** \n\n## Agenda\n\n1. \n2. \n\n## Notas clave\n\n- \n\n## Decisiones tomadas\n\n- \n\n## Próximas acciones\n\n- [ ] **[Responsable]:** Acción — *fecha*\n- [ ] **[Responsable]:** Acción — *fecha*\n',
  ),
  requirements(
    'Requisitos',
    'Define alcance, necesidades, criterios de aceptación y dudas.',
    TemplateCategory.projects,
    '# Requisitos: [nombre del proyecto o función]\n\n#requisitos\n\n**Responsable:** \n**Estado:** Borrador\n**Fecha:** \n\n## Objetivo\n\n¿Qué resultado queremos conseguir?\n\n## Problema y contexto\n\n\n## Usuarios y necesidades\n\n- **Usuario:** \n- **Necesidad:** \n\n## Alcance\n\n### Incluye\n- \n\n### Fuera de alcance\n- \n\n## Requisitos funcionales\n\n- [ ] El sistema debe...\n\n## Requisitos de calidad\n\nRendimiento, accesibilidad, seguridad, compatibilidad u otras restricciones.\n\n- \n\n## Criterios de aceptación\n\n- [ ] Dado que..., cuando..., entonces...\n\n## Dependencias y restricciones\n\n\n## Preguntas abiertas\n\n- [ ] \n',
  ),
  study(
    'Estudio',
    'Comprende un tema y conviértelo en preguntas para repasarlo.',
    TemplateCategory.creativity,
    '# Tema de estudio\n\n#estudio\n\n**Materia:** \n**Fuente o clase:** \n\n## Idea principal\n\n¿Qué estoy intentando entender?\n\n## Notas\n\n\n## Conceptos clave y preguntas\n\n- **Concepto:** ¿Qué significa?\n\n## Explicación en mis palabras\n\n\n## Resumen\n\n\n## Repaso activo\n\n- [ ] ¿Qué puedo explicar sin mirar mis notas?\n- [ ] ¿Qué necesito repasar otra vez?\n',
  ),
  idea(
    'Idea',
    'Aclara el problema, la propuesta y cómo podrías probarla.',
    TemplateCategory.creativity,
    '# Idea\n\n#idea\n\n**Estado:** Idea inicial\n**Fecha:** \n\n## Problema u oportunidad\n\n¿Qué necesidad o situación quiero mejorar?\n\n## ¿Para quién?\n\n\n## Propuesta\n\nDescribe la idea en una frase:\n\n## ¿Por qué podría funcionar?\n\n\n## Suposiciones y riesgos\n\n- **Suposición:** \n- **Riesgo:** \n\n## Primer experimento\n\n¿Cuál es la prueba más pequeña que me daría información útil?\n\n- [ ] Próximo paso:\n\n## Notas\n\n',
  ),
  article(
    'Guión o artículo',
    'Estructura gancho, puntos clave y cierre para tu blog o video.',
    TemplateCategory.creativity,
    '# Título tentativo\n\n#contenido\n\n**Formato:** Artículo / Video\n**Audiencia:** \n\n## Gancho inicial\n\n¿Por qué alguien querría leer o ver esto en los primeros 10 segundos?\n\n## Estructura\n\n### 1. Contexto o problema\n- \n\n### 2. Idea central / Solución\n- \n\n### 3. Ejemplo práctico\n- \n\n## Cierre y llamado a la acción\n\n\n## Checklist de publicación\n\n- [ ] Revisar claridad y ritmo\n- [ ] Añadir capturas o portada\n- [ ] Publicar y compartir\n',
  );

  const NoteTemplate(this.title, this.description, this.category, this.content);

  final String title;
  final String description;
  final TemplateCategory category;
  final String content;

  static String dailyContentFor(DateTime date) {
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    const weekdays = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    final dayLabel =
        '${weekdays[date.weekday - 1]} ${date.day} de ${months[date.month - 1]} de ${date.year}';
    return '# $dayLabel\n\n#diario\n\n## Top 3 prioridades\n\n- [ ] \n- [ ] \n- [ ] \n\n## Bloques de enfoque\n\n- **Mañana:** \n- **Tarde:** \n\n## Notas rápidas\n\n\n## Cierre del día\n\n- **Logro principal:** \n- **Para mañana:** \n';
  }

  String get example => switch (this) {
    daily => '''
# Viernes 20 de noviembre

#diario

## Top 3 prioridades

- [x] Cerrar rediseño del panel lateral de Folio
- [ ] Grabar demo corta de las nuevas plantillas
- [ ] Revisar pendientes de la semana

## Bloques de enfoque

- **Mañana:** 2 pomodoros de escritura sin distracciones
- **Tarde:** Pruebas de exportación a PDF y revisión de backlog

## Notas rápidas

El modo enfoque ayuda muchísimo a mantener el ritmo en borradores largos.

## Cierre y reflexión

- **¿Qué salió bien hoy?** Terminé el bloque principal antes del mediodía.
- **¿Qué dejo listo para mañana?** Guión del video de lanzamiento.
''',
    weekly => '''
# Semana 47 · Noviembre

#semanal #organizacion

## Logros de la semana

- Lanzamiento interno de Folio con panel de tareas lateral.
- Publicación de artículo sobre SemVer en arbe.blog.

## Proyectos y avance

- **Folio:** Rendimiento y experiencia de escritura completados.
- **Blog:** 1 borrador listo para portada.

## Qué soltar o mejorar

- Evitar reuniones largas en las primeras 2 horas del día.

## Objetivos próxima semana

- [ ] Grabar video de presentación de Folio
- [ ] Documentar atajos favoritos
- [ ] Mantener 30 min diarios de lectura técnica
''',
    goals => '''
# Meta: Publicar 12 artículos técnicos este año

#metas #habitos

**Horizonte:** Q4 · 2026
**Estado:** En marcha (8/12)

## Por qué importa

Escribir aclara lo que aprendo y construye un archivo público útil.

## Cómo sabré que lo logré

- [x] 8 artículos publicados con ejemplos reales
- [ ] 4 artículos nuevos antes de fin de año

## Hábitos y sistema semanal

- **Frecuencia:** Martes y jueves · 45 minutos
- **Momento fijo:** 8:00 AM con Modo Enfoque + Pomodoro

## Próximos pasos concretos

- [ ] Elegir el tema del artículo #9
- [ ] Sacar 3 capturas limpias
''',
    project => '''
# Proyecto: Lanzamiento Folio v0.2

#proyecto

**Estado:** Activo
**Objetivo:** Convertir Folio en un espacio rápido para escribir y organizarse.

## Hitos

- [x] **Hito 1:** Panel lateral de tareas Kanban y Eisenhower
- [x] **Hito 2:** Ajustes en vivo junto al editor
- [ ] **Lanzamiento:** Video demo y notas de versión

## Tareas inmediatas

- [ ] Validar exportación a PDF con temas claro y oscuro
- [ ] Revisar guía rápida de atajos

## Decisiones y notas

- Priorizar interfaz nativa de macOS frente a modales estilo móvil.
''',
    meeting => '''
# Reunión: Revisión de diseño Folio

#reunion

**Fecha:** 20 nov 2026
**Participantes:** Diego, Diseño

## Agenda

1. Flujo de tareas en barra lateral
2. Plantillas de organización personal

## Notas clave

- Los ajustes en vivo reducen la fricción al probar temas y tipografías.
- Las plantillas deben cubrir día, semana, proyectos y escritura.

## Decisiones tomadas

- Unificar los menús secundarios dentro del panel lateral de Ajustes.

## Próximas acciones

- [ ] **Diego:** Implementar galería de plantillas y nota diaria `⌘D`
''',
    study => '''
# Entender las promesas en JavaScript

#estudio

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
    idea => '''
# Recordatorios para repasar notas

#idea

**Estado:** Idea inicial

## Problema u oportunidad

Guardo apuntes útiles y luego olvido volver a leerlos.

## ¿Para quién?

Personas que estudian por su cuenta y llevan apuntes en Folio.

## Propuesta

Añadir una fecha de repaso a cada nota y mostrar las próximas en una lista.

## Primer experimento

- [ ] Simular la lista durante una semana con cinco notas.
''',
    requirements => '''
# Requisitos de búsqueda en notas

#requisitos

**Estado:** Borrador

## Objetivo

Encontrar una nota aunque no recuerde su título.

## Alcance

- **Incluye:** Buscar por título, contenido y `#etiquetas`.
- **Fuera de alcance:** Buscar dentro de imágenes adjuntas.

## Criterios de aceptación

- [ ] Al buscar «promesa», aparece la nota con el fragmento resaltado.
''',
    article => '''
# Cómo diseñar un editor Markdown que dé gusto usar

#contenido

**Formato:** Video + Artículo en arbe.blog
**Audiencia:** Desarrolladores y escritores en macOS

## Gancho inicial

¿Por qué algunas apps de notas invitan a escribir durante horas y otras cansan en 5 minutos?

## Estructura

### 1. Contexto o problema
- Exceso de ruido visual y latencia al teclear.

### 2. Idea central / Solución
- Tipografía cuidada, colores cálidos y herramientas que aparecen solo cuando las necesitas.

### 3. Ejemplo práctico
- Demo en vivo de Folio: Modo Enfoque, `⌘D` y tareas laterales.

## Checklist de publicación

- [x] Esquema aprobado
- [ ] Grabar pantalla en 60fps
''',
  };
}
