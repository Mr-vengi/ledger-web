import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SubmitFeedbackPage extends StatefulWidget {
  const SubmitFeedbackPage({super.key});

  @override
  State<SubmitFeedbackPage> createState() => _SubmitFeedbackPageState();
}

class _SubmitFeedbackPageState extends State<SubmitFeedbackPage> {
  String _selectedCategory = 'General';
  bool _isSubmitting = false;

  final List<Map<String, dynamic>> _categories = [
    {'name': 'General', 'icon': Icons.chat},
    {'name': 'Bug Report', 'icon': Icons.bug_report},
    {'name': 'Feature Request', 'icon': Icons.lightbulb_outline},
    {'name': 'Improvement', 'icon': Icons.trending_up},
    {'name': 'Complaint', 'icon': Icons.warning_amber},
    {'name': 'Appreciation', 'icon': Icons.favorite},
  ];

  /// Show dialog to submit feedback
  Future<void> _showFeedbackDialog() async {
    final TextEditingController feedbackController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Submit Feedback'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category Selection
              Text(
                'Category: $_selectedCategory',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),

              // Feedback Input
              TextField(
                controller: feedbackController,
                maxLines: 6,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'Share your thoughts, suggestions, or issues...',
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (feedbackController.text.trim().isEmpty) {
                _showSnackBar('Please enter your feedback', isError: true);
                return;
              }
              if (feedbackController.text.trim().length < 10) {
                _showSnackBar(
                  'Feedback must be at least 10 characters',
                  isError: true,
                );
                return;
              }

              Navigator.pop(context, true);

              setState(() => _isSubmitting = true);

              try {
                await FirebaseFirestore.instance.collection('feedbacks').add({
                  'feedback': feedbackController.text.trim(),
                  'category': _selectedCategory,
                  'submittedAt': FieldValue.serverTimestamp(),
                  'status': 'pending',
                });

                _showSnackBar('Feedback submitted successfully!');
              } catch (e) {
                debugPrint('Error submitting feedback: $e');
                _showSnackBar('Failed to submit feedback', isError: true);
              } finally {
                setState(() => _isSubmitting = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text(
          'Submit Feedback',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: ListView(
        children: [
          // Category Selection Header
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Select Category',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

          // Category Options
          ...List.generate(_categories.length, (index) {
            final category = _categories[index];
            final isSelected = _selectedCategory == category['name'];

            return Column(
              children: [
                RadioListTile<String>(
                  value: category['name'],
                  groupValue: _selectedCategory,
                  onChanged: (value) {
                    setState(() => _selectedCategory = value!);
                  },
                  activeColor: const Color(0xFF4285F4),
                  title: Text(category['name']),
                  secondary: Icon(
                    category['icon'],
                    color: isSelected
                        ? const Color(0xFF4285F4)
                        : Colors.grey[400],
                  ),
                ),
                if (index < _categories.length - 1) const Divider(height: 1),
              ],
            );
          }),

          const Divider(height: 1),

          // Submit Feedback Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _showFeedbackDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSubmitting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Submitting...'),
                      ],
                    )
                  : const Text(
                      'Write Feedback',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),

          // Info Cards
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Text(
                        'Feedback Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Your feedback is anonymous\n'
                    '• We review all feedback carefully\n'
                    '• Typical response: 2-3 business days\n'
                    '• Help us improve our service\n'
                    '• Minimum 10 characters required',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[900],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
