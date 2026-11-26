import 'package:flutter/material.dart';

import 'stt_models.dart';

/// The text fields, model selector, error message and Save button at the top of the screen.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.serviceAccountController,
    required this.projectIdController,
    required this.languageController,
    required this.model,
    required this.onModelChanged,
    required this.onSave,
    this.errorMsg,
  });

  final TextEditingController serviceAccountController;
  final TextEditingController projectIdController;
  final TextEditingController languageController;
  final SttModel model;
  final ValueChanged<SttModel> onModelChanged;
  final VoidCallback onSave;
  final String? errorMsg;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(controller: serviceAccountController, decoration: const InputDecoration(hintText: 'Enter Service Account JSON')),
        TextField(controller: projectIdController, decoration: const InputDecoration(hintText: 'Enter Project Id')),
        TextField(
          controller: languageController,
          decoration: InputDecoration(
            labelText: 'Language codes (comma-separated)',
            hintText: 'no-NO,en-US',
            helperText: model.multiLanguage
                ? 'Several codes allowed, the API picks per utterance'
                : 'This model only uses the first code',
          ),
        ),
        Row(
          children: [
            const Text('Model  '),
            DropdownButton<String>(
              value: model.id,
              items: [for (final m in SttModel.all) DropdownMenuItem(value: m.id, child: Text(m.label))],
              onChanged: (id) {
                if (id != null) onModelChanged(SttModel.byId(id));
              },
            ),
            const Text('  (applies next start)', style: TextStyle(fontSize: 12)),
          ],
        ),
        if (errorMsg != null) Text(errorMsg!, style: const TextStyle(backgroundColor: Colors.red)),
        ElevatedButton(onPressed: onSave, child: const Text('Save')),
      ],
    );
  }
}
