/// Recorded grades of the current exam: a per-variant list and the CSV
/// report export (share sheet). Pure UI over GraderSession.gradeBook.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'session.dart';

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key, required this.session});

  final GraderSession session;

  Future<void> _export() async {
    final csv = session.gradeBook.toCsv();
    final title = session.answerKey?.examTitle ?? 'exam';
    final filename = '$title - grades.csv';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(csv)),
            mimeType: 'text/csv',
            name: filename,
          ),
        ],
        // XFile.fromData's name is ignored on most platforms; this isn't.
        fileNameOverrides: [filename],
        subject: '$title — grade report',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recorded grades')),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final records = session.gradeBook.records;
          if (records.isEmpty) {
            return const Center(child: Text('No grades recorded yet.'));
          }
          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return ListTile(
                dense: true,
                leading: Icon(
                  record.manual ? Icons.edit : Icons.assignment_turned_in,
                ),
                title: Text(
                  'Variant ${record.variantId.toString().padLeft(3, '0')}',
                ),
                subtitle: switch ((record.studentName, record.manual)) {
                  (null, false) => null,
                  (null, true) => const Text('graded manually'),
                  (final name?, false) => Text(name),
                  (final name?, true) => Text('$name — graded manually'),
                },
                trailing: Text(
                  '${record.score} / ${record.total}'
                  '  (${record.percent.toStringAsFixed(1)}%)',
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton.icon(
          icon: const Icon(Icons.ios_share),
          label: const Text('Export report (CSV)'),
          onPressed: session.gradeBook.isEmpty ? null : _export,
        ),
      ),
    );
  }
}
