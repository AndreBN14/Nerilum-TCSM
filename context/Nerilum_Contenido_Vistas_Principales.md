# Nerilum — contenido de las vistas principales

Versión 1.0 · 29 de septiembre de 2026  
Referencia: prototipo actualizado de **Inicio, Nuevo análisis y Perfil** con fondo grafito y resplandor verde superior.

## 1. Alcance

Este documento describe **qué muestra y qué permite hacer cada vista** del prototipo móvil. Es una especificación de interfaz y navegación para Flutter. Los datos de personas, fechas, miniaturas y resultados de los mockups son ilustrativos. El documento no establece contratos técnicos de integración, almacenamiento ni reglas clínicas.

Nerilum es una herramienta académica de clasificación exploratoria de imágenes MRI. En la interfaz se habla de **categoría del modelo** y **resultado orientativo**. No se presenta una predicción como diagnóstico de Alzheimer.

## 2. Navegación inferior común

La barra es una cápsula flotante oscura cerca del borde inferior, con tres posiciones:

| Posición | Icono y texto | Acción |
| --- | --- | --- |
| Izquierda | Casa — **Inicio** | Muestra la pantalla principal. |
| Centro | Cámara — **Analizar** | Abre el flujo de selección y análisis; botón circular menta de mayor tamaño. |
| Derecha | Persona — **Perfil** | Muestra cuenta, preferencias e información. |

El botón central es una **acción primaria**, no una categoría de salud ni un indicador de resultado. Debe conservar una etiqueta visible y una descripción accesible. Su icono de cámara expresa «seleccionar una imagen»; la primera versión contempla cargar un archivo MRI compatible, sin asumir que tomar una fotografía de una pantalla produzca una entrada válida.

La barra usa fondo `#1D201E` sobre un fondo de pantalla casi negro con un resplandor verde oscuro en la zona superior. Iconos y textos inactivos son claros; el botón central usa menta `#C8F5D4` con icono oscuro. La zona segura del sistema y el teclado no deben tapar los controles.

## 3. Vista Inicio

### Encabezado

- Isotipo N y nombre **NERILUM** en la parte superior izquierda.
- Acceso circular a Perfil en la parte superior derecha, como atajo opcional.
- Título: **«Explora imágenes cerebrales»**.
- Apoyo: **«Análisis orientativo de imágenes MRI.»**
- Botón principal: **«Seleccionar imagen»**, que abre el mismo flujo del botón central.

El encabezado es **tipográfico y sin ilustración cerebral grande**. El fondo conserva un resplandor verde tenue que da profundidad sin restar legibilidad al texto.

### Análisis recientes

Encabezado de sección **«Análisis recientes»** con enlace **«Ver todo»** a la vista de historial completo. Los registros se presentan como un **carrusel horizontal de tarjetas**: la primera cabe completa y parte de la siguiente queda visible para indicar que se puede deslizar hacia un lado. También debe funcionar con lectores de pantalla y navegación accesible.

Cada tarjeta muestra:

1. Miniatura del archivo analizado, si está disponible y su conservación está permitida.
2. Fecha del análisis.
3. Etiqueta tal como se registró: por ejemplo `MildDemented` o `NonDemented`.
4. Leyenda **«Categoría del modelo»**.

Tocar una tarjeta abre el detalle de ese análisis. **«Ver todo»** abre la lista completa. Si no hay análisis, mostrar un estado vacío: **«Aún no tienes análisis»**, seguido de un acceso a **«Seleccionar imagen»**. Si una miniatura no puede mostrarse, usar un marcador neutro de archivo sin sustituirla por una MRI ficticia.

### Aviso

Debajo del carrusel, antes de la barra inferior: **«Resultado orientativo · No es diagnóstico médico.»** Mantenerlo visible y legible, sin depender solo de un icono de información.

## 4. Vista Nuevo análisis

### Estado ilustrado en el prototipo: archivo seleccionado

- Barra superior con volver y título **«Nuevo análisis»**.
- Instrucción: **«Selecciona una imagen MRI cerebral»**.
- Texto auxiliar sobre el formato admitido en la versión que se implemente.
- Contenedor de selección con vista previa de la imagen elegida.
- Fila con nombre del archivo (ejemplo: `imagen_mri.jpg`), formato y acción para quitarlo.
- Acción primaria **«Analizar imagen»**.
- Acción secundaria **«Cambiar imagen»**.
- Aviso: **«Resultado orientativo · No es diagnóstico médico.»**

El archivo de ejemplo y la miniatura del prototipo no son datos reales de una persona ni garantizan compatibilidad con el futuro modelo.

### Estados que debe contemplar la interfaz

| Estado | Contenido y acciones |
| --- | --- |
| Sin archivo | Área de selección vacía, formatos permitidos y botón «Seleccionar imagen». «Analizar imagen» no está disponible. |
| Archivo seleccionado | Vista previa, nombre, opción de cambiar o quitar, botón de análisis habilitado. |
| Archivo no válido | Mensaje concreto sobre formato, tamaño o lectura, con opción de volver a elegir. |
| Procesando | Indicador con texto «Analizando imagen» y prevención de envíos repetidos. |
| Error | Explicación comprensible y opción de reintentar o cambiar archivo. |
| Resultado | Categoría del modelo, puntuaciones si se muestran y explicación visible de sus límites. |

No mostrar una caja del hipocampo sobre la imagen salvo que exista un modelo de detección o segmentación entrenado y evaluado para ello. El prototipo actual representa una tarea de **clasificación de imagen**.

## 5. Vista Perfil

### Cabecera de cuenta

Título **«Mi perfil»** y tarjeta con avatar neutro, nombre y correo. En el mockup «André» y `andre@ejemplo.com` son datos de demostración. Tocar la tarjeta puede abrir **Mi cuenta**.

### Opciones de la lista

| Opción | Vista o contenido previsto |
| --- | --- |
| **Mi cuenta** | Datos básicos y edición de los campos permitidos. |
| **Preferencias** | Reducción de animaciones, tamaño de texto y ajustes visuales disponibles. |
| **Historial completo** | Lista de análisis anteriores y acceso a sus detalles. |
| **Privacidad y datos** | Información clara sobre el tratamiento de imágenes y controles que efectivamente se implementen. |
| **Acerca de Nerilum** | Propósito académico, versión de la app, alcance y limitaciones. |
| **Cerrar sesión** | Salida de la cuenta con confirmación cuando corresponda. |

No incluir promesas de privacidad que todavía no estén respaldadas por la implementación y la documentación del proyecto. El historial también es accesible desde Inicio mediante «Ver todo».

## 6. Comportamientos transversales

- **Selección activa:** Inicio y Perfil muestran claramente cuál sección está abierta. El botón central mantiene su jerarquía visual como acción principal.
- **Deslizamiento:** el carrusel de Inicio avanza por tarjetas y conserva márgenes para que el contenido no quede bajo la barra inferior.
- **Texto adaptable:** títulos, categorías largas y nombres de archivo pueden ocupar varias líneas o truncarse con acceso al contenido completo; evitar tamaños fijos que desborden en pantallas pequeñas.
- **Movimiento:** transiciones discretas y una alternativa estática si el usuario prefiere reducir animaciones.
- **Estados vacíos y errores:** deben tener texto y una acción posible; no dejar una pantalla en blanco.
- **Lenguaje:** usar «categoría del modelo» y «resultado orientativo»; no convertir `NonDemented` en «paciente sano».

## 7. Criterios de aceptación visual y funcional

- [ ] Las tres vistas comparten el mismo fondo grafito con verde oscuro tenue en la zona superior.
- [ ] Inicio no contiene una ilustración cerebral grande en el encabezado.
- [ ] Inicio muestra un carrusel horizontal con una tarjeta completa y la siguiente parcialmente visible.
- [ ] Cada tarjeta del historial identifica fecha y categoría del modelo, y abre su detalle al tocarla.
- [ ] La acción central **Analizar** es más grande que Inicio y Perfil y abre la selección de archivo.
- [ ] Nuevo análisis distingue estados sin archivo, archivo seleccionado, error y procesamiento.
- [ ] Perfil presenta las seis opciones descritas y usa datos reales solo cuando existan.
- [ ] En Inicio y análisis se lee que el resultado es orientativo y no diagnóstico.

## 8. Decisiones abiertas

Quedan por definir el diseño del historial completo, detalle de resultado, política de conservación de imágenes, datos reales del perfil y formato exacto de archivo admitido por la versión entrenada del modelo. El prototipo no decide esos puntos por sí mismo.
