import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../shared/ui.dart';

class ConfigRequiredScreen extends StatelessWidget {
  const ConfigRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ScreenPadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.engineering, color: AppColors.orange, size: 34),
              ),
              const SizedBox(height: 22),
              Text(
                'Сметчик',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Для запуска MVP нужно передать Supabase URL и anon key через dart-define.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              const SmetchikCard(
                child: SelectableText(
                  'flutter run -d chrome '
                  '--dart-define=SUPABASE_URL=https://PROJECT.supabase.co '
                  '--dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY',
                  style: TextStyle(fontFamily: 'monospace', height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Для release-сборок используйте те же параметры с flutter build web или flutter build appbundle.',
                style: TextStyle(color: AppColors.textHint, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
