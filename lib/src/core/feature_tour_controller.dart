import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final featureTourControllerProvider =
    ChangeNotifierProvider.autoDispose<FeatureTourController>((ref) {
      return FeatureTourController()..load();
    });

class FeatureTourController extends ChangeNotifier {
  static const paths = [
    '/home',
    '/estimates',
    '/catalog',
    '/clients',
    '/settings',
  ];
  static const _keyPrefix = 'feature_tour_seen_v2';

  bool ready = false;
  int stepIndex = 0;
  String? _userId;
  final Set<int> _seenIndexes = {};
  bool _disposed = false;

  String get currentPath => paths[stepIndex.clamp(0, paths.length - 1)];

  bool shouldShow(int selectedIndex) {
    return ready &&
        _userId != null &&
        selectedIndex >= 0 &&
        selectedIndex < paths.length &&
        !_seenIndexes.contains(selectedIndex);
  }

  Future<void> load() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    _userId = userId;
    if (userId == null) {
      _setState(ready: true, stepIndex: 0);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _seenIndexes.clear();
    for (var i = 0; i < paths.length; i++) {
      if (prefs.getBool(_key(userId, i)) ?? false) {
        _seenIndexes.add(i);
      }
    }
    _setState(ready: true, stepIndex: 0);
  }

  Future<void> completeStep(int index) async {
    final userId = _userId;
    if (userId != null && index >= 0 && index < paths.length) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key(userId, index), true);
      _seenIndexes.add(index);
    }
    _setState(stepIndex: index);
  }

  Future<void> skip() async {
    final userId = _userId;
    if (userId != null) {
      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < paths.length; i++) {
        await prefs.setBool(_key(userId, i), true);
        _seenIndexes.add(i);
      }
    }
    _setState();
  }

  static String _key(String userId, int index) => '$_keyPrefix:$userId:$index';

  void _setState({bool? ready, int? stepIndex}) {
    if (_disposed) return;
    this.ready = ready ?? this.ready;
    this.stepIndex = stepIndex ?? this.stepIndex;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
