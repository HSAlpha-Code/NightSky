import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bundled documents remain available without a network connection.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.asset});

  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FutureBuilder<String>(
      future: rootBundle.loadString(asset),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('This document could not be loaded.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final urls = RegExp(
          r'https://[^\s]+',
        ).allMatches(snapshot.data!).map((m) => m.group(0)!).toSet();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectionArea(child: Text(snapshot.data!)),
              if (urls.isNotEmpty) ...[
                const Divider(height: 32),
                const Text('Referenced sources and licences'),
                for (final url in urls)
                  TextButton(
                    onPressed: () async {
                      final opened = await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                      if (!opened && context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('Could not open this link.')));
                      }
                    },
                    child: Text(url),
                  ),
              ],
            ],
          ),
        );
      },
    ),
  );
}
