/// Bubble-sheet capture screen: camera preview under the framing guide
/// overlay. Thin camera plumbing — the capture is cropped to the on-screen
/// guide and handed to GraderSession.processSheet, which owns OMR + grading.
library;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'framing.dart';
import 'session.dart';
import 'sheet_guide_overlay.dart';

class CaptureSheetScreen extends StatefulWidget {
  const CaptureSheetScreen({super.key, required this.session});

  final GraderSession session;

  @override
  State<CaptureSheetScreen> createState() => _CaptureSheetScreenState();
}

class _CaptureSheetScreenState extends State<CaptureSheetScreen> {
  CameraController? _camera;
  String? _initError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } on Exception catch (error) {
      if (mounted) setState(() => _initError = 'Camera unavailable: $error');
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await camera.takePicture();
      final bytes = await shot.readAsBytes();
      final photo = img.decodeImage(bytes);
      if (photo == null) {
        _showError('Could not decode the captured photo — try again.');
        return;
      }
      // Crop the same relative region the overlay showed. The guide is
      // computed against the photo's own dimensions, which assumes the
      // preview and the capture share an aspect ratio (true for the default
      // camera configurations; revisit if a mismatch shows up on a device).
      final photoSize = Size(photo.width.toDouble(), photo.height.toDouble());
      final guide = pageGuideRect(photoSize);
      final page = cropToGuideFraction(
        photo,
        guideAsFraction(guide, photoSize),
      );
      if (widget.session.processSheet(page)) {
        if (mounted) Navigator.of(context).pop(true);
      } else {
        _showError(widget.session.lastError ?? 'Detection failed — retake.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Capture the bubble sheet')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (camera != null)
            CameraPreview(camera)
          else
            Center(
              child: _initError == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_initError!, textAlign: TextAlign.center),
                    ),
            ),
          SheetGuideOverlay(hint: widget.session.lastError),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.large(
        onPressed: _busy ? null : _capture,
        child: _busy
            ? const CircularProgressIndicator()
            : const Icon(Icons.camera_alt),
      ),
    );
  }
}
