import 'package:flutter/material.dart';

void main() => runApp(const GraderApp());

class GraderApp extends StatelessWidget {
  const GraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MC Exam Grader',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MC Exam Grader')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Workflow', style: TextStyle(fontSize: 20)),
            SizedBox(height: 12),
            Text('1. Load answer-key.json for the exam'),
            Text('2. Scan the QR code on a student sheet'),
            Text('3. Scan the bubble sheet'),
            Text('4. Review the score and per-question breakdown'),
            SizedBox(height: 24),
            Text(
              'The grading engine is implemented and tested; QR camera'
              ' scanning and OMR sheet detection arrive in the next'
              ' milestone.',
            ),
          ],
        ),
      ),
    );
  }
}
