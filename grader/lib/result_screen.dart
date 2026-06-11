/// Result screen: either the score with a per-question breakdown, or the
/// manual-review notice when OMR flagged rows. Pure UI over GraderSession.
library;

import 'package:flutter/material.dart';

import 'session.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.session});

  final GraderSession session;

  @override
  Widget build(BuildContext context) {
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
          ? _ReviewNotice(rows: omr!.reviewRows)
          : _GradeView(session: session),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (needsReview || grade != null)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Retake sheet'),
                  onPressed: () {
                    session.retakeSheet();
                    Navigator.of(context).pop('retake');
                  },
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Next sheet'),
                onPressed: () {
                  session.nextSheet();
                  Navigator.of(context).pop('next');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.rows});

  final List<int> rows;

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
            'Question row${rows.length == 1 ? '' : 's'} ${rows.join(', ')}'
            ' could not be read confidently (multiple or faint marks).'
            ' Retake the photo, or grade this sheet by hand.',
          ),
        ],
      ),
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
