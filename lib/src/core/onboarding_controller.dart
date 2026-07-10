import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final onboardingControllerProvider =
    ChangeNotifierProvider<OnboardingController>((ref) {
      return OnboardingController()..load();
    });

class OnboardingController extends ChangeNotifier {
  static const _key = 'onboarding_seen_v1';

  bool ready = false;
  bool seen = false;
  bool _disposed = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    seen = prefs.getBool(_key) ?? false;
    ready = true;
    notifyListeners();
  }

  Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
    if (_disposed) return;
    seen = true;
    ready = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
