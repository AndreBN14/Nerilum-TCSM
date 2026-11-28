import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/theme/nerilum_theme.dart';
import '../../data/datasources/http_analysis_data_source.dart';
import '../../data/repositories/pdf_report_repository.dart';
import '../../domain/models/analysis_result.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../states/web_view_states.dart';

/// Vista Reporte del portal web.
///
/// Carga el análisis con GET /api/v1/analyses/{id} y genera el PDF en el
/// navegador usando el paquete `pdf` + `printing`. No requiere ningún
/// endpoint de backend para la generación.
class WebReportScreen extends StatefulWidget {
  const WebReportScreen({
    super.key,
    required this.analysisId,
    this.analysisSource,
  });

  final String analysisId;
  // null cuando API_BASE_URL no está configurada.
  final HttpAnalysisDataSource? analysisSource;

  @override
  State<WebReportScreen> createState() => _WebReportScreenState();
}

class _WebReportScreenState extends State<WebReportScreen> {
  WebViewStatus _status = WebViewStatus.loading;
  AnalysisResult? _result;
  bool _generating = false;
  String? _loadError;
  String? _pdfError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _status = WebViewStatus.loading;
      _loadError = null;
      _pdfError = null;
    });

    final source = widget.analysisSource;
    if (source == null) {
      if (!mounted) return;
      setState(() {
        _loadError = 'El backend de análisis no está configurado. '
            'Define API_BASE_URL al ejecutar la app.';
        _status = WebViewStatus.error;
      });
      return;
    }

    try {
      // GET /api/v1/analyses/{id}
      final result = await source.findById(widget.analysisId);
      if (!mounted) return;
      if (result == null) {
        setState(() => _status = WebViewStatus.empty);
      } else {
        setState(() {
          _result = result;
          _status = WebViewStatus.content;
        });
      }
    } on AnalysisFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _status = isSessionExpiredError(e.message)
            ? WebViewStatus.sessionExpired
            : WebViewStatus.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'No se pudo cargar el análisis para el reporte.';
        _status = WebViewStatus.error;
      });
    }
  }

  Future<void> _downloadPdf() async {
    final result = _result;
    if (result == null || _generating) return;
    setState(() {
      _generating = true;
      _pdfError = null;
    });
    try {
      // Descarga la imagen y el mapa persistidos para incluirlos en el PDF,
      // igual que hace la app móvil al exportar. Si la imagen falla, se
      // aborta como en móvil; el mapa es prescindible y el PDF sale sin él.
      Uint8List? imageBytes;
      Uint8List? gradcamBytes;
      final source = widget.analysisSource;
      final id = result.id;
      if (source != null && id != null) {
        if (result.hasImage) {
          try {
            imageBytes = await source.loadImage(id);
          } catch (_) {
            if (!mounted) return;
            setState(() => _pdfError =
                'No se pudo recuperar la imagen para el PDF. Inténtalo de nuevo.');
            return;
          }
        }
        if (result.hasGradcam) {
          try {
            gradcamBytes = await source.loadGradcam(id);
          } catch (_) {
            gradcamBytes = null; // El PDF se genera sin mapa de atención.
          }
        }
      }
      // Genera el PDF con el repositorio existente en el proyecto.
      // No invoca ningún endpoint del backend.
      final bytes = await const PdfReportRepository().buildPdf(
        result,
        imageBytes: imageBytes,
        gradcamBytes: gradcamBytes,
      );
      final rawName = result.displayName ?? 'analisis_nerilum';
      final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final filename =
          '${safeName.isEmpty ? 'analisis_nerilum' : safeName}.pdf';
      // En web, sharePdf abre el diálogo de descarga del navegador.
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _pdfError = 'No se pudo generar el PDF. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Volver',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const Expanded(
                        child: Text(
                          'Reporte',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  Divider(color: colors.border, height: 24),
                  Expanded(
                    child: WebViewStateBox(
                      status: _status,
                      loadingBuilder: (_) => ListView(
                        children: const [
                          SkeletonLine(width: 260, height: 16),
                          SizedBox(height: 20),
                          SkeletonBlock(height: 110, radius: 18),
                          SizedBox(height: 20),
                          SkeletonLine(height: 48, radius: 24),
                        ],
                      ),
                      onRetry: _load,
                      emptyTitle: 'Análisis no encontrado',
                      emptyHint: 'No hay datos para generar el reporte.',
                      errorMessage: _loadError ??
                          'No se pudo cargar el análisis para el reporte.',
                      content: _result == null
                          ? const SizedBox.shrink()
                          : _ReportContent(
                              result: _result!,
                              generating: _generating,
                              onDownload: _downloadPdf,
                              pdfError: _pdfError,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportContent extends StatelessWidget {
  const _ReportContent({
    required this.result,
    required this.generating,
    required this.onDownload,
    this.pdfError,
  });

  final AnalysisResult result;
  final bool generating;
  final VoidCallback onDownload;
  final String? pdfError;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    final d = result.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return ListView(
      children: [
        const Text(
          'Descarga el reporte PDF del análisis.',
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'El PDF se genera en este navegador usando el paquete pdf. '
          'No se envía ningún dato adicional al backend.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.displayName ?? 'Análisis sin nombre',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${two(d.day)}/${two(d.month)}/${d.year} · '
                '${two(d.hour)}:${two(d.minute)}',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                'Categoría del modelo: ${result.category}',
                style: TextStyle(color: colors.mintSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        if (pdfError != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.error_outline, color: colors.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pdfError!,
                  style: TextStyle(color: colors.error, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: generating ? null : onDownload,
          icon: generating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: NerilumColors.mintDarkText,
                  ),
                )
              : const Icon(Icons.download_outlined),
          label: Text(generating ? 'Generando PDF…' : 'Descargar PDF'),
        ),
      ],
    );
  }
}
