import 'package:flutter/material.dart';

import 'exam_api.dart';

Future<bool> showApiLoginDialog(
  BuildContext context,
  ExamApiClient api, {
  required String title,
}) async {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  var isLoading = false;
  var errorMessage = '';

  final authenticated = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.lock_outline, color: Color(0xFF6956D9)),
        title: Text(title),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                enabled: !isLoading,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Tên đăng nhập hoặc email',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                enabled: !isLoading,
                obscureText: true,
                onSubmitted: (_) async {
                  if (!isLoading) {
                    setDialogState(() {
                      isLoading = true;
                      errorMessage = '';
                    });
                    try {
                      await api.authenticate(
                        usernameController.text.trim(),
                        passwordController.text,
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    } on ExamApiException catch (error) {
                      setDialogState(() {
                        isLoading = false;
                        errorMessage = error.message;
                      });
                    }
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
              ),
              if (errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    errorMessage,
                    style: const TextStyle(
                      color: Color(0xFFC45B5B),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isLoading
                ? null
                : () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: isLoading
                ? null
                : () async {
                    setDialogState(() {
                      isLoading = true;
                      errorMessage = '';
                    });
                    try {
                      await api.authenticate(
                        usernameController.text.trim(),
                        passwordController.text,
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    } on ExamApiException catch (error) {
                      setDialogState(() {
                        isLoading = false;
                        errorMessage = error.message;
                      });
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6956D9),
            ),
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Đăng nhập'),
          ),
        ],
      ),
    ),
  );
  usernameController.dispose();
  passwordController.dispose();
  return authenticated == true;
}
