/// Recorded grades of the current exam: a per-variant list and the CSV
/// report export (share sheet). Pure UI over GraderSession.gradeBook.
library;

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
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(csv.codeUnits),
            mimeType: 'text/csv',
            name: '$title - grades.csv',
          ),
        ],
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
                leading: const Icon(Icons.assignment_turned_in),
                title: Text(
                  'Variant ${record.variantId.toString().padLeft(3, '0')}',
                ),
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
