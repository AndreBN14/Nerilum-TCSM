# Nerilum — contexto del proyecto

Versión 1.0 · 28 de septiembre de 2026

## 1. Identidad

**Nerilum** es el nombre de una aplicación móvil de investigación desarrollada con Flutter. El proyecto explora el uso de modelos de visión computacional de la familia YOLO para clasificar imágenes de resonancia magnética cerebral en categorías presentes en un conjunto de entrenamiento. Su uso previsto es **académico y demostrativo**.

Título de trabajo: **«Aplicación móvil con YOLO para la detección y clasificación de posibles signos de Alzheimer mediante imágenes de resonancia magnética»**. El título refleja la línea de investigación; la funcionalidad implementada debe describirse según lo que el modelo realmente haya sido entrenado y evaluado para hacer.

## 2. Problema y propósito

El proyecto investiga si un modelo de aprendizaje profundo puede identificar patrones estadísticos en imágenes MRI y ofrecer una clasificación orientativa dentro de las clases del dataset seleccionado. La aplicación permite presentar de manera comprensible un experimento de inteligencia artificial y sus límites.

**Nerilum no determina si una persona tiene Alzheimer, no establece un estadio clínico y no sustituye la evaluación médica.** Una predicción del modelo depende de la calidad de la imagen, del conjunto de entrenamiento y de la validación realizada.

## 3. Objetivo general

Diseñar y evaluar un prototipo móvil que permita seleccionar una imagen MRI cerebral, procesarla con un modelo YOLO entrenado para clasificación de imágenes y mostrar una categoría **orientativa**, con una explicación clara de sus limitaciones.

### Objetivos específicos

1. Documentar el origen, las licencias y la composición del conjunto de imágenes.
2. Preparar los datos de entrenamiento, validación y prueba, con controles contra duplicados y filtraciones entre particiones.
3. Entrenar y comparar variantes de modelos YOLO para **clasificación** de imágenes.
4. Evaluar resultados por clase y registrar las condiciones experimentales.
5. Diseñar una interfaz Flutter clara para selección de imagen y lectura crítica del resultado.
6. Comunicar los límites del prototipo para evitar su interpretación como herramienta diagnóstica.

## 4. Datos previstos y estado de verificación

La propuesta inicial menciona un conjunto publicado en Kaggle como **«Alzheimer MRI Dataset»**, con imágenes JPG y cuatro carpetas o clases: `NonDemented`, `VeryMildDemented`, `MildDemented` y `ModerateDemented`. El documento inicial habla de aproximadamente **40 000 imágenes**. Esta cifra y la distribución por clase deben **confirmarse en la versión concreta descargada**; no se asumen como un inventario ya validado.

Antes de entrenar, registrar en una ficha del dataset: enlace y autor de la publicación, versión o fecha de descarga, licencia y condiciones de uso, número de archivos válidos, tamaño de las imágenes, clases, balance, procedencia de las imágenes y existencia de identificadores de paciente, estudio y visita. No tratar las cuatro carpetas como categorías clínicas comparables a CN/MCI/AD de ADNI sin una justificación y correspondencia documentadas.

El dataset JPG propuesto es de **clasificación 2D**. Sus etiquetas de carpeta no aportan por sí solas máscaras del hipocampo ni cajas delimitadoras. Esas anotaciones requerirían otra fuente verificada o anotación adicional. ADNI y posibles datos de segmentación constituyen una **línea de investigación separada**, pendiente de permisos, cruce de identificadores y validación espacial; no son una capacidad disponible por el mero uso del dataset de Kaggle.

## 5. Alcance del modelo

### Primera versión experimental

- **Entrada conceptual:** una imagen cerebral 2D compatible con el preprocesamiento usado en entrenamiento.
- **Tarea:** clasificación de la imagen completa con una variante YOLO de clasificación (`-cls`).
- **Salida:** una de las cuatro categorías del dataset y, si el modelo lo permite, puntuaciones por categoría. Estas puntuaciones son salidas del modelo y no equivalen automáticamente a probabilidades clínicas calibradas.

### Línea futura condicionada

La **detección/localización del hipocampo** es una tarea distinta: necesita anotaciones anatómicas verificadas, como máscaras o bounding boxes vinculadas correctamente a las MRI. Entrenar `yolo11l-cls.pt` o `yolov5l-cls.pt` para clasificación **no** produce una caja del hipocampo. Si se incorpora esta etapa, se documentará un dataset, una arquitectura de detección o segmentación y una evaluación propios.

## 6. Evaluación experimental mínima

- Separar entrenamiento, validación y prueba por **paciente** cuando existan identificadores; si no existen, documentar que no se puede garantizar independencia entre pacientes.
- Inspeccionar duplicados exactos y casi duplicados entre particiones, en especial cortes similares de una misma resonancia.
- Registrar matriz de confusión, precisión, recall y F1 por clase, además de métricas agregadas adecuadas al desbalance.
- Evaluar el rendimiento en el conjunto de prueba una vez elegido el modelo; no usar ese conjunto para escoger hiperparámetros.
- Reportar versión del dataset, preprocesamiento, semilla, tamaño de imagen, versión del modelo y condiciones de entrenamiento.
- Examinar errores por calidad, recorte, orientación e imagen fuera de distribución. La exactitud sobre un dataset de JPG no demuestra validez clínica ni generalización a MRI hospitalarias.

## 7. Experiencia móvil prevista

El lenguaje de la interfaz se centra en **«explorar imágenes cerebrales»**, **«análisis orientativo»** y **«categoría del modelo»**. El recorrido funcional previsto comprende entrada animada, bienvenida, registro/inicio de sesión, selección de imagen, espera de procesamiento y lectura del resultado. El contenido y la distribución del **home aún no están definidos**.

Las vistas ya especificadas son entrada, bienvenida e inicio de sesión; el registro cuenta con un mockup visual inicial. Los criterios de color y componentes están en `Nerilum_Diseno_y_Estilo.md`, y las transiciones de entrada y bienvenida en `Nerilum_Vistas_Iniciales.md`.

En la pantalla de resultado se debe mostrar la categoría exactamente como fue definida por el experimento, acompañada de texto comprensible y de una advertencia visible: **«Resultado orientativo. No constituye un diagnóstico médico.»** No inferir «paciente sano» a partir de `NonDemented` ni convertir `VeryMildDemented` en una valoración clínica individual.

## 8. Identidad visual acordada

Marca: **Nerilum**, con isotipo de N geométrica. Paleta: fondo gris casi negro `#0B0D0C`, superficies grafito `#1D201E`, verde menta principal `#C8F5D4`, texto claro `#F5F7F5`. Las capturas de Opal sirven como **referencia de ambiente cromático**, mientras que símbolo, arte cerebral y composiciones pertenecen a Nerilum.

La entrada animada presenta la N, desplaza el símbolo hacia la izquierda, revela «Nerilum» y se desvanece. La bienvenida introduce el propósito mediante una ilustración abstracta y movimiento sutil. Ambas vistas tienen un estado estático equivalente para personas que prefieran reducir movimiento.

## 9. Riesgos y decisiones pendientes

| Tema | Riesgo o decisión necesaria |
| --- | --- |
| Procedencia | Verificar fuente primaria, licencia y trazabilidad del dataset difundido en Kaggle. |
| Etiquetas | Las cuatro clases provienen del dataset; su significado clínico y método de asignación deben verificarse. |
| Independencia | Si faltan identificadores de paciente, una división por archivo puede inflar el rendimiento. |
| Generalización | JPG preprocesados pueden diferir considerablemente de nuevos estudios MRI. |
| Explicabilidad | La categoría no identifica por sí sola una región anatómica ni explica una causa. |
| Hipocampo | La detección requiere anotaciones y evaluación diferentes a las de clasificación. |
| Home | Definir primero su objetivo, contenido y acciones antes de diseñar la pantalla. |
| Comunicación | Revisar textos y pantallas para que ninguna predicción parezca diagnóstico. |

## 10. Criterio de avance

La primera etapa queda delimitada como **prototipo académico de clasificación 2D con cuatro etiquetas del dataset**. Una etapa de detección del hipocampo o de clasificación clínica AD/MCI/CN solo se incorporará cuando existan datos adecuados, trazabilidad de las etiquetas y una evaluación independiente. Este documento establece el contexto del producto y de la investigación; las decisiones técnicas de integración se documentarán por separado cuando estén definidas.
