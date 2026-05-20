// ============================================================
// lib/services/supabase_service.dart
// Compatible dengan supabase_flutter: ^2.12.0
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models.dart';

// ─── Singleton client ─────────────────────────────────────
final supabase = Supabase.instance.client;

// ============================================================
// AUTH SERVICE
// ============================================================
class AuthService {
  /// Login dengan email + password
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Daftar akun baru
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    return await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  /// Logout
  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  static Session? get currentSession => supabase.auth.currentSession;
  static User?    get currentUser    => supabase.auth.currentUser;

  static Stream<AuthState> get authStateChanges =>
      supabase.auth.onAuthStateChange;
}


// ============================================================
// PRODUCT SERVICE
// ============================================================
class ProductService {
  /// Ambil semua produk aktif
  static Future<List<Product>> fetchAll() async {
    // v2.x: response langsung List<Map>, tidak perlu cast
    final response = await supabase
        .from('products')
        .select()
        .eq('is_active', true)
        .order('is_popular', ascending: false);

    return response.map((row) => Product.fromJson(row)).toList();
  }

  /// Filter berdasarkan kategori
  static Future<List<Product>> fetchByCategory(String category) async {
    final List<Map<String, dynamic>> response;

    if (category == 'Semua') {
      response = await supabase
          .from('products')
          .select()
          .eq('is_active', true)
          .order('is_popular', ascending: false);
    } else {
      response = await supabase
          .from('products')
          .select()
          .eq('is_active', true)
          .eq('category', category)
          .order('name');
    }

    return response.map((row) => Product.fromJson(row)).toList();
  }
}


// ============================================================
// ORDER SERVICE
// ============================================================
class OrderService {
  /// Buat pesanan baru (order + order_items)
  static Future<Order> createOrder({
    required List<CartItem> cartItems,
    required int subtotal,
    required int tax,
    required int total,
  }) async {
    final userId = AuthService.currentUser!.id;

    // 1. Insert order, langsung .select().single() → Map<String, dynamic>
    final orderRow = await supabase
        .from('orders')
        .insert({
          'user_id':  userId,
          'subtotal': subtotal,
          'tax':      tax,
          'total':    total,
          'status':   'Pesanan Diterima',
        })
        .select()
        .single();

    final orderId   = orderRow['id']          as String;
    final orderCode = orderRow['order_code']   as String;
    final queueNum  = orderRow['queue_number'] as int;

    // 2. Insert semua item sekaligus
    await supabase.from('order_items').insert(
      cartItems.map((item) => {
        'order_id':   orderId,
        'product_id': item.product.id,
        'quantity':   item.quantity,
        'unit_price': item.product.price,
        'milk_type':  item.milkType,
        'sweetness':  item.sweetness,
      }).toList(),
    );

    return Order(
      id:            orderCode,
      items:         cartItems,
      total:         total,
      timestamp:     DateTime.now(),
      status:        'Pesanan Diterima',
      estimatedTime: '5-7 Menit',
      queueNumber:   queueNum,
    );
  }

  /// Ambil riwayat pesanan user
  static Future<List<Map<String, dynamic>>> fetchHistory() async {
    final userId = AuthService.currentUser!.id;

    // v2.x: response sudah List<Map<String, dynamic>>
    final response = await supabase
        .from('orders')
        .select(
          'id, order_code, status, total, queue_number, created_at, '
          'order_items(quantity, unit_price, milk_type, sweetness, '
          'products(name, image_url))',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return response;
  }

  /// Subscribe realtime ke perubahan status pesanan
  /// Compatible supabase_flutter ^2.12.0:
  ///   - filter pakai PostgresChangeFilter(column, value) — tanpa FilterType
  static RealtimeChannel subscribeToOrder({
    required String orderId,
    required void Function(String newStatus) onStatusChange,
  }) {
    return supabase
        .channel('cofflow_order_$orderId')
        .onPostgresChanges(
          event:  PostgresChangeEvent.update,
          schema: 'public',
          table:  'orders',
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'id',
            value:  orderId,
          ),
          callback: (PostgresChangePayload payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus != null) onStatusChange(newStatus);
          },
        )
        .subscribe();
  }

  /// Berhenti subscribe (panggil saat order selesai / dispose)
  static Future<void> unsubscribeOrder(RealtimeChannel channel) async {
    await supabase.removeChannel(channel);
  }
}


// ============================================================
// PROFILE SERVICE
// ============================================================
class ProfileService {
  /// Ambil profil user yang sedang login
  /// v2.x: .single() langsung return Map<String, dynamic>
  static Future<Map<String, dynamic>> fetchProfile() async {
    final userId = AuthService.currentUser!.id;

    return await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
  }

  /// Update nama dan/atau avatar
  static Future<void> updateProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    final userId = AuthService.currentUser!.id;

    final updates = <String, dynamic>{};
    if (fullName  != null) updates['full_name']  = fullName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (updates.isEmpty) return;

    await supabase
        .from('profiles')
        .update(updates)
        .eq('id', userId);
  }

  /// Riwayat perolehan / penukaran poin
  static Future<List<Map<String, dynamic>>> fetchPointsLog() async {
    final userId = AuthService.currentUser!.id;

    return await supabase
        .from('points_log')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);
  }
}