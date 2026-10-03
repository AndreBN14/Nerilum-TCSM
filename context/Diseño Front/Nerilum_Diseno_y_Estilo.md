# Nerilum — diseño y estilo visual

Versión 1.0 · 28 de septiembre de 2026  
Ámbito: aplicación móvil Flutter para análisis exploratorio de imágenes cerebrales.

## 1. Dirección visual

Nerilum usa una interfaz oscura, sobria y legible, con grafito como base y verde menta como acento. La referencia cromática es el ambiente de las capturas de Opal compartidas para el proyecto; las formas, ilustraciones, logo y composición deben ser propios de Nerilum. El diseño comunica exploración de neuroimagen sin sugerir que la app emite un diagnóstico clínico.

La primera lámina aprobada como punto de partida contiene cuatro vistas: entrada, bienvenida, inicio de sesión y registro. La composición visual es conceptual; estos tokens y reglas son la especificación para implementarla. El contenido del home se definirá después.

## 2. Tokens de color

Estos HEX son una **propuesta de diseño aproximada** a partir de las referencias, no una extracción oficial de los colores de Opal.

| Token | HEX | Uso |
| --- | --- | --- |
| `background` | `#0B0D0C` | Fondo principal y pantalla de entrada |
| `surface` | `#1D201E` | Tarjetas, paneles y contenedores |
| `surfaceRaised` | `#272B28` | Elementos elevados y estados seleccionados |
| `field` | `#303431` | Campos de texto y botones secundarios |
| `mint` | `#C8F5D4` | Acción principal, marca y focos de atención |
| `mintSecondary` | `#9BD9B5` | Indicadores y luces secundarias |
| `mintDarkText` | `#102017` | Texto sobre botones claros |
| `textPrimary` | `#F5F7F5` | Títulos y contenido principal |
| `textSecondary` | `#A6ADA7` | Descripciones y ayuda |
| `border` | `#39413B` | Contornos sutiles |
| `error` | `#F0A7A2` | Errores de formulario, acompañado de texto |

El verde ocupa áreas pequeñas y acciones prioritarias. Las imágenes de resonancia se muestran en escala de grises; cualquier resalte de interfaz debe distinguirse de la imagen médica original. No usar rojo o verde como único indicador de estado.

## 3. Marca y logo

- Nombre visible: **Nerilum**. En la pantalla de entrada puede usarse `NERILUM` con espaciado amplio; en formularios se usa `Nerilum` si el tamaño es reducido.
- Isotipo: una **N geométrica propia**, formada por trazos diagonales y fragmentos separados. Debe funcionar en un solo color, además de la variante con brillo menta.
- Versiones previstas: isotipo, logotipo horizontal, composición vertical para entrada e icono de app. Mantener un área libre mínima equivalente a la mitad del ancho del trazo diagonal principal.
- El brillo es un efecto de presentación; los archivos fuente del símbolo deben conservar una versión plana para tamaños pequeños, accesibilidad y fondos complejos.
- Evitar un cerebro genérico dentro de la N y evitar símbolos de certificación médica.

## 4. Tipografía y jerarquía

Usar una familia sans serif legible en Android e iOS, por ejemplo **Inter** si se incorpora como recurso; en su ausencia, usar la tipografía de sistema mediante Flutter. No depender de una fuente descargada en tiempo de ejecución.

| Nivel | Tamaño orientativo | Peso | Uso |
| --- | --- | --- | --- |
| Título principal | 30–34 sp | 600–700 | Bienvenida y formularios |
| Título de sección | 22–26 sp | 600 | Secciones internas |
| Cuerpo | 16 sp | 400–500 | Explicaciones y campos |
| Etiqueta | 14 sp | 500–600 | Formulario y ayudas |
| Nota | 12–14 sp | 400 | Avisos, con contraste suficiente |

Mantener escalado de texto del sistema, salto de línea natural y altura de línea aproximada de 1.3–1.5 para párrafos. Evitar texto clínico importante por debajo de 14 sp.

## 5. Espaciado, formas y elevación

- Sistema base de 4 px; separaciones usuales: 8, 12, 16, 24, 32 y 48 px.
- Margen lateral de pantalla: 24 px en teléfono, adaptado a anchuras pequeñas.
- Botón principal: altura mínima de 52 px y borde totalmente redondeado; zona táctil mínima de 48 × 48 px.
- Campos: altura objetivo de 56–60 px, radios de 18–22 px, borde sutil y estados de foco claros.
- Tarjetas: radios de 24–30 px; usar contraste de superficie antes que sombras fuertes.
- No ubicar controles bajo la barra de estado, notch ni navegación del sistema; aplicar `SafeArea` y evitar que el teclado tape la acción.

## 6. Componentes y estados

| Componente | Estado base | Estados requeridos |
| --- | --- | --- |
| Acción principal | Fondo menta, texto oscuro | Presionado, deshabilitado, cargando |
| Acción secundaria | Fondo grafito, texto claro | Presionado, foco |
| Campo de entrada | Grafito y etiqueta visible | Foco, error, completado, deshabilitado |
| Enlace textual | Verde suave | Foco, presionado |
| Aviso | Texto claro y contenedor discreto | Informativo y error |

Mostrar mensajes de error concretos junto al campo y anunciar su contenido a tecnologías de asistencia. La animación de carga no sustituye una etiqueta textual.

## 7. Movimiento

El movimiento de Nerilum es breve y funcional: revela la marca y orienta el paso a la siguiente pantalla. Evitar flashes, destellos intensos y efectos continuos que distraigan. Usar curvas suaves (`easeOutCubic` o equivalente) y animaciones implementables con `AnimationController`, `AnimatedBuilder`, `SlideTransition`, `FadeTransition` y transformaciones ligeras.

La entrada y bienvenida tienen sus especificaciones y una alternativa de movimiento reducido en [Nerilum_Vistas_Iniciales.md](Nerilum_Vistas_Iniciales.md). Para usuarios con preferencia de reducir animaciones, mostrar el estado final estático y mantener toda la navegación disponible.

## 8. Contenido y tono

- Vocabulario de interfaz: «imagen cerebral», «análisis exploratorio», «resultado orientativo» y «categoría del modelo».
- Evitar en botones y mensajes afirmaciones como «diagnosticar Alzheimer» o «resultado clínico confirmado».
- No prometer «procesamiento local», «no se almacenan imágenes» ni «datos protegidos» hasta que la arquitectura y política de privacidad lo respalden.
- Las ilustraciones cerebrales son recursos de marca; no deben presentarse como resonancias reales ni como hallazgos del modelo.

## 9. Implementación y recursos en Flutter

Centralizar colores, radios, tipografía y espaciado en tokens (`ThemeData` o `ThemeExtension`) para que splash, onboarding y autenticación compartan valores. Preparar un recurso vectorial del logo y variantes rasterizadas para el icono de instalación; no usar una captura del mockup como asset de producción. Precargar el logo y la ilustración de bienvenida para evitar saltos visuales. Probar en pantallas estrechas y con tamaño de texto ampliado.

Esta especificación cubre la identidad y las vistas iniciales; el home, los resultados y los flujos de MRI requieren decisiones de contenido separadas.
