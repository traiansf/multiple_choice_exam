import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'capture_sheet_screen.dart';
import 'result_screen.dart';
import 'scan_qr_screen.dart';
import 'session.dart';

void main() => runApp(GraderApp(session: GraderSession()));

class GraderApp extends StatelessWidget {
  const GraderApp({super.key, required this.session});

  final GraderSession session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MC Exam Grader',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: HomeScreen(session: session),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final GraderSession session;

  Future<void> _loadKey(BuildContext context) async {
    if (session.stage != SessionStage.needKey) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace the answer key?'),
          content: const Text(
            'Loading a new key starts a new exam: the current QR and sheet'
            ' state will be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }
    const typeGroup = XTypeGroup(label: 'answer key', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final text = utf8.decode(await file.readAsBytes());
    if (!session.loadKey(text) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid key file: ${session.lastError}')),
      );
    }
  }

  Future<void> _gradeFlow(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (session.stage == SessionStage.needQr) {
      final scanned = await navigator.push<bool>(
        MaterialPageRoute(builder: (_) => ScanQrScreen(session: session)),
      );
      if (scanned != true) return;
    }
    // The loop also accepts an entry directly in the result stage: if the
    // user back-navigated out of the result screen earlier, the session is
    // still showing that result and tapping "Grade a sheet" returns to it.
    while (session.stage == SessionStage.needSheet ||
        session.stage == SessionStage.result) {
      if (session.stage == SessionStage.needSheet) {
        final captured = await navigator.push<bool>(
          MaterialPageRoute(
            builder: (_) => CaptureSheetScreen(session: session),
          ),
        );
        if (captured != true) return;
      }
      final action = await navigator.push<String>(
        MaterialPageRoute(builder: (_) => ResultScreen(session: session)),
      );
      if (action != 'retake') return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MC Exam Grader')),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final key = session.answerKey;
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: key == null
                        ? const Text(
                            'No answer key loaded.\n\nStart by loading the'
                            ' answer-key.json produced by mcexam generate.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                key.examTitle,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'easy ${key.sections['easy']},'
                                ' medium ${key.sections['medium']},'
                                ' hard ${key.sections['hard']}'
                                ' — ${key.optionsPerQuestion} options per'
                                ' question',
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(
                    key == null ? 'Load answer key' : 'Load a different key',
                  ),
                  onPressed: () => _loadKey(context),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Grade a sheet'),
                  onPressed: key == null ? null : () => _gradeFlow(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
