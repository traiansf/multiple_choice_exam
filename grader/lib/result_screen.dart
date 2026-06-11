/// Result screen: either the score with a per-question breakdown, or the
/// manual-review notice when OMR flagged rows. Pure UI over GraderSession.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'session.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.session});

  final GraderSession session;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  /// The buttons stay tappable during the pop animation; this guard makes a
  /// second tap a no-op instead of acting on the already-advanced session.
  bool _submitted = false;

  /// Roster name the grader read off the paper (issue #8).
  String? _student;

  @override
  void initState() {
    super.initState();
    final payload = widget.session.qrPayload;
    if (payload != null) {
      _student = widget.session.gradeBook
          .recordFor(payload.variantId)
          ?.studentName;
    }
  }

  void _finish(VoidCallback action, String popValue) {
    if (_submitted) return;
    _submitted = true;
    action();
    Navigator.of(context).pop(popValue);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final omr = session.omrResult;
    final grade = session.gradeResult;
    final needsReview = omr?.needsReview ?? false;
    assert(
      needsReview || grade != null,
      'ResultScreen pushed while the session has no result',
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: needsReview
          ? _ReviewNotice(
              rows: omr!.reviewRows,
              total: omr.rows.length,
              scanPng: session.scannedSheetPng,
              onSubmit: (score) => _finish(() {
                session.submitManualGrade(score, studentName: _student);
                session.nextSheet();
              }, 'next'),
            )
          : _GradeView(session: session),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.roster.isNotEmpty) ...[
              Builder(
                builder: (context) {
                  final available = session.unassignedStudents;
                  return DropdownButtonFormField<String?>(
                    initialValue: _student,
                    decoration: const InputDecoration(
                      labelText: 'Student (from the name on the paper)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— no student —'),
                      ),
                      // An assignment recorded under an older roster stays
                      // selectable; otherwise initialValue would not be
                      // among the items (a debug assertion failure).
                      if (_student != null && !available.contains(_student))
                        DropdownMenuItem<String?>(
                          value: _student,
                          child: Text(_student!),
                        ),
                      for (final name in available)
                        DropdownMenuItem<String?>(
                          value: name,
                          child: Text(name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _student = value),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Retake sheet'),
                    onPressed: () => _finish(session.retakeSheet, 'retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: needsReview
                      ? FilledButton.icon(
                          icon: const Icon(Icons.qr_code_scanner),
                          // Explicit: skipping records nothing — neither a
                          // grade nor the picked student.
                          label: const Text('Skip — no grade'),
                          onPressed: () => _finish(session.nextSheet, 'next'),
                        )
                      : FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Confirm — next sheet'),
                          onPressed: () => _finish(() {
                            session.confirmResult(studentName: _student);
                            session.nextSheet();
                          }, 'next'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewNotice extends StatefulWidget {
  const _ReviewNotice({
    required this.rows,
    required this.total,
    required this.scanPng,
    required this.onSubmit,
  });

  final List<int> rows;
  final int total;

  /// The scanned page with the flagged rows outlined, so the grader can see
  /// what the camera saw while grading by hand.
  final Uint8List? scanPng;
  final void Function(int score) onSubmit;

  @override
  State<_ReviewNotice> createState() => _ReviewNoticeState();
}

class _ReviewNoticeState extends State<_ReviewNotice> {
  final TextEditingController _score = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _score.dispose();
    super.dispose();
  }

  void _submit() {
    final score = int.tryParse(_score.text.trim());
    if (score == null || score < 0 || score > widget.total) {
      setState(() => _error = 'Enter a score between 0 and ${widget.total}.');
      return;
    }
    widget.onSubmit(score);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 32),
              const SizedBox(width: 8),
              Text(
                'Manual review needed',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Question row${widget.rows.length == 1 ? '' : 's'}'
            ' ${widget.rows.join(', ')} could not be read confidently'
            ' (multiple or faint marks). Retake the photo, or inspect the'
            ' sheet and grade it by hand below.',
          ),
          if (widget.scanPng != null) ...[
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Image.memory(widget.scanPng!, fit: BoxFit.contain),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _score,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Score / ${widget.total}',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Submit manual grade'),
                onPressed: _submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabeledSheet extends StatelessWidget {
  const _LabeledSheet({required this.label, required this.png});

  final String label;
  final Uint8List png;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        // Both images are full-page renders with the same A4 aspect, so
        // equal-width columns show them scaled to match.
        Expanded(child: Image.memory(png, fit: BoxFit.contain)),
      ],
    );
  }
}

class _GradeView extends StatelessWidget {
  const _GradeView({required this.session});

  final GraderSession session;

  @override
  Widget build(BuildContext context) {
    final grade = session.gradeResult!;
    final payload = session.qrPayload!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                '${grade.score} / ${grade.total}',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              Text(
                '${session.answerKey!.examTitle} — variant'
                ' ${payload.variantId.toString().padLeft(3, '0')}',
              ),
            ],
          ),
        ),
        if (session.referenceSheetPng != null &&
            session.scannedSheetPng != null)
          SizedBox(
            height: 260,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _LabeledSheet(
                      label: 'Correct answers',
                      png: session.referenceSheetPng!,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LabeledSheet(
                      label: 'Scanned sheet',
                      png: session.scannedSheetPng!,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: grade.perQuestion.length,
            itemBuilder: (context, index) {
              final question = grade.perQuestion[index];
              final marked = question.markedPosition;
              const letters = 'ABCDEFGHIJ';
              return ListTile(
                dense: true,
                leading: Icon(
                  question.correct ? Icons.check_circle : Icons.cancel,
                  color: question.correct ? Colors.green : Colors.red,
                ),
                title: Text(
                  'Question ${question.sheetNumber}'
                  ' (${question.section})',
                ),
                trailing: Text(
                  marked == null
                      ? 'blank — correct: ${letters[question.correctPosition]}'
                      : question.correct
                      ? letters[marked]
                      : '${letters[marked]} — correct:'
                            ' ${letters[question.correctPosition]}',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
