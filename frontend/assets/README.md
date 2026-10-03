# Nerilum — assets para Flutter

Marca y paleta: fondo `#0B0D0C`, grafito `#1D201E`, menta `#C8F5D4`, texto `#F5F7F5`.

## Archivos

| Ruta | Uso |
| --- | --- |
| `brand/nerilum-mark.svg` y `nerilum-mark-{128,256,512,1024}.png` | Isotipo N transparente |
| `brand/nerilum-mark-white.svg` y PNG | Isotipo monocromo |
| `brand/nerilum-wordmark.svg` | Nombre sin símbolo, transparente |
| `brand/nerilum-logo-horizontal.svg` y `.png` | Logo completo horizontal, transparente |
| `brand/nerilum-logo-stacked.svg` y `.png` | Logo completo vertical para entrada, transparente |
| `brand/nerilum-app-icon-1024.png` | Icono cuadrado con fondo grafito |
| `brand/nerilum-adaptive-foreground-1024.png` | Primer plano transparente con margen de seguridad para icono adaptativo |
| `illustrations/nerilum-welcome-hero.png` | Arte cerebral conceptual con transparencia para bienvenida |

## Integración sugerida

Copiar `brand/` y `illustrations/` dentro de `assets/nerilum/`. Si se usan SVG dentro de Flutter, incorporar un renderizador SVG compatible. Los PNG funcionan con `Image.asset`. Declarar las rutas de assets en `pubspec.yaml` según la estructura real del proyecto.

Usar el logo apilado en la pantalla de entrada solo como referencia visual del estado final. Para animar la N y revelar las letras, componer `nerilum-mark.svg` con texto Flutter o con el wordmark independiente. El símbolo no debe animarse como una captura plana de pantalla.

El PNG de la ilustración es **arte decorativo**, no una MRI clínica ni un hallazgo del modelo. No usarlo como entrada de prueba del clasificador. Los archivos del icono y marca fueron trazados a partir del concepto de Nerilum; comprobar cómo se ven a tamaño de dispositivo antes de publicar.
