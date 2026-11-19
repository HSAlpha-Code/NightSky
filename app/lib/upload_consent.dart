import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/legal_screen.dart';

/// Consent lasts for this app session and applies only to the receiving server.
class UploadConsent {
  String? _server;

  bool covers(String server) => _server == server;
  void accept(String server) => _server = server;
  void revoke() => _server = null;
}

final uploadConsentProvider = Provider<UploadConsent>((ref) => UploadConsent());

Future<bool> requestUploadConsent(BuildContext context, String server) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send your photo to identify the sky?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Camera mode sends your sky photo, capture time, phone orientation, '
                'camera field of view, and location (latitude, longitude and altitude, '
                'when location permission is granted) to:\n\n$server\n\n'
                'The server processes these to identify the sky and fetch survey images. '
                'Your IP address is also visible to the server and its hosting provider. '
                'If auto-capture is enabled, each capture sends this data. '
                'Avoid photographing people or private information. '
                'You can cancel and use Sky View without uploading a photo.',
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LegalScreen(
                      title: 'Privacy policy',
                      asset: 'assets/legal/privacy.txt',
                    ),
                  ),
                ),
                child: const Text('Read privacy policy'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Agree and continue'),
          ),
        ],
      ),
    ) ??
    false;
