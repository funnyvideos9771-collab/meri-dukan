import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBg1 = Color(0xFF0A0F24);
const kBg2 = Color(0xFF1A1040);
const kTeal = Color(0xFF00E5C3);
const kPurple = Color(0xFF8B5CF6);
const kPink = Color(0xFFFF4D8D);
const kOrange = Color(0xFFFFB020);
const kGreen = Color(0xFF2EE59D);
const kRed = Color(0xFFFF5470);

// ------------------------------------------------------------ helpers
String money(double v) {
  final neg = v < 0;
  var s = v.abs().toStringAsFixed(2);
  if (s.endsWith('.00')) s = s.substring(0, s.length - 3);
  final parts = s.split('.');
  final ip = parts[0];
  String out;
  if (ip.length > 3) {
    final last3 = ip.substring(ip.length - 3);
    var rest = ip.substring(0, ip.length - 3);
    final buf = <String>[];
    while (rest.length > 2) {
      buf.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) buf.insert(0, rest);
    out = '${buf.join(',')},$last3';
  } else {
    out = ip;
  }
  if (parts.length > 1) out = '$out.${parts[1]}';
  return '${neg ? '-' : ''}₹$out';
}

String qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

String shortMoney(double v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 100000) return '$sign${(a / 100000).toStringAsFixed(1)}L';
  if (a >= 1000) return '$sign${(a / 1000).toStringAsFixed(1)}k';
  return '$sign${a.toStringAsFixed(0)}';
}

Widget glass({
  required Widget child,
  EdgeInsets padding = const EdgeInsets.all(14),
  VoidCallback? onTap,
  List<Color>? colors,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Ink(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors ?? [Colors.white.withOpacity(0.09), Colors.white.withOpacity(0.03)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: child,
          ),
        ),
      ),
    );

InputDecoration dec(String label, {String? suffix, IconData? icon}) => InputDecoration(
      labelText: label,
      suffixText: suffix,
      prefixIcon: icon == null ? null : Icon(icon, color: kTeal, size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kTeal)),
    );

// ------------------------------------------------------------- models
class Item {
  String id, name, unit;
  double buy, sell, stock, low;
  Item({
    required this.id,
    required this.name,
    this.unit = 'pcs',
    required this.buy,
    required this.sell,
    required this.stock,
    this.low = 5,
  });

  double get unitProfit => sell - buy;
  double get totalProfit => unitProfit * stock;
  double get buyValue => buy * stock;
  double get sellValue => sell * stock;
  int get status => stock <= 0 ? 2 : (stock <= low ? 1 : 0); // 0 ok, 1 kam, 2 khatam

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'unit': unit, 'buy': buy, 'sell': sell, 'stock': stock, 'low': low};

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'].toString(),
        name: j['name'].toString(),
        unit: (j['unit'] ?? 'pcs').toString(),
        buy: (j['buy'] as num).toDouble(),
        sell: (j['sell'] as num).toDouble(),
        stock: (j['stock'] as num).toDouble(),
        low: (j['low'] as num?)?.toDouble() ?? 5,
      );
}

class Sale {
  String name, unit;
  double qty, buy, sell;
  int ts;
  Sale({required this.name, required this.unit, required this.qty, required this.buy, required this.sell, required this.ts});
  double get amount => sell * qty;
  double get profit => (sell - buy) * qty;
  Map<String, dynamic> toJson() =>
      {'name': name, 'unit': unit, 'qty': qty, 'buy': buy, 'sell': sell, 'ts': ts};
  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        name: j['name'].toString(),
        unit: (j['unit'] ?? '').toString(),
        qty: (j['qty'] as num).toDouble(),
        buy: (j['buy'] as num).toDouble(),
        sell: (j['sell'] as num).toDouble(),
        ts: (j['ts'] as num).toInt(),
      );
}

// -------------------------------------------------------------- chart
class BarPainter extends CustomPainter {
  final List<MapEntry<String, double>> data;
  final double t;
  BarPainter(this.data, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const top = 26.0, bottom = 34.0;
    final h = size.height - top - bottom;
    double maxV = 1;
    for (final e in data) {
      maxV = math.max(maxV, e.value.abs());
    }
    final n = data.length;
    final slot = size.width / n;
    final bw = math.min(slot * 0.55, 46.0);
    final base = size.height - bottom;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), Paint()..color = Colors.white24..strokeWidth = 1);
    for (var i = 0; i < n; i++) {
      final v = data[i].value;
      final bh = math.max(3.0, v.abs() / maxV * h * t);
      final cx = slot * i + slot / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - bw / 2, base - bh, bw, bh),
        topLeft: const Radius.circular(10),
        topRight: const Radius.circular(10),
      );
      final colors = v >= 0 ? [kTeal, kPurple] : [kRed, kPink];
      canvas.drawRRect(
          rect,
          Paint()
            ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors)
                .createShader(rect.outerRect));
      _text(canvas, shortMoney(v), Offset(cx, base - bh - 17), 11, Colors.white, bold: true);
      final nm = data[i].key.length > 8 ? '${data[i].key.substring(0, 7)}…' : data[i].key;
      _text(canvas, nm, Offset(cx, base + 8), 11, Colors.white70);
    }
  }

  void _text(Canvas c, String s, Offset center, double size, Color col, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(color: col, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 80);
    tp.paint(c, Offset(center.dx - tp.width / 2, center.dy));
  }

  @override
  bool shouldRepaint(BarPainter o) => o.t != t || o.data != data;
}

// ---------------------------------------------------------------- app
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DukanApp());
}

class DukanApp extends StatelessWidget {
  const DukanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Meri Dukan',
        theme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: kTeal, useMaterial3: true),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String shop = 'Meri Dukan';
  List<Item> items = [];
  List<Sale> sales = [];
  int tab = 0, filter = 0;
  String query = '';
  final shopCtl = TextEditingController();
  String expr = '', result = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    shopCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      shop = p.getString('shop') ?? 'Meri Dukan';
      shopCtl.text = shop == 'Meri Dukan' ? '' : shop;
      items = (p.getStringList('items') ?? [])
          .map((s) => Item.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)))
          .toList();
      sales = (p.getStringList('sales') ?? [])
          .map((s) => Sale.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)))
          .toList();
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('shop', shop);
    await p.setStringList('items', items.map((e) => jsonEncode(e.toJson())).toList());
    await p.setStringList('sales', sales.map((e) => jsonEncode(e.toJson())).toList());
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  bool _isToday(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  String _dateStr() {
    const days = ['Somvaar', 'Mangalvaar', 'Budhvaar', 'Guruvaar', 'Shukravaar', 'Shanivaar', 'Ravivaar'];
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final n = DateTime.now();
    return '${days[n.weekday - 1]}, ${n.day} ${mon[n.month - 1]} ${n.year}';
  }

  // ------------------------------------------------------------ actions
  Future<double?> _askQty(String title, String unit) {
    final c = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151A33),
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: dec('Matra', suffix: unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _sell(Item it) async {
    final q = await _askQty('${it.name} kitna bika?', it.unit);
    if (q == null || q <= 0) return;
    if (q > it.stock) {
      _snack('Stock sirf ${qty(it.stock)} ${it.unit} hai');
      return;
    }
    setState(() {
      it.stock -= q;
      sales.add(Sale(
          name: it.name,
          unit: it.unit,
          qty: q,
          buy: it.buy,
          sell: it.sell,
          ts: DateTime.now().millisecondsSinceEpoch));
    });
    await _save();
    _snack('${qty(q)} ${it.unit} ${it.name} bika - munafa ${money((it.sell - it.buy) * q)}');
  }

  Future<void> _addStock(Item it) async {
    final q = await _askQty('${it.name} me kitna stock badhana hai?', it.unit);
    if (q == null || q <= 0) return;
    setState(() => it.stock += q);
    await _save();
  }

  Future<void> _delete(Item it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151A33),
        title: const Text('Item hatana hai?'),
        content: Text('"${it.name}" master list se hat jayega.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nahi')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Haan, hatao')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => items.removeWhere((e) => e.id == it.id));
      await _save();
    }
  }

  Future<void> _itemSheet({Item? edit}) async {
    final name = TextEditingController(text: edit?.name ?? '');
    final unit = TextEditingController(text: edit?.unit ?? 'pcs');
    final buy = TextEditingController(text: edit == null ? '' : qty(edit.buy));
    final sell = TextEditingController(text: edit == null ? '' : qty(edit.sell));
    final stock = TextEditingController(text: edit == null ? '' : qty(edit.stock));
    final low = TextEditingController(text: edit == null ? '5' : qty(edit.low));
    final numFmt = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    const kb = TextInputType.numberWithOptions(decimal: true);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12162B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final b = double.tryParse(buy.text) ?? 0;
        final s = double.tryParse(sell.text) ?? 0;
        final st = double.tryParse(stock.text) ?? 0;
        final pu = s - b;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                  child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 14),
              Text(edit == null ? 'Naya Item Jodein' : 'Item Badlein',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: dec('Item ka naam', icon: Icons.label)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: buy,
                        keyboardType: kb,
                        inputFormatters: numFmt,
                        onChanged: (_) => setS(() {}),
                        decoration: dec('Kharid bhav', suffix: '₹', icon: Icons.shopping_cart))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: sell,
                        keyboardType: kb,
                        inputFormatters: numFmt,
                        onChanged: (_) => setS(() {}),
                        decoration: dec('Bikri bhav', suffix: '₹', icon: Icons.sell))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: stock,
                        keyboardType: kb,
                        inputFormatters: numFmt,
                        onChanged: (_) => setS(() {}),
                        decoration: dec('Stock (kitna hai)', icon: Icons.inventory))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: unit, decoration: dec('Unit (kg/pcs/ltr)', icon: Icons.straighten))),
              ]),
              const SizedBox(height: 10),
              TextField(
                  controller: low,
                  keyboardType: kb,
                  inputFormatters: numFmt,
                  decoration: dec('Kam stock alert (is se kam ho to chetavni)', icon: Icons.notifications_active)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(colors: [
                    (pu >= 0 ? kGreen : kRed).withOpacity(0.22),
                    (pu >= 0 ? kTeal : kPink).withOpacity(0.08)
                  ]),
                  border: Border.all(color: (pu >= 0 ? kGreen : kRed).withOpacity(0.4)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Munafa per unit', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(money(pu),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pu >= 0 ? kGreen : kRed)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('Pure stock par munafa', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(money(pu * st),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pu >= 0 ? kGreen : kRed)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: kTeal,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  icon: const Icon(Icons.check_circle),
                  label: Text(edit == null ? 'Master me Jodein' : 'Save Karein',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  onPressed: () {
                    final nm = name.text.trim();
                    if (nm.isEmpty) {
                      _snack('Item ka naam likhiye');
                      return;
                    }
                    setState(() {
                      if (edit == null) {
                        items.add(Item(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          name: nm,
                          unit: unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
                          buy: b,
                          sell: s,
                          stock: st,
                          low: double.tryParse(low.text) ?? 5,
                        ));
                      } else {
                        edit.name = nm;
                        edit.unit = unit.text.trim().isEmpty ? 'pcs' : unit.text.trim();
                        edit.buy = b;
                        edit.sell = s;
                        edit.stock = st;
                        edit.low = double.tryParse(low.text) ?? 5;
                      }
                    });
                    _save();
                    Navigator.pop(ctx);
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // --------------------------------------------------------- dashboard
  Widget _header() {
    final khatam = items.where((e) => e.status == 2).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPurple, Color(0xFF3B82F6), kTeal], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
        boxShadow: [BoxShadow(color: kPurple.withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.storefront, size: 32, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shop,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.4,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 8)])),
              const SizedBox(height: 2),
              Text(_dateStr(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('${items.length} items  •  $khatam khatam',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
                colors: [c.withOpacity(0.28), c.withOpacity(0.06)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            border: Border.all(color: c.withOpacity(0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          ]),
        ),
      );

  Widget _mini(String label, String value, Color c) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w800))),
        ]),
      );

  Widget _statusChip(Item it) {
    final c = it.status == 0 ? kGreen : (it.status == 1 ? kOrange : kRed);
    final t = it.status == 0 ? 'Available' : (it.status == 1 ? 'Kam Bacha' : 'Khatam');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withOpacity(0.18), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withOpacity(0.6))),
      child: Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  Widget _itemCard(Item it) {
    final c = it.status == 0 ? kGreen : (it.status == 1 ? kOrange : kRed);
    final pc = it.unitProfit >= 0 ? kGreen : kRed;
    return glass(
      colors: [c.withOpacity(0.10), Colors.white.withOpacity(0.03)],
      child: Column(children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [c, c.withOpacity(0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Text(it.name.isEmpty ? '?' : it.name[0].toUpperCase(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text('Stock: ${qty(it.stock)} ${it.unit}', style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
          _statusChip(it),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _mini('Kharid bhav', money(it.buy), Colors.white),
          _mini('Bikri bhav', money(it.sell), Colors.white),
          _mini('Munafa/unit', money(it.unitProfit), pc),
          _mini('Kul munafa', money(it.totalProfit), pc),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: kTeal, side: const BorderSide(color: kTeal), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: it.stock <= 0 ? null : () => _sell(it),
              icon: const Icon(Icons.sell, size: 18),
              label: const Text('Bikri'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: kOrange, side: const BorderSide(color: kOrange), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => _addStock(it),
              icon: const Icon(Icons.add_box, size: 18),
              label: const Text('+ Stock'),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _dashboard() {
    final shown = items.where((e) {
      if (filter == 1 && e.status != 0) return false;
      if (filter == 2 && e.status != 1) return false;
      if (filter == 3 && e.status != 2) return false;
      if (query.isNotEmpty && !e.name.toLowerCase().contains(query.toLowerCase())) return false;
      return true;
    }).toList();

    double tBuy = 0, tSell = 0, tProfit = 0;
    for (final e in items) {
      tBuy += e.buyValue;
      tSell += e.sellValue;
      tProfit += e.totalProfit;
    }
    double todayProfit = 0, todaySale = 0;
    for (final s in sales.where((s) => _isToday(s.ts))) {
      todayProfit += s.profit;
      todaySale += s.amount;
    }
    final khatam = items.where((e) => e.status == 2).length;
    final kam = items.where((e) => e.status == 1).length;

    final sorted = [...items]..sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
    final chart = sorted.where((e) => e.totalProfit != 0).take(6).map((e) => MapEntry(e.name, e.totalProfit)).toList();

    final chips = <List<dynamic>>[
      [0, 'Sab', kTeal],
      [1, 'Available', kGreen],
      [2, 'Kam', kOrange],
      [3, 'Khatam', kRed],
    ];

    return Column(children: [
      _header(),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), children: [
          Row(children: [
            _statCard(Icons.today, 'Aaj ki bikri', money(todaySale), kTeal),
            const SizedBox(width: 10),
            _statCard(Icons.trending_up, 'Aaj ka munafa', money(todayProfit), kGreen),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _statCard(Icons.warning_amber_rounded, 'Kam stock', '$kam item', kOrange),
            const SizedBox(width: 10),
            _statCard(Icons.remove_shopping_cart, 'Khatam', '$khatam item', kRed),
          ]),
          const SizedBox(height: 14),
          glass(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.bar_chart_rounded, color: kTeal),
                const SizedBox(width: 8),
                const Text('Item-wise Munafa (stock par)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 190,
                child: chart.isEmpty
                    ? const Center(child: Text('Item jodte hi graph yahan dikhega', style: TextStyle(color: Colors.white54)))
                    : TweenAnimationBuilder<double>(
                        key: ValueKey('${chart.length}-${tProfit.toStringAsFixed(0)}'),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => CustomPaint(size: Size.infinite, painter: BarPainter(chart, v)),
                      ),
              ),
            ]),
          ),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: dec('Item dhundhein...', icon: Icons.search),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final c in chips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c[1] as String),
                    selected: filter == c[0],
                    selectedColor: (c[2] as Color).withOpacity(0.35),
                    onSelected: (_) => setState(() => filter = c[0] as int),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            glass(
              child: Column(children: [
                const Icon(Icons.inventory_2_outlined, size: 48, color: kTeal),
                const SizedBox(height: 8),
                const Text('Abhi koi item nahi hai', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Master tab me jaakar apna saman jodein', style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 10),
                FilledButton.icon(
                    onPressed: () => setState(() => tab = 1),
                    icon: const Icon(Icons.add),
                    label: const Text('Master kholein')),
              ]),
            )
          else if (shown.isEmpty)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Is filter me koi item nahi', style: TextStyle(color: Colors.white54))))
          else
            for (final it in shown) _itemCard(it),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1B1F3B), Color(0xFF0F2A3A)]),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: kTeal.withOpacity(0.5))),
          boxShadow: [BoxShadow(color: kTeal.withOpacity(0.2), blurRadius: 18)],
        ),
        child: Row(children: [
          _totalCol('KUL KHARID', money(tBuy), Colors.white),
          _totalCol('KUL BIKRI', money(tSell), kTeal),
          _totalCol('KUL MUNAFA', money(tProfit), tProfit >= 0 ? kGreen : kRed),
        ]),
      ),
    ]);
  }

  Widget _totalCol(String l, String v, Color c) => Expanded(
        child: Column(children: [
          Text(l, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 3),
          FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: TextStyle(color: c, fontSize: 19, fontWeight: FontWeight.w900))),
        ]),
      );

  // ------------------------------------------------------------ master
  Widget _master() => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 12),
            child: Row(children: const [
              Icon(Icons.inventory_2, color: kTeal),
              SizedBox(width: 10),
              Text('MASTER LIST', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ]),
          ),
        ),
        glass(
          colors: [kPurple.withOpacity(0.25), kTeal.withOpacity(0.08)],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Dukan ka naam', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            const Text('Ye Dashboard ke sabse upar dikhega', style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(controller: shopCtl, textCapitalization: TextCapitalization.words, decoration: dec('Jaise: Sharma General Store', icon: Icons.storefront)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kPurple),
                onPressed: () {
                  final n = shopCtl.text.trim();
                  setState(() => shop = n.isEmpty ? 'Meri Dukan' : n);
                  _save();
                  FocusScope.of(context).unfocus();
                  _snack('Dukan ka naam save ho gaya');
                },
                icon: const Icon(Icons.save),
                label: const Text('Naam Save Karein'),
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: kTeal, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => _itemSheet(),
            icon: const Icon(Icons.add_circle, size: 24),
            label: const Text('Naya Item Jodein', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 14),
        Text('Kul ${items.length} items', style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 8),
        for (final it in items)
          glass(
            onTap: () => _itemSheet(edit: it),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 3),
                  Text('Kharid ${money(it.buy)}  •  Bikri ${money(it.sell)}  •  Stock ${qty(it.stock)} ${it.unit}',
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  Text('Munafa/unit ${money(it.unitProfit)}',
                      style: TextStyle(color: it.unitProfit >= 0 ? kGreen : kRed, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.edit, color: kTeal), onPressed: () => _itemSheet(edit: it)),
              IconButton(icon: const Icon(Icons.delete, color: kRed), onPressed: () => _delete(it)),
            ]),
          ),
      ]);

  // ------------------------------------------------------------- sales
  Widget _salesPage() {
    double tSale = 0, tProfit = 0, dSale = 0, dProfit = 0;
    for (final s in sales) {
      tSale += s.amount;
      tProfit += s.profit;
      if (_isToday(s.ts)) {
        dSale += s.amount;
        dProfit += s.profit;
      }
    }
    final list = sales.reversed.toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 12),
          child: Row(children: [
            const Icon(Icons.point_of_sale, color: kTeal),
            const SizedBox(width: 10),
            const Text('BIKRI HISAAB', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const Spacer(),
            if (sales.isNotEmpty)
              TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF151A33),
                        title: const Text('Poori bikri history hatani hai?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nahi')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Haan')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      setState(() => sales.clear());
                      _save();
                    }
                  },
                  child: const Text('Clear', style: TextStyle(color: kRed))),
          ]),
        ),
      ),
      Row(children: [
        _statCard(Icons.today, 'Aaj ki bikri', money(dSale), kTeal),
        const SizedBox(width: 10),
        _statCard(Icons.trending_up, 'Aaj ka munafa', money(dProfit), kGreen),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _statCard(Icons.account_balance_wallet, 'Kul bikri', money(tSale), kPurple),
        const SizedBox(width: 10),
        _statCard(Icons.savings, 'Kul munafa', money(tProfit), kOrange),
      ]),
      const SizedBox(height: 14),
      if (list.isEmpty)
        const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: Text('Abhi koi bikri nahi hui.\nDashboard par item ke "Bikri" button se likhein.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))))
      else
        for (final s in list.take(100))
          glass(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.receipt_long, color: kTeal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                      '${qty(s.qty)} ${s.unit} x ${money(s.sell)}  •  ${DateTime.fromMillisecondsSinceEpoch(s.ts).toString().substring(0, 16)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(s.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('+${money(s.profit)}', style: TextStyle(color: s.profit >= 0 ? kGreen : kRed, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
    ]);
  }

  // -------------------------------------------------------- calculator
  double? _evalExpr(String s) {
    final toks = RegExp(r'(\d+\.?\d*|\.\d+)|[+\-×÷%]').allMatches(s).map((m) => m.group(0)!).toList();
    if (toks.isEmpty) return null;
    final seq = <dynamic>[];
    bool expectNum = true;
    double sign = 1;
    for (final t in toks) {
      if (t == '%') {
        if (seq.isNotEmpty && seq.last is double) seq[seq.length - 1] = (seq.last as double) / 100;
        continue;
      }
      final n = double.tryParse(t);
      if (n != null) {
        seq.add(sign * n);
        sign = 1;
        expectNum = false;
      } else {
        if (expectNum) {
          if (t == '-') sign = -sign;
          continue;
        }
        seq.add(t);
        expectNum = true;
      }
    }
    if (seq.isNotEmpty && seq.last is String) seq.removeLast();
    if (seq.isEmpty) return null;
    final a = <dynamic>[seq.first];
    for (var i = 1; i + 1 < seq.length; i += 2) {
      final op = seq[i] as String;
      final r = seq[i + 1] as double;
      if (op == '×' || op == '÷') {
        final l = a.removeLast() as double;
        if (op == '÷' && r == 0) return null;
        a.add(op == '×' ? l * r : l / r);
      } else {
        a.add(op);
        a.add(r);
      }
    }
    double res = a.first as double;
    for (var i = 1; i + 1 < a.length; i += 2) {
      final op = a[i] as String;
      final r = a[i + 1] as double;
      res = op == '+' ? res + r : res - r;
    }
    return res;
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e12) return v.toInt().toString();
    var s = v.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  void _calcTap(String k) {
    setState(() {
      if (k == 'C') {
        expr = '';
        result = '';
      } else if (k == '⌫') {
        if (expr.isNotEmpty) expr = expr.substring(0, expr.length - 1);
        _live();
      } else if (k == '=') {
        final v = _evalExpr(expr);
        if (v == null) {
          result = 'Error';
        } else {
          expr = _fmtNum(v);
          result = '';
        }
      } else {
        const ops = ['+', '-', '×', '÷'];
        if (ops.contains(k) && expr.isNotEmpty && ops.contains(expr[expr.length - 1])) {
          expr = expr.substring(0, expr.length - 1) + k;
        } else if (expr.length < 40) {
          expr += k;
        }
        _live();
      }
    });
  }

  void _live() {
    final v = _evalExpr(expr);
    result = (v == null || expr.isEmpty) ? '' : '= ${_fmtNum(v)}';
  }

  Widget _calc() {
    const keys = ['C', '⌫', '%', '÷', '7', '8', '9', '×', '4', '5', '6', '-', '1', '2', '3', '+', '00', '0', '.', '='];
    Color bg(String k) {
      if (k == '=') return kTeal;
      if (['÷', '×', '-', '+'].contains(k)) return kPurple.withOpacity(0.6);
      if (['C', '⌫', '%'].contains(k)) return kPink.withOpacity(0.35);
      return Colors.white.withOpacity(0.08);
    }

    return Column(children: [
      SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
            Icon(Icons.calculate, color: kTeal),
            SizedBox(width: 10),
            Text('HISAAB (CALCULATOR)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ]),
        ),
      ),
      Expanded(
        flex: 2,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(colors: [kPurple.withOpacity(0.25), kTeal.withOpacity(0.1)]),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end, children: [
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(expr.isEmpty ? '0' : expr, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800))),
            const SizedBox(height: 6),
            Text(result, style: const TextStyle(fontSize: 22, color: kTeal, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      Expanded(
        flex: 5,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final k in keys)
                Material(
                  color: bg(k),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _calcTap(k);
                    },
                    child: Center(
                        child: Text(k,
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: k == '=' ? Colors.black : Colors.white))),
                  ),
                ),
            ],
          ),
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final pages = [_dashboard(), _master(), _salesPage(), _calc()];
    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [kBg1, kBg2], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: pages[tab],
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xFF10142B),
          indicatorColor: kTeal.withOpacity(0.25),
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Master'),
            NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Bikri'),
            NavigationDestination(icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate), label: 'Hisab'),
          ],
        ),
      ),
    );
  }
}
