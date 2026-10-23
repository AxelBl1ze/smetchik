import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_data_cache.dart';
import 'repository.dart';
import 'room_calculator.dart';

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  final userId = ref.watch(activeUserIdProvider);
  if (userId == null) throw Exception('Войдите в аккаунт ещё раз.');
  return RoomRepository(Supabase.instance.client, userId);
});

final projectRoomsProvider = FutureProvider.autoDispose
    .family<List<ProjectRoom>, String>((ref, id) {
      return ref.watch(roomRepositoryProvider).fetch(id);
    });

class RoomRepository {
  RoomRepository(this.client, this.userId);
  final SupabaseClient client;
  final String userId;
  final _cache = const LocalDataCache();
  String _key(String projectId) => 'rooms.$userId.$projectId';
  void _checkUser() {
    if (client.auth.currentUser?.id != userId) {
      throw Exception('Аккаунт изменился. Откройте объект ещё раз.');
    }
  }

  Future<List<ProjectRoom>> fetch(String projectId) async {
    _checkUser();
    try {
      final rows = await client
          .from('project_rooms')
          .select()
          .eq('project_id', projectId)
          .eq('user_id', userId)
          .order('created_at');
      _checkUser();
      final rooms = rows.map(ProjectRoom.fromRow).toList();
      await _cache.write(_key(projectId), rows);
      return rooms;
    } catch (error) {
      _checkUser();
      final message = error.toString().toLowerCase();
      if (![
        'socket',
        'network',
        'clientexception',
        'timeout',
        'connection',
      ].any(message.contains)) {
        rethrow;
      }
      final cached = await _cache.readList(_key(projectId));
      if (cached == null) rethrow;
      return cached.map(ProjectRoom.fromRow).toList();
    }
  }

  Future<ProjectRoom> save(String projectId, ProjectRoom room) async {
    _checkUser();
    RoomGeometry(room).validate();
    for (final finish in room.finishes) {
      RoomCalculator.calculate(room, finish);
    }
    final payload = {
      'id': room.id,
      'user_id': userId,
      'project_id': projectId,
      'data': room.toMap(),
    };
    Map<String, dynamic>? row;
    if (room.revision == 0) {
      row = await client
          .from('project_rooms')
          .insert(payload)
          .select()
          .single();
    } else {
      row = await client
          .from('project_rooms')
          .update({'data': room.toMap()})
          .eq('id', room.id)
          .eq('user_id', userId)
          .eq('project_id', projectId)
          .eq('revision', room.revision)
          .select()
          .maybeSingle();
    }
    _checkUser();
    if (row == null) {
      throw Exception(
        'Помещение изменено на другом устройстве или удалено. '
        'Ваши правки остались на экране. Вернитесь к списку и обновите данные.',
      );
    }
    final cached = await _cache.readList(_key(projectId)) ?? [];
    cached.removeWhere((item) => item['id'] == room.id);
    cached.add(row);
    await _cache.write(_key(projectId), cached);
    return ProjectRoom.fromRow(row);
  }

  Future<void> delete(String projectId, ProjectRoom room) async {
    _checkUser();
    final deleted = await client
        .from('project_rooms')
        .delete()
        .eq('id', room.id)
        .eq('user_id', userId)
        .eq('project_id', projectId)
        .eq('revision', room.revision)
        .select('id');
    _checkUser();
    if (deleted.isEmpty) {
      throw Exception(
        'Помещение уже изменено. Обновите список перед удалением.',
      );
    }
    final cached = await _cache.readList(_key(projectId)) ?? [];
    cached.removeWhere((item) => item['id'] == room.id);
    await _cache.write(_key(projectId), cached);
  }
}
