import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../services/ble_service.dart';
import '../services/on_device_vision_service.dart';
import '../services/scene_description_service.dart';
import '../services/vertex_ai_service.dart';

enum _DiagBackend {
  cloud('Cloud Gemini'),
  foundationModels('Apple Foundation Models'),
  moondream('Moondream CoreML'),
  smolVLM('SmolVLM llama.cpp'),
  visionTemplate('Vision-only template');

  const _DiagBackend(this.label);
  final String label;
}

class VisionDiagnosticScreen extends StatefulWidget {
  const VisionDiagnosticScreen({super.key});

  @override
  State<VisionDiagnosticScreen> createState() => _VisionDiagnosticScreenState();
}

class _VisionDiagnosticScreenState extends State<VisionDiagnosticScreen> {
  final ImagePicker _picker = ImagePicker();
  late final SceneDescriptionService _sceneService;

  Uint8List? _imageBytes;
  String _imageSource = '';
  _DiagBackend _selectedBackend = _DiagBackend.cloud;

  bool _isRunning = false;
  String _outputText = '';
  String _errorText = '';
  int? _timeToFirstTokenMs;
  int? _totalTimeMs;

  StreamSubscription<Uint8List>? _bleSub;
  Uint8List? _lastBleImage;

  @override
  void initState() {
    super.initState();
    final aiService = VertexAiService()..loadSavedModel();
    final onDeviceService = OnDeviceVisionService();
    _sceneService = SceneDescriptionService(
      cloudService: aiService,
      onDeviceService: onDeviceService,
    )..loadSavedMode();

    _bleSub = BleService.instance.imageStream.listen((bytes) {
      _lastBleImage = bytes;
    });
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = Uint8List.fromList(bytes);
      _imageSource = 'Gallery: ${file.name}';
      _clearResults();
    });
  }

  void _useLastBleImage() {
    if (_lastBleImage == null) return;
    setState(() {
      _imageBytes = _lastBleImage;
      _imageSource = 'Last BLE image (${_lastBleImage!.length} bytes)';
      _clearResults();
    });
  }

  void _clearResults() {
    _outputText = '';
    _errorText = '';
    _timeToFirstTokenMs = null;
    _totalTimeMs = null;
  }

  Future<void> _runDiagnostic() async {
    if (_imageBytes == null || _isRunning) return;

    setState(() {
      _isRunning = true;
      _clearResults();
    });

    const systemPrompt =
        'You are the vision system for a blind person wearing a chest camera. '
        'Describe the scene in 4–6 sentences. Be specific and spatial.';

    final stopwatch = Stopwatch()..start();
    bool gotFirstToken = false;
    final buffer = StringBuffer();

    try {
      final Stream<String> stream;
      switch (_selectedBackend) {
        case _DiagBackend.cloud:
          stream = _sceneService.describeWithGemini(
            _imageBytes!,
            systemPrompt: systemPrompt,
          );
        case _DiagBackend.foundationModels:
          stream = _sceneService.describeWithFoundationModels(
            _imageBytes!,
            systemPrompt: systemPrompt,
          );
        case _DiagBackend.moondream:
          stream = _sceneService.describeWithMoondream(_imageBytes!);
        case _DiagBackend.smolVLM:
          stream = _sceneService.describeWithSmolVLM(
            _imageBytes!,
            systemPrompt: systemPrompt,
          );
        case _DiagBackend.visionTemplate:
          stream = _sceneService.describeWithVisionTemplate(_imageBytes!);
      }

      await for (final chunk in stream) {
        if (!gotFirstToken) {
          gotFirstToken = true;
          setState(() {
            _timeToFirstTokenMs = stopwatch.elapsedMilliseconds;
          });
        }
        buffer.write(chunk);
        setState(() {
          _outputText = buffer.toString();
        });
      }
    } catch (e) {
      setState(() {
        _errorText = e.toString();
      });
    }

    stopwatch.stop();
    setState(() {
      _totalTimeMs = stopwatch.elapsedMilliseconds;
      _outputText = buffer.toString();
      if (_outputText.isEmpty && _errorText.isEmpty) {
        _errorText = 'Backend produced no output.';
      }
      _isRunning = false;
    });
  }

  void _copyResult() {
    final text = StringBuffer()
      ..writeln('Backend: ${_selectedBackend.label}')
      ..writeln('Image: $_imageSource')
      ..writeln('Time to first token: ${_timeToFirstTokenMs ?? "--"} ms')
      ..writeln('Total time: ${_totalTimeMs ?? "--"} ms')
      ..writeln()
      ..writeln(_outputText.isNotEmpty ? _outputText : '(no output)')
      ..writeln()
      ..writeln(_errorText.isNotEmpty ? 'Error: $_errorText' : '');

    Clipboard.setData(ClipboardData(text: text.toString().trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Vision Diagnostic',
          style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageSection(),
              const SizedBox(height: AppSpacing.md),
              _buildBackendSelector(),
              const SizedBox(height: AppSpacing.md),
              _buildRunButton(),
              const SizedBox(height: AppSpacing.md),
              _buildResultsSection(),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test Image',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textOnLight,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_imageBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _imageBytes!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 180,
                  color: AppColors.borderLight,
                  child: const Center(child: Text('Cannot preview image')),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _imageSource,
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondaryOnLight),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Row(
            children: [
              Expanded(
                child: _DiagButton(
                  label: 'Pick from Gallery',
                  onPressed: _isRunning ? null : _pickFromGallery,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _DiagButton(
                  label: 'Use Last BLE Image',
                  onPressed: (_lastBleImage == null || _isRunning)
                      ? null
                      : _useLastBleImage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackendSelector() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Backend',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textOnLight,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<_DiagBackend>(
            value: _selectedBackend,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
            ),
            items: _DiagBackend.values
                .map((b) => DropdownMenuItem(
                      value: b,
                      child: Text(
                        b.label,
                        style: TextStyle(fontSize: 16.sp),
                      ),
                    ))
                .toList(),
            onChanged: _isRunning
                ? null
                : (value) {
                    if (value != null) setState(() => _selectedBackend = value);
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildRunButton() {
    final canRun = _imageBytes != null && !_isRunning;
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: canRun ? _runDiagnostic : null,
        child: _isRunning
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textOnDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Running ${_selectedBackend.label}…'),
                ],
              )
            : const Text('Run Description'),
      ),
    );
  }

  Widget _buildResultsSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceCardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Results',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textOnLight,
                  ),
                ),
              ),
              if (_outputText.isNotEmpty || _errorText.isNotEmpty)
                _DiagButton(label: 'Copy Result', onPressed: _copyResult),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          _ResultRow(label: 'Backend', value: _selectedBackend.label),
          _ResultRow(
            label: 'First token',
            value: _timeToFirstTokenMs != null ? '${_timeToFirstTokenMs} ms' : '--',
          ),
          _ResultRow(
            label: 'Total time',
            value: _totalTimeMs != null ? '${_totalTimeMs} ms' : '--',
          ),

          const Divider(height: 24, color: AppColors.borderLight),

          if (_errorText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error),
              ),
              child: Text(
                _errorText,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.error,
                  height: 1.4,
                ),
              ),
            ),

          if (_outputText.isNotEmpty) ...[
            if (_errorText.isNotEmpty) const SizedBox(height: AppSpacing.xs),
            SelectableText(
              _outputText,
              style: TextStyle(
                fontSize: 16.sp,
                color: AppColors.textOnLight,
                height: 1.5,
              ),
            ),
          ],

          if (_outputText.isEmpty && _errorText.isEmpty)
            Text(
              'Run a backend to see results.',
              style: TextStyle(
                fontSize: 16.sp,
                color: AppColors.disabledOnLight,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textSecondaryOnLight,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textOnLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _DiagButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? AppColors.interactive : AppColors.borderLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: enabled ? AppColors.textOnDark : AppColors.disabledOnLight,
            ),
          ),
        ),
      ),
    );
  }
}
