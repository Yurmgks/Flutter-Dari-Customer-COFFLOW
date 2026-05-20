// ============================================================
// lib/main.dart  — Cofflow + Supabase Integration
// Perubahan dari versi mock:
//   1. Inisialisasi Supabase di main()
//   2. LoginScreen memakai AuthService
//   3. HomeScreen fetch produk dari DB
//   4. CartScreen buat order ke Supabase
//   5. OrdersScreen pakai Realtime subscription
//   6. ProfileScreen fetch data profil dari DB
// ============================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import 'models.dart';
import 'services/supabase_service.dart';

// ─── GANTI DUA NILAI INI ──────────────────────────────────
const kSupabaseUrl    = 'https://fhvsavmubvgsrqqijhvq.supabase.co';
const kSupabaseAnonKey = 'sb_publishable_jNM9EmfBOdrNxJ9nR2gkJg_OlM5BGYZ';
// ──────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url:    kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
  );

  runApp(const CofflowApp());
}

class CofflowApp extends StatelessWidget {
  const CofflowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cofflow.',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7F5),
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: kBrandDark,
          primary:   kBrandDark,
          secondary: kBrandAccent,
        ),
      ),
      // Cek session: jika sudah login, langsung ke Home
      home: AuthService.currentSession != null
          ? MainNavigation(key: AppState.navKey)
          : const SplashScreen(),
    );
  }
}

// --- Brand Colors ---
const kBrandDark   = Color(0xFF1C2C22);
const kBrandAccent = Color(0xFFD4AF37);
const kBrandLight  = Color(0xFFF7F7F5);
const kBrandMuted  = Color(0xFFEEEEEB);

// ─────────────────────────────────────────────────────────
// GLOBAL STATE  (cart tetap di memori; order dari Supabase)
// ─────────────────────────────────────────────────────────
class AppState {
  static final GlobalKey<_MainNavigationState> navKey =
      GlobalKey<_MainNavigationState>();

  static List<CartItem>  cart         = [];
  static Order?          currentOrder;
  static List<Map<String, dynamic>> history = [];

  // Realtime channel handle
  static RealtimeChannel? _orderChannel;

  static void changeTab(int i) => navKey.currentState?.updateIndex(i);
  static void refreshUI()      => navKey.currentState?.refresh();

  static void addToCart(CartItem newItem) {
    int index = cart.indexWhere((i) => i.uniqueId == newItem.uniqueId);
    if (index != -1) {
      cart[index].quantity += newItem.quantity;
    } else {
      cart.add(newItem);
    }
    changeTab(2);
  }

  // ── Buat pesanan ke Supabase ──────────────────────────
  static Future<void> placeOrder(BuildContext context) async {
    int subtotal = cart.fold(0, (s, i) => s + i.product.price * i.quantity);
    int tax      = (subtotal * 0.1).toInt();
    int total    = subtotal + tax;

    try {
      final order = await OrderService.createOrder(
        cartItems: List.from(cart),
        subtotal:  subtotal,
        tax:       tax,
        total:     total,
      );

      currentOrder = order;
      cart = [];
      changeTab(1); // Tab Pesanan

      // Mulai realtime listener untuk status pesanan
      _listenToOrder(context, order.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat pesanan: $e')),
        );
      }
    }
  }

  // ── Realtime: update status pesanan otomatis ──────────
  static void _listenToOrder(BuildContext context, String orderCode) {
    // Supabase realtime subscribe ke baris yg matching order_code
    // (orderId di sini adalah order_code dari DB, bukan UUID)
    _orderChannel = supabase
        .channel('cofflow_order_$orderCode')
        .onPostgresChanges(
          event:  PostgresChangeEvent.update,
          schema: 'public',
          table:  'orders',
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus != null && currentOrder != null) {
              currentOrder = Order(
                id:            currentOrder!.id,
                items:         currentOrder!.items,
                total:         currentOrder!.total,
                timestamp:     currentOrder!.timestamp,
                status:        newStatus,
                estimatedTime: currentOrder!.estimatedTime,
                queueNumber:   currentOrder!.queueNumber,
              );
              refreshUI();

              if (newStatus == 'Selesai') {
                _orderChannel?.unsubscribe();
                _showDoneDialog(context);
              }
            }
          },
        )
        .subscribe();
  }

  static void _showDoneDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Sukses!', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Pesanan kamu sudah selesai. Terima kasih!'),
        actions: [
          TextButton(
            onPressed: () {
              currentOrder = null;
              refreshUI();
              Navigator.pop(ctx);
            },
            child: const Text('TUTUP',
              style: TextStyle(color: kBrandDark, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// SPLASH SCREEN  (tidak berubah)
// ─────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _controller.forward();

    Timer(const Duration(milliseconds: 2500), () {
      Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    });
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBrandDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kBrandAccent, borderRadius: BorderRadius.circular(32)),
                child: const Icon(LucideIcons.coffee, color: kBrandDark, size: 48),
              ),
            ),
            const SizedBox(height: 24),
            Text('Cofflow.',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white, fontSize: 40,
                fontWeight: FontWeight.bold, letterSpacing: -2)),
            const SizedBox(height: 8),
            const Text('Pengalaman Kopi Berkelas',
              style: TextStyle(color: kBrandAccent, fontSize: 10,
                fontWeight: FontWeight.bold, letterSpacing: 4)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// LOGIN SCREEN  — pakai AuthService
// ─────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.signIn(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (mounted) {
        Navigator.pushReplacement(context,
          MaterialPageRoute(
            builder: (_) => MainNavigation(key: AppState.navKey)));
      }
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned(top: -100, right: -100, child: _blob(kBrandAccent.withOpacity(0.05))),
        Positioned(bottom: -100, left: -100, child: _blob(kBrandDark.withOpacity(0.05))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kBrandDark, borderRadius: BorderRadius.circular(28)),
              child: const Icon(LucideIcons.coffee, color: kBrandAccent, size: 40),
            ),
            const SizedBox(height: 24),
            Text('Cofflow.',
              style: GoogleFonts.plusJakartaSans(
                color: kBrandDark, fontSize: 36,
                fontWeight: FontWeight.bold, letterSpacing: -1.5)),
            const SizedBox(height: 48),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: _inputDecoration('EMAIL'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: _inputDecoration('KATA SANDI'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandDark, foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('MASUK KE FLOW',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            ),
            const SizedBox(height: 16),
            // ── Tombol ke Register ──
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Belum punya akun?',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
              TextButton(
                onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text('DAFTAR',
                  style: TextStyle(
                    color: kBrandDark, fontSize: 12,
                    fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ]),
            const SizedBox(height: 8),
            const Text('DIRACIK SEJAK 2024',
              style: TextStyle(color: Colors.grey, fontSize: 9,
                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _blob(Color color) => Container(
    width: 300, height: 300,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
      color: Colors.grey, letterSpacing: 1.5),
    filled: true, fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
  );
}

// ─────────────────────────────────────────────────────────
// REGISTER SCREEN
// ─────────────────────────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();
  bool _loading  = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    // Validasi lokal
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Nama lengkap tidak boleh kosong');
      return;
    }
    if (!_emailCtrl.text.contains('@')) {
      setState(() => _error = 'Format email tidak valid');
      return;
    }
    if (_passwordCtrl.text.length < 6) {
      setState(() => _error = 'Password minimal 6 karakter');
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Password dan konfirmasi tidak cocok');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      await AuthService.signUp(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        fullName: _nameCtrl.text.trim(),
      );

      if (mounted) {
        // Tampilkan dialog sukses lalu kembali ke Login
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            icon: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kBrandAccent.withOpacity(0.1),
                shape: BoxShape.circle),
              child: const Icon(LucideIcons.checkCircle2,
                color: kBrandAccent, size: 32)),
            title: const Text('Akun Berhasil Dibuat!',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: Text(
              'Selamat datang, ${_nameCtrl.text.trim()}!\nSilakan login dengan akun barumu.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);          // tutup dialog
                    Navigator.pop(context);      // kembali ke LoginScreen
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandDark, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
                  child: const Text('MASUK SEKARANG',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned(top: -80, right: -80,
          child: Container(width: 250, height: 250,
            decoration: BoxDecoration(
              color: kBrandAccent.withOpacity(0.05), shape: BoxShape.circle))),
        Positioned(bottom: -80, left: -80,
          child: Container(width: 250, height: 250,
            decoration: BoxDecoration(
              color: kBrandDark.withOpacity(0.05), shape: BoxShape.circle))),

        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 16),
              // Tombol back
              IconButton(
                icon: const Icon(LucideIcons.chevronLeft, color: kBrandDark),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero),
              const SizedBox(height: 24),
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kBrandDark, borderRadius: BorderRadius.circular(20)),
                child: const Icon(LucideIcons.coffee, color: kBrandAccent, size: 32)),
              const SizedBox(height: 20),
              Text('Buat Akun Baru',
                style: GoogleFonts.plusJakartaSans(
                  color: kBrandDark, fontSize: 30,
                  fontWeight: FontWeight.bold, letterSpacing: -1.5)),
              const Text('Bergabung dan nikmati kopi terbaik',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 36),

              // Nama Lengkap
              _label('NAMA LENGKAP'),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration('Contoh: Aris Setiawan',
                  icon: LucideIcons.user)),
              const SizedBox(height: 20),

              // Email
              _label('EMAIL'),
              const SizedBox(height: 8),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration('Contoh: aris@email.com',
                  icon: LucideIcons.mail)),
              const SizedBox(height: 20),

              // Password
              _label('KATA SANDI'),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure1,
                decoration: _inputDecoration('Minimal 6 karakter',
                  icon: LucideIcons.lock,
                  suffix: IconButton(
                    icon: Icon(_obscure1 ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 18, color: Colors.grey),
                    onPressed: () => setState(() => _obscure1 = !_obscure1)))),
              const SizedBox(height: 20),

              // Konfirmasi Password
              _label('KONFIRMASI KATA SANDI'),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscure2,
                decoration: _inputDecoration('Ulangi kata sandi',
                  icon: LucideIcons.lock,
                  suffix: IconButton(
                    icon: Icon(_obscure2 ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 18, color: Colors.grey),
                    onPressed: () => setState(() => _obscure2 = !_obscure2)))),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100)),
                  child: Row(children: [
                    Icon(LucideIcons.alertCircle, color: Colors.red.shade400, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade600, fontSize: 12))),
                  ])),
              ],

              const SizedBox(height: 32),
              // Tombol Daftar
              ElevatedButton(
                onPressed: _loading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBrandDark, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
                child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('BUAT AKUN',
                      style: TextStyle(fontWeight: FontWeight.bold,
                        letterSpacing: 2, fontSize: 12)),
              ),
              const SizedBox(height: 16),
              // Link ke Login
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Sudah punya akun?',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('MASUK',
                    style: TextStyle(color: kBrandDark, fontSize: 12,
                      fontWeight: FontWeight.bold, letterSpacing: 1))),
              ]),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _label(String text) => Text(text,
    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
      color: Colors.grey, letterSpacing: 1.5));

  InputDecoration _inputDecoration(String hint,
      {required IconData icon, Widget? suffix}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: Colors.grey),
      suffixIcon: suffix,
      filled: true, fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
}

// ─────────────────────────────────────────────────────────
// MAIN NAVIGATION  (tidak berubah)
// ─────────────────────────────────────────────────────────
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  void updateIndex(int i) => setState(() => _currentIndex = i);
  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final screens = [
      const HomeScreen(),
      const OrdersScreen(),
      const CartScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: Container(
        height: 90,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF1F1F1)))),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: updateIndex,
          elevation: 0,
          backgroundColor: Colors.transparent,
          selectedItemColor:   kBrandDark,
          unselectedItemColor: Colors.grey.shade400,
          selectedFontSize:   9,
          unselectedFontSize: 9,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(LucideIcons.home),        label: 'HOME'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.shoppingBag), label: 'PESANAN'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.coffee),      label: 'KERANJANG'),
            BottomNavigationBarItem(icon: Icon(LucideIcons.user),        label: 'PROFIL'),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// STICKY HEADER  (tidak berubah)
// ─────────────────────────────────────────────────────────
class StickyHeader extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final bool hasNotification;
  const StickyHeader({super.key, required this.title, required this.subtitle,
    required this.icon, this.hasNotification = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        bottom: 20, left: 24, right: 24),
      decoration: BoxDecoration(
        color: kBrandLight.withOpacity(0.9),
        border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.05)))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.plusJakartaSans(
            fontSize: 24, fontWeight: FontWeight.bold,
            color: kBrandDark, letterSpacing: -1)),
          Text(subtitle, style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold,
            color: Colors.grey, letterSpacing: 1)),
        ]),
        Stack(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFF1F1F1))),
            child: Icon(icon, size: 18, color: kBrandDark)),
          if (hasNotification)
            Positioned(top: 10, right: 10, child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: kBrandAccent, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2)))),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// HOME SCREEN  — fetch produk dari Supabase
// ─────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _activeCategory = 'Semua';
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await ProductService.fetchByCategory(_activeCategory);
      setState(() { _products = products; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const StickyHeader(
        title: 'Cofflow.', subtitle: 'Kopi Terbaik Untukmu',
        icon: LucideIcons.bell, hasNotification: true),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(LucideIcons.search, size: 20, color: Colors.grey),
                hintText: 'Cari kopi favoritmu...',
                hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(100),
                  borderSide: BorderSide.none)),
            ),
          ),
          const SizedBox(height: 28),
          // Kategori
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 24),
              itemCount: ['Semua', 'Kopi', 'Non-Kopi', 'Snack'].length,
              itemBuilder: (ctx, i) {
                final cat = ['Semua', 'Kopi', 'Non-Kopi', 'Snack'][i];
                final isActive = _activeCategory == cat;
                return GestureDetector(
                  onTap: () async {
                    setState(() { _activeCategory = cat; _loading = true; });
                    _loadProducts();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: isActive ? kBrandDark : Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isActive ? kBrandDark : const Color(0xFFF1F1F1)),
                      boxShadow: isActive ? [
                        BoxShadow(color: kBrandDark.withOpacity(0.2),
                          blurRadius: 15, offset: const Offset(0, 5))
                      ] : null),
                    alignment: Alignment.center,
                    child: Text(cat,
                      style: TextStyle(
                        color: isActive ? Colors.white : Colors.grey,
                        fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          // Grid produk
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Pilihan Populer',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kBrandDark)),
              TextButton(onPressed: () {},
                child: const Text('Lihat Semua',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
            ]),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: kBrandDark)))
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 20,
                crossAxisSpacing: 20, childAspectRatio: 0.8),
              itemCount: _products.length,
              itemBuilder: (ctx, i) => ProductCard(product: _products[i]),
            ),
          const SizedBox(height: 32),
          // Reward banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(28),
            width: double.infinity,
            decoration: BoxDecoration(
              color: kBrandDark, borderRadius: BorderRadius.circular(32)),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('FLOW REWARDS',
                  style: TextStyle(color: kBrandAccent, fontWeight: FontWeight.bold,
                    fontSize: 9, letterSpacing: 2)),
                const SizedBox(height: 8),
                const Text('Klaim kopi gratis kamu',
                  style: TextStyle(color: Colors.white, fontSize: 24,
                    fontWeight: FontWeight.bold, letterSpacing: -1)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandAccent, foregroundColor: kBrandDark,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
                  child: const Text('CEK POIN',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ]),
              const Positioned(right: -30, bottom: -30,
                child: Opacity(opacity: 0.1,
                  child: Icon(LucideIcons.coffee, size: 140, color: kBrandAccent))),
            ]),
          ),
          const SizedBox(height: 32),
        ]),
      )),
    ]);
  }
}

// ProductCard tidak berubah
class ProductCard extends StatelessWidget {
  final Product product;
  const ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => DetailScreen(product: product))),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFF8F8F8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.network(product.image, width: double.infinity, fit: BoxFit.cover))),
          const SizedBox(height: 12),
          Text(product.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kBrandDark)),
          Text(product.category.toUpperCase(),
            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold,
              fontSize: 9, letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Rp${product.price ~/ 1000}K',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kBrandDark)),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: kBrandDark, borderRadius: BorderRadius.circular(10)),
              child: const Icon(LucideIcons.plus, color: Colors.white, size: 16)),
          ]),
        ]),
      ),
    );
  }
}

// DetailScreen tidak berubah — AppState.addToCart() tetap sama
class DetailScreen extends StatefulWidget {
  final Product product;
  const DetailScreen({super.key, required this.product});
  @override State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  String _milkType = 'Oat';
  String _sweetness = 'Normal';
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Expanded(child: SingleChildScrollView(child: Column(children: [
          Stack(children: [
            Image.network(widget.product.image,
              width: double.infinity, height: 400, fit: BoxFit.cover),
            Positioned(top: 50, left: 24,
              child: CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.3),
                child: IconButton(
                  icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
                  onPressed: () => Navigator.pop(context)))),
            Positioned(bottom: 30, left: 24, right: 24,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.product.name,
                  style: const TextStyle(color: Colors.white, fontSize: 32,
                    fontWeight: FontWeight.bold, letterSpacing: -1)),
                const SizedBox(height: 8),
                Text(widget.product.description,
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
              ])),
          ]),
          Padding(padding: const EdgeInsets.all(24), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Jenis Susu', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: ['Normal', 'Oat', 'Almond'].map((m) => Expanded(child:
                GestureDetector(onTap: () => setState(() => _milkType = m),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8), height: 44,
                    decoration: BoxDecoration(
                      color: _milkType == m ? kBrandDark : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F1F1))),
                    alignment: Alignment.center,
                    child: Text(m, style: TextStyle(
                      color: _milkType == m ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.bold, fontSize: 12)))))).toList()),
              const SizedBox(height: 32),
              const Text('Kemanisan', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(children: ['Less', 'Normal', 'Extra'].map((l) => Expanded(child:
                GestureDetector(onTap: () => setState(() => _sweetness = l),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8), height: 44,
                    decoration: BoxDecoration(
                      color: _sweetness == l ? kBrandDark : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF1F1F1))),
                    alignment: Alignment.center,
                    child: Text(l, style: TextStyle(
                      color: _sweetness == l ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.bold, fontSize: 12)))))).toList()),
            ])),
        ]))),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFF1F1F1)))),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: kBrandMuted, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                IconButton(icon: const Icon(LucideIcons.minus, size: 18),
                  onPressed: () => setState(() => _quantity = (_quantity - 1).clamp(1, 99))),
                Text('$_quantity',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                IconButton(icon: const Icon(LucideIcons.plus, size: 18),
                  onPressed: () => setState(() => _quantity++)),
              ])),
            const SizedBox(width: 16),
            Expanded(child: ElevatedButton(
              onPressed: () {
                AppState.addToCart(CartItem(
                  product:   widget.product,
                  milkType:  _milkType,
                  sweetness: _sweetness,
                  quantity:  _quantity,
                ));
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandDark, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: Text(
                'TAMBAH • Rp${(widget.product.price * _quantity) ~/ 1000}K',
                style: const TextStyle(fontWeight: FontWeight.bold)))),
          ])),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// CART SCREEN  — pakai AppState.placeOrder()
// ─────────────────────────────────────────────────────────
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});
  @override State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _placing = false;

  @override
  Widget build(BuildContext context) {
    int subtotal = AppState.cart.fold(0, (s, i) => s + i.product.price * i.quantity);
    int tax      = (subtotal * 0.1).toInt();
    int total    = subtotal + tax;

    return Column(children: [
      StickyHeader(title: 'keranjangku.',
        subtitle: '${AppState.cart.length} Produk',
        icon: LucideIcons.shoppingBag),
      Expanded(child: AppState.cart.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(LucideIcons.shoppingBag, size: 64, color: Colors.grey.shade200),
            const SizedBox(height: 16),
            const Text('Keranjangmu kosong',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            itemCount: AppState.cart.length,
            itemBuilder: (ctx, i) {
              final item = AppState.cart[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFF1F1F1))),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(16),
                    child: Image.network(item.product.image,
                      width: 70, height: 70, fit: BoxFit.cover)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: kBrandDark)),
                    Text('${item.milkType} | ${item.sweetness}',
                      style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Rp${(item.product.price * item.quantity) ~/ 1000}K',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ])),
                  Column(children: [
                    IconButton(icon: const Icon(LucideIcons.plus, size: 16),
                      onPressed: () => setState(() => item.quantity++)),
                    Text('${item.quantity}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(LucideIcons.minus, size: 16),
                      onPressed: () => setState(
                        () => item.quantity = (item.quantity - 1).clamp(1, 99))),
                  ]),
                  IconButton(
                    icon: const Icon(LucideIcons.trash2, color: Colors.red, size: 18),
                    onPressed: () => setState(() => AppState.cart.removeAt(i))),
                ]),
              );
            },
          )),
      if (AppState.cart.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: kBrandMuted,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
          child: Column(children: [
            _summaryRow('SUBTOTAL', 'Rp${subtotal ~/ 1000}K'),
            const SizedBox(height: 8),
            _summaryRow('PAJAK (10%)', 'Rp${tax ~/ 1000}K'),
            const SizedBox(height: 12),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('TOTAL',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('Rp${total ~/ 1000}K',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kBrandDark)),
            ]),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _placing ? null : () async {
                setState(() => _placing = true);
                await AppState.placeOrder(context);
                setState(() => _placing = false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrandDark, foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              child: _placing
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('PESAN SEKARANG',
                    style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
          ]),
        ),
    ]);
  }

  Widget _summaryRow(String label, String value) =>
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ]);
}

// ─────────────────────────────────────────────────────────
// ORDERS SCREEN  — realtime dari Supabase, tidak perlu Timer
// ─────────────────────────────────────────────────────────
const orderStatuses = [
  'Pesanan Diterima', 'Sedang Dibuat', 'Siap Diambil', 'Selesai'];

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppState.currentOrder == null) {
      return Column(children: [
        const StickyHeader(title: 'status.', subtitle: 'Lacak Pesananmu', icon: LucideIcons.timer),
        Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(LucideIcons.coffee, size: 64, color: Colors.grey.shade200),
          const SizedBox(height: 16),
          const Text('Belum ada pesanan aktif',
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ]))),
      ]);
    }

    final order = AppState.currentOrder!;
    final currentIdx = orderStatuses.indexOf(order.status);

    return Column(children: [
      StickyHeader(title: 'status pesanan.',
        subtitle: 'Lacak #${order.id}', icon: LucideIcons.coffee),
      Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(children: [
            Expanded(child: _infoCard('ESTIMASI', order.estimatedTime, dark: false)),
            const SizedBox(width: 16),
            Expanded(child: _infoCard('ANTREAN', '${order.queueNumber}', dark: true)),
          ]),
          const SizedBox(height: 40),
          ...List.generate(orderStatuses.length, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(children: [
              Icon(
                currentIdx >= i ? LucideIcons.checkCircle2 : LucideIcons.circle,
                color: currentIdx >= i ? kBrandAccent : Colors.grey.shade300, size: 24),
              const SizedBox(width: 24),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orderStatuses[i],
                  style: TextStyle(fontWeight: FontWeight.bold,
                    color: currentIdx >= i ? kBrandDark : Colors.grey)),
                Text(
                  currentIdx == i ? 'Sedang diproses...'
                    : i < currentIdx ? 'Selesai' : 'Belum diproses',
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
            ]),
          )),
        ]),
      )),
    ]);
  }

  Widget _infoCard(String label, String value, {required bool dark}) =>
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? kBrandDark : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: dark ? null : Border.all(color: const Color(0xFFF1F1F1))),
      child: Column(children: [
        Text(label, style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.bold,
          color: dark ? Colors.white54 : Colors.grey)),
        Text(value, style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold,
          color: dark ? Colors.white : kBrandDark)),
      ]),
    );
}

// ─────────────────────────────────────────────────────────
// PROFILE SCREEN  — data dari Supabase
// ─────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _showHistory = false;
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ProfileService.fetchProfile();
      setState(() { _profile = UserProfile.fromJson(data); _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showHistory) return _historyView();

    return Column(children: [
      const StickyHeader(title: 'profilku.', subtitle: 'Informasi Akun', icon: LucideIcons.user),
      Expanded(child: _loading
        ? const Center(child: CircularProgressIndicator(color: kBrandDark))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              CircleAvatar(radius: 50,
                backgroundImage: NetworkImage(
                  _profile?.avatarUrl ??
                  'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=200')),
              const SizedBox(height: 16),
              Text(_profile?.fullName ?? '—',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text('MEMBER ${_profile?.memberTier ?? ''} SEJAK ${_profile?.memberSince.year ?? ''}',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
                  color: Colors.grey, letterSpacing: 1)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: kBrandDark, borderRadius: BorderRadius.circular(32)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('FLOW POINTS',
                    style: TextStyle(color: Colors.white54, fontSize: 9,
                      fontWeight: FontWeight.bold, letterSpacing: 1)),
                  Text('${_profile?.flowPoints ?? 0}',
                    style: const TextStyle(color: kBrandAccent, fontSize: 36,
                      fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('PROGRES KOPI GRATIS',
                      style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.bold)),
                    Text('${((_profile?.flowPoints ?? 0) % 100)}%',
                      style: const TextStyle(color: kBrandAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: ((_profile?.flowPoints ?? 0) % 100) / 100,
                    backgroundColor: Colors.white10,
                    valueColor: const AlwaysStoppedAnimation(kBrandAccent)),
                ])),
              const SizedBox(height: 32),
              _menuItem('Riwayat Pesanan', LucideIcons.history,
                () => setState(() => _showHistory = true)),
              _menuItem('Ubah Profil',    LucideIcons.user,        () {}),
              _menuItem('Pengaturan',     LucideIcons.settings,    () {}),
              _menuItem('Bantuan',        LucideIcons.helpCircle,  () {}),
              _menuItem('Keluar', LucideIcons.logOut, () async {
                await AuthService.signOut();
                if (mounted) {
                  Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (r) => false);
                }
              }, color: Colors.red),
            ]),
          )),
    ]);
  }

  Widget _historyView() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: OrderService.fetchHistory(),
      builder: (ctx, snap) {
        return Column(children: [
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 10,
              bottom: 20, left: 20, right: 24),
            decoration: BoxDecoration(color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.05)))),
            child: Row(children: [
              IconButton(icon: const Icon(LucideIcons.chevronLeft),
                onPressed: () => setState(() => _showHistory = false)),
              const SizedBox(width: 8),
              const Text('riwayat.',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ])),
          Expanded(child: snap.connectionState == ConnectionState.waiting
            ? const Center(child: CircularProgressIndicator(color: kBrandDark))
            : (snap.data?.isEmpty ?? true)
              ? const Center(child: Text('Belum ada riwayat'))
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: snap.data!.length,
                  itemBuilder: (ctx, i) {
                    final order = snap.data![i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: kBrandMuted, borderRadius: BorderRadius.circular(24)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Order #${order['order_code']}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text((order['created_at'] as String).split('T')[0],
                            style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ]),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('Rp${(order['total'] as int) ~/ 1000}K',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(order['status'] as String,
                            style: const TextStyle(color: kBrandAccent,
                              fontSize: 9, fontWeight: FontWeight.bold)),
                        ]),
                      ]));
                  })),
        ]);
      },
    );
  }

  Widget _menuItem(String title, IconData icon, VoidCallback onTap, {Color? color}) =>
    GestureDetector(onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF8F8F8))),
        child: Row(children: [
          Icon(icon, size: 20, color: color ?? kBrandDark),
          const SizedBox(width: 16),
          Expanded(child: Text(title,
            style: TextStyle(fontWeight: FontWeight.bold, color: color ?? kBrandDark))),
          const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 18),
        ])));
}