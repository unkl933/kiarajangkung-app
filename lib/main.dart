import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeDateFormatting('id_ID', null).catchError((e) {
    print("Error init date format: $e");
  });
  runApp(const WarungBarokahApp());
}

class WarungBarokahApp extends StatelessWidget {
  const WarungBarokahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warung Barokah Kiarajangkung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          primary: const Color(0xFF10B981),
          surface: const Color(0xFFF4FDF4),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4FDF4),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF10B981),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const MainHomeScreen(),
    );
  }
}

class Product {
  String id;
  String name;
  String category;
  double buyPrice;
  double price;
  double halfPrice;     
  double quarterPrice;  
  int stock;
  String retailName;
  int retailConversion;
  double retailPrice;
  String barcode;
  bool isConsignment;
  String salesName;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.buyPrice,
    required this.price,
    this.halfPrice = 0,
    this.quarterPrice = 0,
    required this.stock,
    this.retailName = '',
    this.retailConversion = 1,
    this.retailPrice = 0,
    this.barcode = '',
    this.isConsignment = false,
    this.salesName = '',
  });

  bool get hasRetail => retailName.isNotEmpty && retailConversion > 1 && retailPrice > 0;
  bool get hasHalfPrice => halfPrice > 0;
  bool get hasQuarterPrice => quarterPrice > 0;

  String getFormattedStock() {
    if (!hasRetail) return '$stock Pcs';
    int mainUnit = stock ~/ retailConversion;
    int remainder = stock % retailConversion;
    if (remainder == 0) {
      return '$mainUnit Unit Utama ($stock Total)';
    }
    return '$mainUnit Unit + $remainder $retailName ($stock Total)';
  }
}

enum CartUnitType { full, half, quarter, retail }

class CartItem {
  Product product;
  int quantity;
  CartUnitType unitType;

  CartItem({
    required this.product, 
    required this.quantity, 
    this.unitType = CartUnitType.full
  });

  double get unitPrice {
    switch (unitType) {
      case CartUnitType.quarter:
        return product.quarterPrice;
      case CartUnitType.half:
        return product.halfPrice;
      case CartUnitType.retail:
        return product.retailPrice;
      case CartUnitType.full:
      default:
        return product.price;
    }
  }

  double get totalPrice => unitPrice * quantity;
  
  double get totalBuyPrice {
    if (product.isConsignment) return 0;
    double buyPerSmallUnit = product.buyPrice / (product.retailConversion > 0 ? product.retailConversion : 1);
    return buyPerSmallUnit * stockDeduction;
  }

  int get stockDeduction {
    switch (unitType) {
      case CartUnitType.quarter:
        return quantity * (product.retailConversion ~/ 4);
      case CartUnitType.half:
        return quantity * (product.retailConversion ~/ 2);
      case CartUnitType.retail:
        return quantity;
      case CartUnitType.full:
      default:
        return quantity * product.retailConversion;
    }
  }

  String get unitLabel {
    switch (unitType) {
      case CartUnitType.quarter:
        return '1/4 Unit';
      case CartUnitType.half:
        return '1/2 Unit';
      case CartUnitType.retail:
        return product.retailName.isNotEmpty ? product.retailName : 'Eceran';
      case CartUnitType.full:
      default:
        return 'Utama';
    }
  }
}

class TransactionRecord {
  String id;
  DateTime date;
  List<CartItem> items;
  double subtotal;
  double discount;
  double tax;
  double total;
  double payAmount;
  double change;
  double customNetProfit;
  String itemsSummary;
  String staffName;
  String paymentType;

  TransactionRecord({
    required this.id,
    required this.date,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.payAmount,
    required this.change,
    this.customNetProfit = 0,
    this.itemsSummary = '',
    this.staffName = '-',
    this.paymentType = 'Tunai',
  });

  double get totalCapital {
    return items.fold(0, (sum, item) {
      if (item.product.isConsignment) {
        double buyPerSmallUnit = item.product.buyPrice / (item.product.retailConversion > 0 ? item.product.retailConversion : 1);
        return sum + (buyPerSmallUnit * item.stockDeduction);
      }
      return sum + item.totalBuyPrice;
    });
  }

  double get netProfit => items.isNotEmpty ? ((subtotal - discount) - totalCapital) : customNetProfit;
}

class DebtRecord {
  String id;
  String customerName;
  String staffName;
  DateTime date;
  double totalAmount;
  double paidAmount;
  double remainingAmount;
  String status;
  String itemsSummary;
  String settlementHistory;

  DebtRecord({
    required this.id,
    required this.customerName,
    required this.staffName,
    required this.date,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    required this.status,
    required this.itemsSummary,
    this.settlementHistory = '',
  });
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  List<Product> products = [];
  List<CartItem> cart = [];
  List<TransactionRecord> transactions = [];
  List<DebtRecord> debts = [];

  final TextEditingController searchKasirController = TextEditingController();
  String searchKasirQuery = '';
  String selectedCategory = 'Semua';

  final TextEditingController searchMasterController = TextEditingController();
  String searchMasterQuery = '';
  String productSortOption = 'Default';

  final AudioPlayer audioPlayer = AudioPlayer();

  final String googleSheetUrl =
      'https://script.google.com/macros/s/AKfycbx0Vw5ldIELsmoXzTNiW9VBeLYeNxaJ15CaX9IhnjBPIWqdxIVJSYN8lUPjMMjyOiet/exec';

  final currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      fetchAllDataFromGoogleSheets();
    });
  }

  @override
  void dispose() {
    searchKasirController.dispose();
    searchMasterController.dispose();
    audioPlayer.dispose();
    super.dispose();
  }

  void fetchAllDataFromGoogleSheets() {
    fetchProductsFromGoogleSheets();
    fetchTransactionsFromGoogleSheets();
    fetchDebtsFromGoogleSheets();
  }

  Future<void> fetchProductsFromGoogleSheets() async {
    try {
      final response = await http.get(Uri.parse(googleSheetUrl));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            products = data.map((item) {
              String id = item['id'].toString();
              
              bool existingConsignment = false;
              String existingSalesName = '';
              
              try {
                final oldProd = products.firstWhere((p) => p.id == id);
                existingConsignment = oldProd.isConsignment;
                existingSalesName = oldProd.salesName;
              } catch (_) {}

              bool serverIsConsignment = item['isConsignment'] == true || item['isConsignment'].toString() == 'true';
              String serverSalesName = item['salesName'] ?? '';

              return Product(
                id: id,
                name: item['name'] ?? '',
                category: item['category'] ?? 'Umum',
                buyPrice: (item['buyPrice'] as num?)?.toDouble() ?? 0,
                price: (item['price'] as num?)?.toDouble() ?? 0,
                halfPrice: (item['halfPrice'] as num?)?.toDouble() ?? 0,
                quarterPrice: (item['quarterPrice'] as num?)?.toDouble() ?? 0,
                stock: (item['stock'] as num?)?.toInt() ?? 0,
                retailName: item['retailName'] ?? '',
                retailConversion: (item['retailConversion'] as num?)?.toInt() ?? 1,
                retailPrice: (item['retailPrice'] as num?)?.toDouble() ?? 0,
                barcode: item['barcode'] ?? '',
                isConsignment: serverIsConsignment || existingConsignment,
                salesName: serverSalesName.isNotEmpty ? serverSalesName : existingSalesName,
              );
            }).toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat produk: $e");
    }
  }

  Future<void> fetchTransactionsFromGoogleSheets() async {
    try {
      final response =
          await http.get(Uri.parse('$googleSheetUrl?action=getTransactions'));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            transactions = data.map((item) {
              DateTime parsedDate;
              try {
                parsedDate = DateTime.parse(item['date'].toString());
              } catch (_) {
                parsedDate = DateTime.now();
              }
              return TransactionRecord(
                id: item['id'].toString(),
                date: parsedDate,
                items: [],
                subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0,
                discount: (item['discount'] as num?)?.toDouble() ?? 0,
                tax: (item['tax'] as num?)?.toDouble() ?? 0,
                total: (item['total'] as num?)?.toDouble() ?? 0,
                payAmount: (item['total'] as num?)?.toDouble() ?? 0,
                change: 0,
                customNetProfit: (item['netProfit'] as num?)?.toDouble() ?? 0,
                itemsSummary: item['itemsSummary'] ?? '',
                staffName: item['staffName'] ?? '-',
                paymentType: item['paymentType'] ?? 'Tunai',
              );
            }).toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat transaksi: $e");
    }
  }

  Future<void> fetchDebtsFromGoogleSheets() async {
    try {
      final response =
          await http.get(Uri.parse('$googleSheetUrl?action=getDebts'));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            debts = data.map((item) {
              DateTime parsedDate;
              try {
                parsedDate = DateTime.parse(item['date'].toString());
              } catch (_) {
                parsedDate = DateTime.now();
              }
              return DebtRecord(
                id: item['id'].toString(),
                customerName: item['customerName'] ?? '-',
                staffName: item['staffName'] ?? '-',
                date: parsedDate,
                totalAmount: (item['totalAmount'] as num?)?.toDouble() ?? 0,
                paidAmount: (item['paidAmount'] as num?)?.toDouble() ?? 0,
                remainingAmount:
                    (item['remainingAmount'] as num?)?.toDouble() ?? 0,
                status: item['status'] ?? 'Belum Lunas',
                itemsSummary: item['itemsSummary'] ?? '',
                settlementHistory: item['settlementHistory'] ?? '',
              );
            }).toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat kasbon: $e");
    }
  }

  Future<void> saveProductToGoogleSheets(Product product) async {
    try {
      await http.post(
        Uri.parse(googleSheetUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "action": "saveProduct",
          "id": product.id,
          "name": product.name,
          "category": product.category,
          "buyPrice": product.buyPrice,
          "price": product.price,
          "halfPrice": product.halfPrice,
          "quarterPrice": product.quarterPrice,
          "stock": product.stock,
          "retailName": product.retailName,
          "retailConversion": product.retailConversion,
          "retailPrice": product.retailPrice,
          "barcode": product.barcode,
          "isConsignment": product.isConsignment,
          "salesName": product.salesName,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan produk: $e");
    }
  }

  Future<void> saveTransactionToGoogleSheets(TransactionRecord trx) async {
    try {
      String itemsSummary = trx.items
          .map((i) => "${i.product.name} (${i.quantity} ${i.unitLabel})")
          .join(", ");

      await http.post(
        Uri.parse(googleSheetUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "action": "saveTransaction",
          "id": trx.id,
          "date": DateFormat('yyyy-MM-dd HH:mm:ss').format(trx.date),
          "subtotal": trx.subtotal,
          "discount": trx.discount,
          "tax": trx.tax,
          "total": trx.total,
          "netProfit": trx.netProfit,
          "itemsSummary": itemsSummary,
          "staffName": trx.staffName,
          "paymentType": trx.paymentType,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan transaksi: $e");
    }
  }

  Future<void> saveDebtToGoogleSheets(DebtRecord debt) async {
    try {
      await http.post(
        Uri.parse(googleSheetUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "action": "saveDebt",
          "id": debt.id,
          "customerName": debt.customerName,
          "staffName": debt.staffName,
          "date": DateFormat('yyyy-MM-dd HH:mm:ss').format(debt.date),
          "totalAmount": debt.totalAmount,
          "paidAmount": debt.paidAmount,
          "remainingAmount": debt.remainingAmount,
          "status": debt.status,
          "itemsSummary": debt.itemsSummary,
          "settlementHistory": debt.settlementHistory,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan kasbon: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      buildKasirPage(),
      buildProductManagementPage(),
      buildRestockPage(),
      buildConsignmentReportPage(),
      buildDebtPage(),
      buildHistoryPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Menu modul usaha',
          icon: const Icon(Icons.menu),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              builder: (ctx) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(title: Text('Menu Usaha', style: TextStyle(fontWeight: FontWeight.bold))),
                    ListTile(
                      leading: const Icon(Icons.storefront, color: Color(0xFF10B981)),
                      title: const Text('Warung Barokah'),
                      subtitle: const Text('Kasir dan pengelolaan warung'),
                      onTap: () => Navigator.pop(ctx),
                    ),
                    ListTile(
                      leading: const Icon(Icons.propane_tank, color: Color(0xFF10B981)),
                      title: const Text('Pangkalan GAS LPG'),
                      subtitle: const Text('Penjualan, stok, tabung, retur dan kasbon'),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => LpgModuleScreen(apiUrl: googleSheetUrl)));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.grass, color: Color(0xFF10B981)),
                      title: const Text('Jual Beli Gabah / Padi'),
                      subtitle: const Text('Pembelian, penjualan, pinjaman, stok dan pengiriman pabrik'),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => GabahModuleScreen(apiUrl: googleSheetUrl)));
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Warung Barokah',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                Text('Kiarajangkung',
                    style: TextStyle(fontSize: 11, color: Colors.white70)),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Data',
            onPressed: () {
              fetchAllDataFromGoogleSheets();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memperbarui data...')),
              );
            },
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: const Color(0xFF10B981),
          unselectedItemColor: Colors.grey[400],
          backgroundColor: Colors.white,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.point_of_sale_rounded), label: 'Kasir'),
            BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), label: 'Produk'),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Belanja'),
            BottomNavigationBarItem(icon: Icon(Icons.local_shipping_outlined), label: 'Sales'),
            BottomNavigationBarItem(icon: Icon(Icons.menu_book_rounded), label: 'Kasbon'),
            BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: 'Laporan'),
          ],
        ),
      ),
    );
  }

  List<String> getCategories() {
    Set<String> categories = {'Semua'};
    for (var p in products) {
      if (p.category.isNotEmpty) categories.add(p.category);
    }
    return categories.toList();
  }

  // ================= 1. HALAMAN KASIR =================
  Widget buildKasirPage() {
    double subtotal = cart.fold(0, (sum, item) => sum + item.totalPrice);
    int totalItemsCount = cart.fold(0, (sum, item) => sum + item.quantity);
    List<String> categories = getCategories();

    List<Product> filteredProducts = products.where((prod) {
      bool matchesSearch = prod.name.toLowerCase().contains(searchKasirQuery.toLowerCase()) ||
          prod.barcode.toLowerCase().contains(searchKasirQuery.toLowerCase());
      bool matchesCategory = selectedCategory == 'Semua' || prod.category == selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              color: const Color(0xFFF4FDF4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: searchKasirController,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Cari produk / scan barcode...',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF10B981)),
                          suffixIcon: searchKasirQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      searchKasirController.clear();
                                      searchKasirQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (value) => setState(() => searchKasirQuery = value),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () async {
                      final scannedCode = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
                      );
                      if (scannedCode != null && scannedCode.toString().isNotEmpty) {
                        processScannedBarcode(scannedCode.toString());
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.qr_code_scanner, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  String cat = categories[index];
                  bool isSelected = selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF334155),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFF10B981),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      showCheckmark: false,
                      onSelected: (bool selected) => setState(() => selectedCategory = cat),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            
            Expanded(
              child: filteredProducts.isEmpty
                  ? const Center(
                      child: Text('Produk tidak ditemukan', style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(bottom: cart.isNotEmpty ? 90 : 16),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final prod = filteredProducts[index];
                        int cartQty = getCartQtyForProduct(prod);

                        String initial = prod.name.trim().length >= 2 
                            ? prod.name.trim().substring(0, 2).toUpperCase() 
                            : prod.name.trim().toUpperCase();

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFECFDF5),
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            title: Text(
                              prod.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            subtitle: Text(
                              'Jual: ${currencyFormatter.format(prod.price)}   -   Stok: ${prod.getFormattedStock()}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                            trailing: cartQty > 0
                                ? Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF10B981)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () => handleRemoveOneFromCart(prod),
                                          child: const Padding(
                                            padding: EdgeInsets.all(6.0),
                                            child: Icon(Icons.remove, size: 16, color: Color(0xFF10B981)),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            '$cartQty',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF059669),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: prod.stock > 0 ? () => handleAddToCart(prod) : null,
                                          child: const Padding(
                                            padding: EdgeInsets.all(6.0),
                                            child: Icon(Icons.add, size: 16, color: Color(0xFF10B981)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Material(
                                    color: prod.stock > 0 ? const Color(0xFF10B981) : Colors.grey[300],
                                    borderRadius: BorderRadius.circular(8),
                                    child: InkWell(
                                      onTap: prod.stock > 0 ? () => handleAddToCart(prod) : null,
                                      borderRadius: BorderRadius.circular(8),
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(Icons.add, color: Colors.white, size: 18),
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),

        if (cart.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: GestureDetector(
              onTap: () => showCartBottomSheet(subtotal),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$totalItemsCount Barang',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Subtotal', style: TextStyle(color: Colors.grey, fontSize: 10)),
                            Text(
                              currencyFormatter.format(subtotal),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: () => showPaymentDialog(subtotal),
                      child: const Row(
                        children: [
                          Text('BAYAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  int getCartQtyForProduct(Product prod) {
    int total = 0;
    for (var item in cart) {
      if (item.product.id == prod.id) {
        total += item.quantity;
      }
    }
    return total;
  }

  void handleRemoveOneFromCart(Product prod) {
    setState(() {
      int idx = cart.indexWhere((c) => c.product.id == prod.id);
      if (idx != -1) {
        if (cart[idx].quantity > 1) {
          cart[idx].quantity--;
        } else {
          cart.removeAt(idx);
        }
      }
    });
  }

  void showCartBottomSheet(double subtotal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Rincian Keranjang',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => cart.clear());
                          Navigator.pop(context);
                        },
                        child: const Text('Kosongkan', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    ],
                  ),
                  const Divider(),
                  Flexible(
                    child: cart.isEmpty
                        ? const Center(child: Text('Keranjang kosong'))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: cart.length,
                            itemBuilder: (context, index) {
                              final item = cart[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${item.product.name} (${item.unitLabel})',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                                subtitle: Text(
                                  '${item.quantity} x ${currencyFormatter.format(item.unitPrice)} = ${currencyFormatter.format(item.totalPrice)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                      onPressed: () {
                                        setState(() {
                                          if (item.quantity > 1) {
                                            item.quantity--;
                                          } else {
                                            cart.removeAt(index);
                                          }
                                        });
                                        setSheetState(() {});
                                      },
                                    ),
                                    Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, color: Color(0xFF10B981), size: 20),
                                      onPressed: () {
                                        setState(() {
                                          item.quantity++;
                                        });
                                        setSheetState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total: ${currencyFormatter.format(subtotal)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          showPaymentDialog(subtotal);
                        },
                        child: const Text('PROSES BAYAR'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void processScannedBarcode(String code) async {
    try {
      final matchingProduct = products.firstWhere(
        (p) => p.barcode == code || p.id == code,
      );

      await audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/submarines/sonar_ping.ogg'));
      HapticFeedback.mediumImpact();

      handleAddToCart(matchingProduct);
    } catch (_) {
      await audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/alarms/beep_short.ogg'));
      HapticFeedback.vibrate();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('Barcode "$code" belum terdaftar!'),
          action: SnackBarAction(
            label: '+ Tambah Produk',
            textColor: Colors.amberAccent,
            onPressed: () {
              setState(() => _currentIndex = 1);
              showProductDialog(null, initialBarcode: code);
            },
          ),
        ),
      );
    }
  }

  void handleAddToCart(Product prod) {
    if (!prod.hasRetail && !prod.hasHalfPrice && !prod.hasQuarterPrice) {
      addItemToCart(prod, 1, CartUnitType.full);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pilih Satuan - ${prod.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.inventory, color: Color(0xFF10B981)),
              title: const Text('Satuan Utuh (Bungkus/Pax)'),
              subtitle: Text('Harga: ${currencyFormatter.format(prod.price)}'),
              onTap: () {
                Navigator.pop(context);
                addItemToCart(prod, 1, CartUnitType.full);
              },
            ),
            if (prod.hasHalfPrice) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.pie_chart, color: Colors.orange),
                title: const Text('Setengah (1/2 Bungkus)'),
                subtitle: Text('Harga: ${currencyFormatter.format(prod.halfPrice)}'),
                onTap: () {
                  Navigator.pop(context);
                  addItemToCart(prod, 1, CartUnitType.half);
                },
              ),
            ],
            if (prod.hasQuarterPrice) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.donut_small, color: Colors.purple),
                title: const Text('Seperempat (1/4 Bungkus)'),
                subtitle: Text('Harga: ${currencyFormatter.format(prod.quarterPrice)}'),
                onTap: () {
                  Navigator.pop(context);
                  addItemToCart(prod, 1, CartUnitType.quarter);
                },
              ),
            ],
            if (prod.hasRetail) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.storefront, color: Colors.blue),
                title: Text('Satuan Eceran (${prod.retailName})'),
                subtitle: Text('Harga: ${currencyFormatter.format(prod.retailPrice)}'),
                onTap: () {
                  Navigator.pop(context);
                  addItemToCart(prod, 1, CartUnitType.retail);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void addItemToCart(Product prod, int qty, CartUnitType unitType) {
    setState(() {
      int requiredStock = 0;
      if (unitType == CartUnitType.quarter) {
        requiredStock = qty * (prod.retailConversion ~/ 4);
      } else if (unitType == CartUnitType.half) {
        requiredStock = qty * (prod.retailConversion ~/ 2);
      } else if (unitType == CartUnitType.retail) {
        requiredStock = qty;
      } else {
        requiredStock = qty * prod.retailConversion;
      }

      int existingIndex = cart.indexWhere((c) => c.product.id == prod.id && c.unitType == unitType);
      
      if (existingIndex != -1) {
        int newQty = cart[existingIndex].quantity + qty;
        int totalRequired = 0;
        if (unitType == CartUnitType.quarter) {
          totalRequired = newQty * (prod.retailConversion ~/ 4);
        } else if (unitType == CartUnitType.half) {
          totalRequired = newQty * (prod.retailConversion ~/ 2);
        } else if (unitType == CartUnitType.retail) {
          totalRequired = newQty;
        } else {
          totalRequired = newQty * prod.retailConversion;
        }

        if (totalRequired <= prod.stock) {
          cart[existingIndex].quantity = newQty;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok tidak cukup!')));
        }
      } else {
        if (requiredStock <= prod.stock) {
          cart.add(CartItem(product: prod, quantity: qty, unitType: unitType));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok tidak cukup!')));
        }
      }
    });
  }

  void showPaymentDialog(double subtotal) {
    TextEditingController discountCtrl = TextEditingController(text: '0');
    TextEditingController taxPercentCtrl = TextEditingController(text: '0');
    TextEditingController payCtrl = TextEditingController();
    TextEditingController customerNameCtrl = TextEditingController();
    TextEditingController staffNameCtrl = TextEditingController();
    
    TextEditingController splitCashCtrl = TextEditingController(text: '0');
    TextEditingController splitQrisCtrl = TextEditingController(text: '0');

    String paymentType = 'Tunai';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double discount = double.tryParse(discountCtrl.text) ?? 0;
            double taxPercent = double.tryParse(taxPercentCtrl.text) ?? 0;
            double taxAmount = (subtotal - discount) * (taxPercent / 100);
            double grandTotal = (subtotal - discount) + taxAmount;

            double payAmount = double.tryParse(payCtrl.text) ?? 0;
            if (paymentType == 'Kasbon Penuh') payAmount = 0;
            
            double remainingDebt = paymentType != 'Tunai' && paymentType != 'QRIS' 
                ? (grandTotal - payAmount > 0 ? grandTotal - payAmount : 0) 
                : 0;

            double splitCash = double.tryParse(splitCashCtrl.text) ?? 0;
            double splitQris = double.tryParse(splitQrisCtrl.text) ?? 0;
            double splitRemaining = grandTotal - (splitCash + splitQris);

            return AlertDialog(
              title: const Text('Pembayaran & Metode'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: staffNameCtrl,
                      decoration: const InputDecoration(labelText: 'Nama Kasir *', prefixIcon: Icon(Icons.person), border: OutlineInputBorder(), isDense: true),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: paymentType,
                      decoration: const InputDecoration(labelText: 'Metode Pembayaran', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'Tunai', child: Text('💵 Tunai / Lunas')),
                        DropdownMenuItem(value: 'QRIS', child: Text('📱 QRIS (Non-Tunai)')),
                        DropdownMenuItem(value: 'Split Bill', child: Text('🔀 Split Bill (Tunai + QRIS)')),
                        DropdownMenuItem(value: 'Kasbon Penuh', child: Text('🔴 Kasbon Penuh (Rp 0)')),
                        DropdownMenuItem(value: 'Kasbon Sebagian', child: Text('🟡 Bayar Sebagian (DP)')),
                      ],
                      onChanged: (val) => setDialogState(() {
                        paymentType = val!;
                        if (paymentType == 'Kasbon Penuh') payCtrl.text = '0';
                        if (paymentType == 'QRIS') payCtrl.text = grandTotal.toString();
                      }),
                    ),
                    if (paymentType != 'Tunai' && paymentType != 'QRIS' && paymentType != 'Split Bill') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: customerNameCtrl,
                        decoration: const InputDecoration(labelText: 'Nama Pengutang / Pelanggan *', prefixIcon: Icon(Icons.badge), border: OutlineInputBorder(), isDense: true),
                      ),
                    ],
                    const Divider(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal:'), Text(currencyFormatter.format(subtotal))]),
                    const SizedBox(height: 6),
                    TextField(controller: discountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diskon (Rp)', prefixText: 'Rp ', border: OutlineInputBorder(), isDense: true), onChanged: (val) => setDialogState(() {})),
                    const SizedBox(height: 6),
                    TextField(controller: taxPercentCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PPN (%)', suffixText: '%', border: OutlineInputBorder(), isDense: true), onChanged: (val) => setDialogState(() {})),
                    const Divider(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL BELANJA:', style: TextStyle(fontWeight: FontWeight.bold)), Text(currencyFormatter.format(grandTotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF10B981)))]),
                    
                    if (paymentType == 'QRIS') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                        child: Column(
                          children: [
                            const Text('Scan QRIS Warung Barokah (Tap untuk Zoom)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => Dialog(
                                    backgroundColor: Colors.black,
                                    child: InteractiveViewer(
                                      panEnabled: true,
                                      boundaryMargin: const EdgeInsets.all(20),
                                      minScale: 0.5,
                                      maxScale: 4,
                                      child: Image.asset(
                                        'assets/images/qris.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Image.asset(
                                'assets/images/qris.png',
                                width: 180,
                                height: 180,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('Nominal: ${currencyFormatter.format(grandTotal)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                      )
                    ],

                    if (paymentType == 'Split Bill') ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pengaturan Split Bill (Bagi Tagihan):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: splitCashCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Bayar Tunai (Rp)', prefixText: 'Rp ', border: OutlineInputBorder(), isDense: true),
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: splitQrisCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Bayar QRIS (Rp)', prefixText: 'Rp ', border: OutlineInputBorder(), isDense: true),
                              onChanged: (val) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Kurang / Sisa:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                Text(currencyFormatter.format(splitRemaining), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: splitRemaining == 0 ? Colors.green : Colors.red)),
                              ],
                            )
                          ],
                        ),
                      )
                    ],

                    if (paymentType != 'Kasbon Penuh' && paymentType != 'QRIS' && paymentType != 'Split Bill') ...[
                      const SizedBox(height: 10),
                      TextField(controller: payCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: paymentType == 'Kasbon Sebagian' ? 'Uang DP' : 'Uang Diterima', prefixText: 'Rp ', border: const OutlineInputBorder()), onChanged: (val) => setDialogState(() {})),
                    ],
                    if (paymentType != 'Tunai' && paymentType != 'QRIS' && paymentType != 'Split Bill') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.red[50],
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Sisa Utang:', style: TextStyle(color: Colors.red)), Text(currencyFormatter.format(remainingDebt), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                      )
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                  onPressed: () {
                    if (staffNameCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi Nama Kasir!')));
                      return;
                    }
                    if (paymentType != 'Tunai' && paymentType != 'QRIS' && paymentType != 'Split Bill' && customerNameCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Isi Nama Pengutang!')));
                      return;
                    }
                    if (paymentType == 'Tunai' && payAmount < grandTotal) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uang pembayaran kurang!')));
                      return;
                    }
                    if (paymentType == 'Split Bill' && splitRemaining > 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Total pembayaran Split Bill belum lunas!')));
                      return;
                    }

                    double finalPaid = paymentType == 'QRIS' ? grandTotal : (paymentType == 'Split Bill' ? (splitCash + splitQris) : payAmount);
                    double kembalian = (paymentType == 'Tunai') ? finalPaid - grandTotal : 0;
                    if (paymentType == 'Split Bill' && (splitCash + splitQris) > grandTotal) {
                      kembalian = (splitCash + splitQris) - grandTotal;
                    }

                    for (var item in cart) {
                      item.product.stock -= item.stockDeduction;
                      saveProductToGoogleSheets(item.product);
                    }

                    String summary = cart.map((i) => "${i.product.name} (${i.quantity} ${i.unitLabel})").join(", ");
                    String finalPaymentLabel = paymentType == 'Split Bill' ? 'Split Bill (Tunai+QRIS)' : paymentType;

                    TransactionRecord trx = TransactionRecord(
                      id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                      date: DateTime.now(),
                      items: List.from(cart),
                      subtotal: subtotal,
                      discount: discount,
                      tax: taxAmount,
                      total: grandTotal,
                      payAmount: finalPaid,
                      change: kembalian,
                      staffName: staffNameCtrl.text,
                      paymentType: finalPaymentLabel,
                      itemsSummary: summary,
                    );

                    saveTransactionToGoogleSheets(trx);
                    transactions.add(trx);

                    if (paymentType != 'Tunai' && paymentType != 'QRIS' && paymentType != 'Split Bill') {
                      DebtRecord newDebt = DebtRecord(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        customerName: customerNameCtrl.text,
                        staffName: staffNameCtrl.text,
                        date: DateTime.now(),
                        totalAmount: grandTotal,
                        paidAmount: finalPaid,
                        remainingAmount: remainingDebt,
                        status: 'Belum Lunas',
                        itemsSummary: summary,
                        settlementHistory: finalPaid > 0 ? "${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}: DP ${currencyFormatter.format(finalPaid)} (${staffNameCtrl.text})\n" : "",
                      );
                      saveDebtToGoogleSheets(newDebt);
                      debts.add(newDebt);
                    }

                    setState(() => cart.clear());
                    Navigator.pop(context);
                    showReceiptDialog(trx);
                  },
                  child: const Text('SIMPAN & NOTA'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ================= 2. HALAMAN MANAJEMEN PRODUK =================
  Widget buildProductManagementPage() {
    Map<String, int> salesCount = {};
    for (var trx in transactions) {
      for (var item in trx.items) {
        salesCount[item.product.id] = (salesCount[item.product.id] ?? 0) + item.stockDeduction;
      }
    }

    List<Product> filteredMasterProducts = products.where((prod) {
      bool matchesSearch = prod.name.toLowerCase().contains(searchMasterQuery.toLowerCase()) ||
          prod.barcode.toLowerCase().contains(searchMasterQuery.toLowerCase());
      if (productSortOption == 'Stok Kosong') return matchesSearch && prod.stock == 0;
      if (productSortOption == 'Stok Menipis') return matchesSearch && prod.stock > 0 && prod.stock < (prod.retailConversion > 1 ? prod.retailConversion : 5);
      if (productSortOption == 'Barang Sales') return matchesSearch && prod.isConsignment;
      return matchesSearch;
    }).toList();

    filteredMasterProducts.sort((a, b) {
      if (productSortOption == 'Stok Terkecil') return a.stock.compareTo(b.stock);
      if (productSortOption == 'Stok Terbesar') return b.stock.compareTo(a.stock);
      if (productSortOption == 'Paling Laku') return (salesCount[b.id] ?? 0).compareTo(salesCount[a.id] ?? 0);
      return a.name.compareTo(b.name);
    });

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF10B981),
        onPressed: () => showProductDialog(null),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: searchMasterController,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Cari stok / barcode...',
                        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF10B981)),
                        suffixIcon: searchMasterQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setState(() { searchMasterController.clear(); searchMasterQuery = ''; })) : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (val) => setState(() => searchMasterQuery = val),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: productSortOption,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                      items: const [
                        DropdownMenuItem(value: 'Default', child: Text('Urut: Default')),
                        DropdownMenuItem(value: 'Barang Sales', child: Text('🤝 Barang Sales')),
                        DropdownMenuItem(value: 'Stok Kosong', child: Text('🔴 Stok Kosong')),
                        DropdownMenuItem(value: 'Stok Menipis', child: Text('🟡 Stok Menipis')),
                        DropdownMenuItem(value: 'Stok Terkecil', child: Text('Stok Terkecil')),
                        DropdownMenuItem(value: 'Stok Terbesar', child: Text('Stok Terbesar')),
                        DropdownMenuItem(value: 'Paling Laku', child: Text('Paling Laku')),
                      ],
                      onChanged: (val) => setState(() => productSortOption = val!),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredMasterProducts.isEmpty
                ? const Center(child: Text('Barang tidak ditemukan'))
                : ListView.builder(
                    itemCount: filteredMasterProducts.length,
                    itemBuilder: (context, index) {
                      final prod = filteredMasterProducts[index];
                      Color stockColor = prod.stock == 0 ? Colors.red : (prod.stock < 10 ? Colors.amber[700]! : const Color(0xFF10B981));

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: stockColor.withOpacity(0.15),
                            child: Text(
                              '${prod.stock}',
                              style: TextStyle(color: stockColor, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              if (prod.isConsignment) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(4)),
                                  child: Text('Sales: ${prod.salesName}', style: TextStyle(fontSize: 9, color: Colors.orange[900], fontWeight: FontWeight.bold)),
                                )
                              ]
                            ],
                          ),
                          subtitle: Text(
                              'Kategori: ${prod.category} | Jual: ${currencyFormatter.format(prod.price)}\nStok: ${prod.getFormattedStock()}${prod.hasHalfPrice ? ' | 1/2: ${currencyFormatter.format(prod.halfPrice)}' : ''}${prod.hasQuarterPrice ? ' | 1/4: ${currencyFormatter.format(prod.quarterPrice)}' : ''}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 20), onPressed: () => showProductDialog(prod)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => setState(() => products.removeWhere((p) => p.id == prod.id))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void showProductDialog(Product? product, {String? initialBarcode}) {
    bool isEdit = product != null;
    TextEditingController nameCtrl = TextEditingController(text: isEdit ? product.name : '');
    TextEditingController categoryCtrl = TextEditingController(text: isEdit ? product.category : '');
    TextEditingController buyPriceCtrl = TextEditingController(text: isEdit ? product.buyPrice.toInt().toString() : '');
    TextEditingController priceCtrl = TextEditingController(text: isEdit ? product.price.toInt().toString() : '');
    TextEditingController halfPriceCtrl = TextEditingController(text: isEdit ? product.halfPrice.toInt().toString() : '');
    TextEditingController quarterPriceCtrl = TextEditingController(text: isEdit ? product.quarterPrice.toInt().toString() : '');
    TextEditingController stockCtrl = TextEditingController(text: isEdit ? product.stock.toString() : '');
    TextEditingController barcodeCtrl = TextEditingController(
      text: isEdit ? product.barcode : (initialBarcode ?? ''),
    );
    
    TextEditingController retailNameCtrl = TextEditingController(text: isEdit ? product.retailName : '');
    TextEditingController retailConvCtrl = TextEditingController(text: isEdit ? product.retailConversion.toString() : '');
    TextEditingController retailPriceCtrl = TextEditingController(text: isEdit ? product.retailPrice.toInt().toString() : '');
    
    bool isConsignment = isEdit ? product.isConsignment : false;
    TextEditingController salesNameCtrl = TextEditingController(text: isEdit ? product.salesName : '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'Edit Produk' : 'Tambah Produk Baru'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Barang Titipan Sales (Konsinyasi)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    value: isConsignment,
                    onChanged: (val) => setDialogState(() => isConsignment = val),
                  ),
                  if (isConsignment) ...[
                    TextField(controller: salesNameCtrl, decoration: const InputDecoration(labelText: 'Nama Sales / Supplier *')),
                    const SizedBox(height: 6),
                  ],
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nama Barang *')),
                  TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: 'Kategori')),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: barcodeCtrl, decoration: const InputDecoration(labelText: 'Kode Barcode'))),
                      IconButton(
                        icon: const Icon(Icons.camera_alt, color: Color(0xFF10B981)),
                        tooltip: 'Scan Barcode',
                        onPressed: () async {
                          final scanned = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
                          );
                          if (scanned != null) {
                            barcodeCtrl.text = scanned.toString();
                          }
                        },
                      ),
                    ],
                  ),
                  TextField(controller: buyPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Modal / Harga Beli (Rp)')),
                  TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual 1 Bungkus/Utuh (Rp)')),
                  TextField(controller: halfPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual 1/2 Bungkus (Rp)')),
                  TextField(controller: quarterPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual 1/4 Bungkus (Rp)')),
                  TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total Stok Awal (Satuan Terkecil/Pcs)')),
                  const Divider(height: 20),
                  const Text('--- PENGATURAN ECERAN ---', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue)),
                  TextField(controller: retailNameCtrl, decoration: const InputDecoration(labelText: 'Nama Satuan Eceran (Cth: Batang)')),
                  TextField(controller: retailConvCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Isi per Bungkus Utuh (Cth: 12)')),
                  TextField(controller: retailPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Jual Eceran (Rp)')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                onPressed: () {
                  if (nameCtrl.text.isNotEmpty) {
                    Product newProd = Product(
                      id: isEdit ? product.id : DateTime.now().millisecondsSinceEpoch.toString(),
                      name: nameCtrl.text,
                      category: categoryCtrl.text.isEmpty ? 'Umum' : categoryCtrl.text,
                      buyPrice: double.tryParse(buyPriceCtrl.text) ?? 0,
                      price: double.tryParse(priceCtrl.text) ?? 0,
                      halfPrice: double.tryParse(halfPriceCtrl.text) ?? 0,
                      quarterPrice: double.tryParse(quarterPriceCtrl.text) ?? 0,
                      stock: int.tryParse(stockCtrl.text) ?? 0,
                      retailName: retailNameCtrl.text,
                      retailConversion: int.tryParse(retailConvCtrl.text) ?? 1,
                      retailPrice: double.tryParse(retailPriceCtrl.text) ?? 0,
                      barcode: barcodeCtrl.text,
                      isConsignment: isConsignment,
                      salesName: salesNameCtrl.text,
                    );
                    setState(() {
                      if (isEdit) {
                        int idx = products.indexWhere((p) => p.id == product.id);
                        if (idx != -1) products[idx] = newProd;
                      } else {
                        products.add(newProd);
                      }
                    });
                    saveProductToGoogleSheets(newProd);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk berhasil disimpan!')));
                  }
                },
                child: const Text('Simpan'),
              )
            ],
          );
        },
      ),
    );
  }

  // ================= 3. HALAMAN KULAKAN / BELANJA ULANG =================
  Widget buildRestockPage() {
    List<Product> lowStockProducts = products.where((p) => p.stock < 10 && !p.isConsignment).toList();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFA7F3D0))),
              child: const Text(
                '💡 Fitur Kulakan: Pilih barang yang stoknya menipis/habis atau ingin dibelanjakan kembali. Stok otomatis bertambah & tercatat dalam laporan.',
                style: TextStyle(fontSize: 12, color: Color(0xFF065F46)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Daftar Produk Stok Menipis / Habis:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            Expanded(
              child: lowStockProducts.isEmpty
                  ? const Center(child: Text('Semua stok produk mandiri masih aman.'))
                  : ListView.builder(
                      itemCount: lowStockProducts.length,
                      itemBuilder: (context, index) {
                        final prod = lowStockProducts[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ListTile(
                            title: Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Stok: ${prod.getFormattedStock()}   -   Modal Satuan: ${currencyFormatter.format(prod.buyPrice)}'),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                              onPressed: () => showRestockDialog(prod),
                              icon: const Icon(Icons.add_shopping_cart, size: 16),
                              label: const Text('Kulakan'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => showRestockDialog(null),
                icon: const Icon(Icons.search, color: Color(0xFF10B981)),
                label: const Text('Cari Produk Lain untuk Kulakan', style: TextStyle(color: Color(0xFF10B981))),
              ),
            )
          ],
        ),
      ),
    );
  }

  void showRestockDialog(Product? selectedProd) {
    Product? chosenProduct = selectedProd;
    TextEditingController addStockCtrl = TextEditingController(text: '10');
    TextEditingController totalCostCtrl = TextEditingController();
    TextEditingController staffCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Form Belanja Ulang / Kulakan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chosenProduct == null) ...[
                    DropdownButtonFormField<Product>(
                      decoration: const InputDecoration(labelText: 'Pilih Produk *', border: OutlineInputBorder(), isDense: true),
                      items: products.where((p) => !p.isConsignment).map((p) => DropdownMenuItem(value: p, child: Text('${p.name} (Stok: ${p.stock})'))).toList(),
                      onChanged: (val) => setDialogState(() {
                        chosenProduct = val;
                        if (chosenProduct != null) {
                          double estCost = chosenProduct!.buyPrice * 10;
                          totalCostCtrl.text = estCost.toInt().toString();
                        }
                      }),
                    ),
                  ] else ...[
                    Text('Produk: ${chosenProduct!.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Stok Sekarang: ${chosenProduct!.getFormattedStock()}'),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: staffCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Pengelola / Kasir *', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: addStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Jumlah Tambahan Stok (Satuan Terkecil/Pcs)', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: totalCostCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Total Uang Belanja / Modal Keluar (Rp)', prefixText: 'Rp ', border: OutlineInputBorder(), isDense: true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                onPressed: () {
                  if (chosenProduct == null || staffCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih produk dan isi nama pengelola!')));
                    return;
                  }
                  int addStock = int.tryParse(addStockCtrl.text) ?? 0;
                  double totalCost = double.tryParse(totalCostCtrl.text) ?? 0;

                  if (addStock <= 0 || totalCost <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jumlah stok dan total biaya harus valid!')));
                    return;
                  }

                  setState(() {
                    chosenProduct!.stock += addStock;
                  });
                  saveProductToGoogleSheets(chosenProduct!);

                  TransactionRecord restockTrx = TransactionRecord(
                    id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                    date: DateTime.now(),
                    items: [],
                    subtotal: totalCost,
                    discount: 0,
                    tax: 0,
                    total: totalCost,
                    payAmount: totalCost,
                    change: 0,
                    customNetProfit: -totalCost,
                    itemsSummary: "Kulakan/Belanja Ulang: ${chosenProduct!.name} (+ $addStock Pcs)",
                    staffName: staffCtrl.text,
                    paymentType: 'Kulakan / Restock',
                  );
                  saveTransactionToGoogleSheets(restockTrx);
                  transactions.add(restockTrx);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Stok ${chosenProduct!.name} berhasil ditambah sebanyak $addStock Pcs!')),
                  );
                },
                child: const Text('Simpan Kulakan'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ================= 4. HALAMAN KONSINYASI / SALES =================
  Widget buildConsignmentReportPage() {
    List<Product> consignmentProducts = products.where((p) => p.isConsignment).toList();

    return Scaffold(
      body: consignmentProducts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Belum ada barang titipan sales (konsinyasi).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: consignmentProducts.length,
              itemBuilder: (context, index) {
                final prod = consignmentProducts[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(6)),
                            child: Text('Sales: ${prod.salesName}', style: TextStyle(color: Colors.orange[900], fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Text('Sisa Stok di Toko: ${prod.getFormattedStock()}', style: const TextStyle(fontSize: 13)),
                      Text('Harga Setoran: ${currencyFormatter.format(prod.buyPrice)} per utuh', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                            onPressed: () => showSalesSettlementDialog(prod),
                            icon: const Icon(Icons.sync, size: 16),
                            label: const Text('Sales Datang / Retur Ganti Baru'),
                          ),
                        ],
                      )
                    ],
                  ),
                );
              },
            ),
    );
  }

  void showSalesSettlementDialog(Product prod) {
    TextEditingController physicalStockCtrl = TextEditingController(text: prod.stock.toString());
    TextEditingController newStockCtrl = TextEditingController(text: '0');
    TextEditingController staffCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          int physicalStock = int.tryParse(physicalStockCtrl.text) ?? prod.stock;
          int soldStock = prod.stock - physicalStock;
          if (soldStock < 0) soldStock = 0;

          double buyPerSmallUnit = prod.buyPrice / (prod.retailConversion > 0 ? prod.retailConversion : 1);
          double totalPayToSales = soldStock * buyPerSmallUnit;

          int restockAmount = int.tryParse(newStockCtrl.text) ?? 0;

          return AlertDialog(
            title: Text('Kunjungan Sales: ${prod.salesName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Barang: ${prod.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Stok Tercatat di Sistem: ${prod.stock} Pcs'),
                  const Divider(height: 20),
                  TextField(controller: staffCtrl, decoration: const InputDecoration(labelText: 'Nama Kasir *', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: physicalStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Sisa Fisik Barang Sekarang', border: OutlineInputBorder()),
                    onChanged: (val) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFA7F3D0))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Estimasi Terjual:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF065F46))),
                        Text('$soldStock Pcs', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                        const SizedBox(height: 4),
                        Text('Uang Setoran ke Sales: ${currencyFormatter.format(totalPayToSales)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF047857))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: newStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Tambah Stok Baru dari Sales (Restock)', border: OutlineInputBorder()),
                    onChanged: (val) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                onPressed: () {
                  if (staffCtrl.text.isEmpty) return;

                  setState(() {
                    prod.stock = physicalStock + restockAmount;
                  });
                  saveProductToGoogleSheets(prod);

                  TransactionRecord salesTrx = TransactionRecord(
                    id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                    date: DateTime.now(),
                    items: [],
                    subtotal: totalPayToSales,
                    discount: 0,
                    tax: 0,
                    total: totalPayToSales,
                    payAmount: totalPayToSales,
                    change: 0,
                    customNetProfit: 0,
                    itemsSummary: "Setoran Sales [${prod.salesName}] - ${prod.name} (Terjual: $soldStock)",
                    staffName: staffCtrl.text,
                    paymentType: 'Setoran Sales Titipan',
                  );
                  saveTransactionToGoogleSheets(salesTrx);
                  transactions.add(salesTrx);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Setoran ke sales berhasil dicatat!')));
                },
                child: const Text('Selesaikan & Bayar Sales'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ================= 5. HALAMAN KASBON =================
  Widget buildDebtPage() {
    Map<String, List<DebtRecord>> groupedDebts = {};
    for (var d in debts) {
      String nameKey = d.customerName.trim().toUpperCase();
      if (!groupedDebts.containsKey(nameKey)) {
        groupedDebts[nameKey] = [];
      }
      groupedDebts[nameKey]!.add(d);
    }

    double totalActiveDebts = debts.where((d) => d.status != 'Lunas').fold(0, (sum, d) => sum + d.remainingAmount);

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
            child: Column(
              children: [
                const Text('Total Sisa Piutang Warung', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                const SizedBox(height: 4),
                Text(currencyFormatter.format(totalActiveDebts), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red[800])),
              ],
            ),
          ),
          Expanded(
            child: groupedDebts.isEmpty
                ? const Center(child: Text('Belum ada data kasbon.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: groupedDebts.keys.length,
                    itemBuilder: (context, index) {
                      String custName = groupedDebts.keys.elementAt(index);
                      List<DebtRecord> custDebts = groupedDebts[custName]!;
                      
                      double custTotalDebt = custDebts.where((d) => d.status != 'Lunas').fold(0, (sum, d) => sum + d.remainingAmount);
                      bool isAllLunas = custTotalDebt == 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: isAllLunas ? const Color(0xFFECFDF5) : Colors.red[50],
                            child: Icon(isAllLunas ? Icons.check : Icons.person, color: isAllLunas ? const Color(0xFF10B981) : Colors.red),
                          ),
                          title: Text(custName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: Text('Sisa Utang: ${currencyFormatter.format(custTotalDebt)} (${custDebts.length} Nota Kasbon)',
                              style: TextStyle(color: isAllLunas ? Colors.green[700] : Colors.red[700], fontWeight: FontWeight.w500, fontSize: 12)),
                          children: [
                            Container(
                              color: const Color(0xFFF8FAFC),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('--- RINCIAN PIUTANG PELANGGAN ---', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                                  const SizedBox(height: 8),
                                  ...custDebts.map((d) => Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(8)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text('📅 ${DateFormat('dd/MM/yyyy HH:mm').format(d.date)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                                Text(d.status, style: TextStyle(color: d.status == 'Lunas' ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                                              ],
                                            ),
                                            Text('Kasir: ${d.staffName}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                            const Divider(height: 12),
                                            Text('Barang:\n${d.itemsSummary}', style: const TextStyle(fontSize: 12)),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text('Total Nota: ${currencyFormatter.format(d.totalAmount)}', style: const TextStyle(fontSize: 11)),
                                                Text('Sisa: ${currencyFormatter.format(d.remainingAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 11)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      )),
                                  const Divider(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      if (!isAllLunas)
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                                          onPressed: () => showGroupSettlementDialog(custName, custDebts, custTotalDebt),
                                          icon: const Icon(Icons.payment, size: 16),
                                          label: const Text('Bayar Cicil/Lunas'),
                                        ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                        onPressed: () => generateAndSharePDF(custName, custDebts, custTotalDebt),
                                        icon: const Icon(Icons.share, size: 16),
                                        label: const Text('Kirim PDF WA'),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void showGroupSettlementDialog(String custName, List<DebtRecord> custDebts, double totalDebt) {
    TextEditingController payCtrl = TextEditingController(text: totalDebt.toString());
    TextEditingController staffCtrl = TextEditingController();
    String paymentType = 'Tunai';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double payAmount = double.tryParse(payCtrl.text) ?? 0;

          return AlertDialog(
            title: Text('Pelunasan Utang - $custName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total Sisa Utang: ${currencyFormatter.format(totalDebt)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 12),
                  TextField(controller: staffCtrl, decoration: const InputDecoration(labelText: 'Nama Kasir Penerima *', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: paymentType,
                    decoration: const InputDecoration(labelText: 'Metode Pembayaran', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'Tunai', child: Text('💵 Tunai')),
                      DropdownMenuItem(value: 'QRIS', child: Text('📱 QRIS (Non-Tunai)')),
                    ],
                    onChanged: (val) => setDialogState(() {
                      paymentType = val!;
                      if (paymentType == 'QRIS') payCtrl.text = totalDebt.toString();
                    }),
                  ),
                  const SizedBox(height: 8),
                  if (paymentType == 'QRIS') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                      child: Column(
                        children: [
                          const Text('Scan QRIS Pelunasan Utang (Tap untuk Zoom)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.black,
                                  child: InteractiveViewer(
                                    panEnabled: true,
                                    boundaryMargin: const EdgeInsets.all(20),
                                    minScale: 0.5,
                                    maxScale: 4,
                                    child: Image.asset(
                                      'assets/images/qris.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              );
                            },
                            child: Image.asset(
                              'assets/images/qris.png',
                              width: 180,
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('Nominal: ${currencyFormatter.format(payAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (paymentType != 'QRIS') ...[
                    TextField(
                      controller: payCtrl, 
                      keyboardType: TextInputType.number, 
                      decoration: const InputDecoration(labelText: 'Jumlah Pembayaran (Rp)', prefixText: 'Rp ', border: OutlineInputBorder()), 
                      onChanged: (val) => setDialogState(() {}),
                    ),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                onPressed: () {
                  if (staffCtrl.text.isEmpty) return;
                  double finalPayAmount = paymentType == 'QRIS' ? totalDebt : (double.tryParse(payCtrl.text) ?? 0);
                  if (finalPayAmount <= 0) return;

                  double remainingPay = finalPayAmount;

                  setState(() {
                    for (var d in custDebts) {
                      if (d.status != 'Lunas' && remainingPay > 0) {
                        if (remainingPay >= d.remainingAmount) {
                          remainingPay -= d.remainingAmount;
                          d.paidAmount += d.remainingAmount;
                          d.remainingAmount = 0;
                          d.status = 'Lunas';
                        } else {
                          d.paidAmount += remainingPay;
                          d.remainingAmount -= remainingPay;
                          remainingPay = 0;
                        }
                        d.settlementHistory += "${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}: Bayar via $paymentType ${currencyFormatter.format(finalPayAmount)} (${staffCtrl.text})\n";
                        saveDebtToGoogleSheets(d);
                      }
                    }
                  });

                  TransactionRecord settlementTrx = TransactionRecord(
                    id: DateTime.now().millisecondsSinceEpoch.toString().substring(7),
                    date: DateTime.now(),
                    items: [],
                    subtotal: finalPayAmount,
                    discount: 0,
                    tax: 0,
                    total: finalPayAmount,
                    payAmount: finalPayAmount,
                    change: 0,
                    customNetProfit: finalPayAmount,
                    itemsSummary: "Pelunasan Piutang ($paymentType): $custName",
                    staffName: staffCtrl.text,
                    paymentType: 'Pelunasan Kasbon ($paymentType)',
                  );
                  saveTransactionToGoogleSheets(settlementTrx);
                  transactions.add(settlementTrx);

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran berhasil dicatat!')));
                },
                child: const Text('Simpan'),
              )
            ],
          );
        },
      ),
    );
  }

  Future<void> generateAndSharePDF(String custName, List<DebtRecord> custDebts, double totalDebt) async {
    final pdf = pw.Document();
    final ByteData logoBytes = await rootBundle.load('assets/images/logo.png');
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Center(
                child: pw.Opacity(
                  opacity: 0.08,
                  child: pw.Image(logoImage, width: 320, height: 320),
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Image(logoImage, width: 50, height: 50),
                        pw.SizedBox(height: 4),
                        pw.Text('WARUNG BAROKAH KIARAJANGKUNG', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Sukahening, Tasikmalaya | Struk Piutang / Kasbon', style: const pw.TextStyle(fontSize: 10)),
                        pw.Divider(thickness: 1),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text('Rincian Piutang / Kasbon Pelanggan:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Text('Nama Pelanggan: $custName', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Tanggal Cetak  : ${DateFormat('dd MMMM yyyy HH:mm', 'id_ID').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 12),
                  pw.Table.fromTextArray(
                    headers: ['Tanggal', 'Kasir', 'Rincian Barang', 'Total', 'Sisa Utang'],
                    data: custDebts.map((d) => [
                      DateFormat('dd/MM/yy HH:mm').format(d.date),
                      d.staffName,
                      d.itemsSummary,
                      currencyFormatter.format(d.totalAmount),
                      currencyFormatter.format(d.remainingAmount),
                    ]).toList(),
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                    cellStyle: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.Divider(),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL SISA PIUTANG:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      pw.Text(currencyFormatter.format(totalDebt), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.red)),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Center(child: pw.Text('Terima Kasih Atas Kepercayaannya!', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10))),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Nota_Piutang_$custName.pdf');
  }

  Future<void> generateAndShareTransactionPDF(TransactionRecord trx) async {
    final pdf = pw.Document();
    final ByteData logoBytes = await rootBundle.load('assets/images/logo.png');
    final pw.MemoryImage logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Center(
                child: pw.Opacity(
                  opacity: 0.10,
                  child: pw.Image(logoImage, width: 180, height: 180),
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Column(
                      children: [
                        pw.Image(logoImage, width: 40, height: 40),
                        pw.SizedBox(height: 2),
                        pw.Text('WARUNG BAROKAH', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        pw.Text('KIARAJANGKUNG', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Sukahening, Tasikmalaya', style: const pw.TextStyle(fontSize: 8)),
                        pw.Divider(thickness: 1),
                      ],
                    ),
                  ),
                  pw.Text('No Nota : #${trx.id}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Tanggal : ${DateFormat('dd/MM/yy HH:mm').format(trx.date)}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Kasir   : ${trx.staffName}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Metode  : ${trx.paymentType}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Divider(thickness: 0.5),
                  if (trx.items.isNotEmpty)
                    ...trx.items.map((item) => pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('${item.product.name} (${item.quantity} ${item.unitLabel})', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text(currencyFormatter.format(item.totalPrice), style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ))
                  else
                    pw.Text('Items: ${trx.itemsSummary}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Divider(thickness: 0.5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Belanja:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text(currencyFormatter.format(trx.total), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Bayar:', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(currencyFormatter.format(trx.payAmount), style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Kembali:', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(currencyFormatter.format(trx.change), style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Center(child: pw.Text('Terima Kasih Atas Kunjungan Anda!', style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic))),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Struk_Nota_${trx.id}.pdf');
  }

  // ================= 6. HALAMAN LAPORAN =================
  Widget buildHistoryPage() {
    DateTime now = DateTime.now();

    double dailyOmsetCash = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day && t.paymentType != 'Kasbon Penuh').fold(0, (s, t) => s + t.payAmount);
    double dailyNewDebt = debts.where((d) => d.date.year == now.year && d.date.month == now.month && d.date.day == now.day).fold(0, (s, d) => s + d.remainingAmount);
    double dailyProfit = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day).fold(0, (s, t) => s + t.netProfit);
    int dailyCount = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day).length;

    double monthlyOmsetCash = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.paymentType != 'Kasbon Penuh').fold(0, (s, t) => s + t.payAmount);
    double monthlyProfit = transactions.where((t) => t.date.year == now.year && t.date.month == now.month).fold(0, (s, t) => s + t.netProfit);
    int monthlyCount = transactions.where((t) => t.date.year == now.year && t.date.month == now.month).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFA7F3D0))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📅 Rekap Hari Ini (${DateFormat('dd MMM yyyy').format(now)})', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF065F46))),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [const Text('Uang Masuk', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(dailyOmsetCash), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF047857)))]),
                    Column(children: [const Text('Piutang Baru', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(dailyNewDebt), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red))]),
                    Column(children: [const Text('Laba Bersih', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(dailyProfit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue))]),
                  ],
                ),
                const SizedBox(height: 6),
                Center(child: Text('$dailyCount Aktivitas Transaksi', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade200)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📊 Rekap Bulan Ini (${DateFormat('MMMM yyyy', 'id_ID').format(now)})', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900])),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [const Text('Total Uang Masuk', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(monthlyOmsetCash), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF047857)))]),
                    Column(children: [const Text('Laba Bersih', style: TextStyle(fontSize: 11)), Text(currencyFormatter.format(monthlyProfit), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue))]),
                  ],
                ),
                const SizedBox(height: 6),
                Center(child: Text('$monthlyCount Transaksi', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey))),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Align(alignment: Alignment.centerLeft, child: Text('Daftar Riwayat Penjualan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)))),
          ),
          transactions.isEmpty
              ? const Padding(padding: EdgeInsets.all(32.0), child: Center(child: Text('Belum ada transaksi')))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final trx = transactions[transactions.length - 1 - index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ListTile(
                        title: Text('Nota #${trx.id} [${trx.paymentType}]', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('Tgl: ${DateFormat('dd/MM/yy HH:mm').format(trx.date)} | Kasir: ${trx.staffName}\nItem: ${trx.itemsSummary}', style: const TextStyle(fontSize: 12)),
                        trailing: Text(currencyFormatter.format(trx.total), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        onTap: () => showReceiptDialog(trx),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  void showReceiptDialog(TransactionRecord trx) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.08,
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/logo.png', width: 45, height: 45),
                  const SizedBox(height: 4),
                  const Text('WARUNG BAROKAH KIARAJANGKUNG', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Text('Kiarajangkung, Sukahening, Tasikmalaya', textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
                  const Divider(),
                  Text('No: #${trx.id} | ${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}\nKasir: ${trx.staffName} | Tipe: ${trx.paymentType}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                  const Divider(),
                  if (trx.items.isNotEmpty)
                    ...trx.items.map((item) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${item.product.name} (${item.quantity} ${item.unitLabel})', style: const TextStyle(fontSize: 12)),
                            Text(currencyFormatter.format(item.totalPrice), style: const TextStyle(fontSize: 12)),
                          ],
                        ))
                  else
                    Text('Rincian: ${trx.itemsSummary}', style: const TextStyle(fontSize: 11)),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total:'), Text(currencyFormatter.format(trx.total), style: const TextStyle(fontWeight: FontWeight.bold))]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Bayar:'), Text(currencyFormatter.format(trx.payAmount))]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Kembali:'), Text(currencyFormatter.format(trx.change))]),
                  const SizedBox(height: 10),
                  const Text('Terima Kasih!', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              printReceiptViaBluetooth(trx);
            },
            icon: const Icon(Icons.print, size: 16),
            label: const Text('Cetak Bluetooth'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              generateAndShareTransactionPDF(trx);
            },
            icon: const Icon(Icons.share, size: 16),
            label: const Text('Kirim PDF WA'),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> printReceiptViaBluetooth(TransactionRecord trx) async {
    try {
      List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      if (devices.isEmpty) return;
      bool status = await PrintBluetoothThermal.connect(macPrinterAddress: devices.first.macAdress);
      if (status) {
        String receiptText = "       WARUNG BAROKAH\n       KIARAJANGKUNG\n--------------------------------\n"
            "No : #${trx.id}\nTgl: ${DateFormat('dd/MM/yy HH:mm').format(trx.date)}\nKasir: ${trx.staffName}\nTipe : ${trx.paymentType}\n--------------------------------\n";
        for (var item in trx.items) {
          receiptText += "${item.product.name} (${item.quantity} ${item.unitLabel})\n  = ${currencyFormatter.format(item.totalPrice)}\n";
        }
        receiptText += "--------------------------------\nTotal   : ${currencyFormatter.format(trx.total)}\nBayar   : ${currencyFormatter.format(trx.payAmount)}\nKembali : ${currencyFormatter.format(trx.change)}\n--------------------------------\n Terimakasih Atas Kunjungan Anda\n\n\n";
        await PrintBluetoothThermal.writeString(printText: PrintTextSize(size: 1, text: receiptText));
        await PrintBluetoothThermal.disconnect;
      }
    } catch (e) {
      print("Error cetak: $e");
    }
  }
}

class BarcodeScannerScreen extends StatelessWidget {
  const BarcodeScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode Produk'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue);
              break;
            }
          }
        },
      ),
    );
  }
}


// ============================================================================
// MODUL PANGKALAN LPG - data terpisah dari POS Warung
// ============================================================================

const List<String> lpgVariants = ['LPG 3 kg', 'LPG 5,5 kg', 'LPG 12 kg'];
const List<String> lpgAgents = ['PT. Mutiara Sri Rengganis', 'PT. Petro Lindo Jaya Utama'];


// =============================================================
// MODUL JUAL BELI GABAH / PADI - versi operasional
// Semua data disimpan pada sheet MOD_GABAH melalui endpoint modul usaha.
// =============================================================
class GabahModuleScreen extends StatefulWidget {
  final String apiUrl;
  const GabahModuleScreen({super.key, required this.apiUrl});
  @override
  State<GabahModuleScreen> createState() => _GabahModuleScreenState();
}

class _GabahModuleScreenState extends State<GabahModuleScreen> {
  static const Color green = Color(0xFF10B981);
  static const List<String> varieties = ['Panjang', 'Bulat', 'Ketan', 'Merah'];
  static const List<String> invoiceModes = [
    'Semua jenis terpisah',
    'Panjang + Bulat digabung; Ketan & Merah terpisah',
    'Panjang + Bulat + Merah digabung; Ketan terpisah',
  ];
  final NumberFormat money = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final NumberFormat kg = NumberFormat('#,##0.##', 'id_ID');
  final List<Map<String, dynamic>> data = [];
  bool loading = false;
  String error = '';
  int tab = 0;
  DateTime reportDate = DateTime.now();
  bool monthly = false;

  final List<String> tabs = const [
    'Ringkasan', 'Petani', 'Pengepul', 'Harga', 'Pengiriman', 'Pembayaran', 'Stok & Karung', 'Biaya', 'Laporan'
  ];

  @override
  void initState() { super.initState(); _load(); }

  double n(dynamic v) {
    if (v is num) return v.toDouble();
    var s = '${v ?? 0}'.trim().replaceAll(' ', '');
    if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(s) ?? 0;
  }
  String id(String p) => '$p-${DateTime.now().millisecondsSinceEpoch}';
  Map<String, dynamic> extra(Map<String, dynamic> r) {
    final v = r['extra'];
    if (v is Map) return Map<String, dynamic>.from(v);
    try { final x = jsonDecode(v?.toString() ?? '{}'); if (x is Map) return Map<String, dynamic>.from(x); } catch (_) {}
    return <String, dynamic>{};
  }
  List<Map<String, dynamic>> get rows => data.map((r) => <String, dynamic>{...r, ...extra(r)}).toList();
  List<Map<String, dynamic>> of(String type) => rows.where((r) => r['type'] == type && r['voided'] != true).toList();
  double sum(String type, String key) => of(type).fold(0.0, (a, r) => a + n(r[key]));
  double get farmerAdvance => sum('PETANI_PINJAMAN', 'amount');
  double get farmerPurchase => sum('PETANI_PEMBELIAN', 'purchaseValue');
  double get shipmentRevenue => sum('PENGIRIMAN', 'grossValue');
  double get expenses => sum('BIAYA', 'amount');
  double get factoryAdvanceBalance => sum('MODAL_PABRIK', 'amount') - sum('PEMBAYARAN_PABRIK', 'advanceDeduction');
  double get stockKg => varieties.fold(0.0, (a, v) => a + stockFor(v));

  Future<void> _load() async {
    if (mounted) setState(() { loading = true; error = ''; });
    try {
      final uri = Uri.parse('${widget.apiUrl}?action=getModuleData&module=GABAH');
      final res = await http.get(uri).timeout(const Duration(seconds: 35));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final decoded = jsonDecode(res.body);
      if (decoded is! List) throw Exception('Format data MOD_GABAH tidak valid');
      data..clear()..addAll(decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    } catch (e) { error = e.toString(); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _post(Map<String, dynamic> payload) async {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse(widget.apiUrl))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(payload);
      var res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 40)));
      if (res.statusCode >= 300 && res.statusCode < 400) {
        final loc = res.headers['location'];
        if (loc == null || loc.isEmpty) throw Exception('HTTP ${res.statusCode}: alamat redirect tidak ditemukan');
        res = await client.get(Uri.parse(loc)).timeout(const Duration(seconds: 40));
      }
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}: ${res.body}');
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['status'] == 'error') throw Exception(decoded['message'] ?? 'Permintaan gagal');
    } finally { client.close(); }
  }

  Future<String> _save({String? recordId, required String type, required String party,
    required String description, double qty = 0, String unit = 'kg', double buyPrice = 0,
    double sellPrice = 0, required double total, String payment = '-', String status = 'Tersimpan',
    required Map<String, dynamic> extraData, String? date}) async {
    final rid = recordId ?? id('GBH');
    final merged = <String, dynamic>{...extraData, 'id': rid, 'type': type, 'party': party,
      'description': description, 'total': total, 'payment': payment, 'status': status};
    await _post({'action': 'saveModuleRecord', 'module': 'GABAH', 'id': rid,
      'date': date ?? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      'type': type, 'party': party, 'description': description, 'qty': qty, 'unit': unit,
      'buyPrice': buyPrice, 'sellPrice': sellPrice, 'total': total, 'payment': payment,
      'status': status, 'extra': jsonEncode(merged)});
    await _load();
    return rid;
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Hapus data?'), content: Text('Data ${r['id']} akan dihapus permanen.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Hapus'))]));
    if (ok != true) return;
    try { await _post({'action': 'deleteModuleRecord', 'module': 'GABAH', 'id': r['id']}); await _load(); }
    catch (e) { _msg('Gagal menghapus: $e'); }
  }

  void _msg(String s) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s))); }
  InputDecoration _dec(String s) => InputDecoration(labelText: s, border: const OutlineInputBorder(), isDense: true);
  TextEditingController _ctl(dynamic v) => TextEditingController(text: v == null ? '' : '$v');
  Widget _field(TextEditingController c, String label, {bool numeric = false, int lines = 1}) => TextField(
    controller: c, maxLines: lines, keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
    decoration: _dec(label));

  double farmerDebt(String farmer) {
    final loans = of('PETANI_PINJAMAN').where((r) => '${r['party']}' == farmer).fold(0.0, (a,r)=>a+n(r['amount']));
    final repayments = of('PETANI_PEMBAYARAN').where((r) => '${r['party']}' == farmer && r['balanceType']=='PINJAMAN').fold(0.0,(a,r)=>a+n(r['amount']));
    final offsets = of('PETANI_PEMBELIAN').where((r) => '${r['party']}' == farmer).fold(0.0,(a,r)=>a+n(r['loanOffset']));
    return (loans - repayments - offsets).clamp(0.0, double.infinity).toDouble();
  }
  double farmerPayable(String farmer) {
    final purchases = of('PETANI_PEMBELIAN').where((r) => '${r['party']}' == farmer).fold(0.0,(a,r)=>a+n(r['purchaseValue'])-n(r['loanOffset']));
    final paid = of('PETANI_PEMBAYARAN').where((r) => '${r['party']}' == farmer && r['balanceType']=='PEMBELIAN').fold(0.0,(a,r)=>a+n(r['amount']));
    return (purchases-paid).clamp(0.0,double.infinity).toDouble();
  }
  double collectorCapital(String name) => of('PENGEPUL_MODAL').where((r)=>'${r['party']}'==name).fold(0.0,(a,r)=>a+n(r['amount']));
  double collectorValue(String name) => of('PENGEPUL_PADI').where((r)=>'${r['party']}'==name).fold(0.0,(a,r)=>a+n(r['value']));
  double collectorPaid(String name) => of('PENGEPUL_PEMBAYARAN').where((r)=>'${r['party']}'==name).fold(0.0,(a,r)=>a+n(r['amount']));
  double collectorOwed(String name) => (collectorCapital(name)-collectorValue(name)-collectorPaid(name)).clamp(0.0,double.infinity).toDouble();
  double sacksOut(String name) => of('KARUNG_KELUAR').where((r)=>'${r['party']}'==name).fold(0.0,(a,r)=>a+n(r['count'])) - of('KARUNG_KEMBALI').where((r)=>'${r['party']}'==name).fold(0.0,(a,r)=>a+n(r['count']));
  double stockFor(String v) {
    final bought = of('PETANI_PEMBELIAN').where((r)=>'${r['variety']}'==v).fold(0.0,(a,r)=>a+n(r['netKg']));
    final dispatchedFarmers = of('PENGIRIMAN').fold(0.0,(a,r) {
      final allocations = (r['allocations'] is List) ? (r['allocations'] as List) : <dynamic>[];
      return a + allocations.whereType<Map>().where((x)=>x['sourceType']=='PETANI' && x['variety']==v).fold(0.0,(b,x)=>b+n(x['initialKg']));
    });
    return bought-dispatchedFarmers;
  }

  Future<void> _simpleForm({required String title, required String type, Map<String,dynamic>? old,
    required List<String> labels, required List<String> keys, String unit='kg', String priceKey='price',
    String totalKey='total', String status='Tersimpan', String partyLabel='Nama'}) async {
    final x = old == null ? <String,dynamic>{} : <String,dynamic>{...old};
    final ctrls = <String,TextEditingController>{};
    for (var i=0;i<labels.length;i++) { final k=keys[i]; ctrls[k]=_ctl(x[k] ?? (k=='date'?DateFormat('yyyy-MM-dd').format(DateTime.now()):'')); }
    String method = '${x['payment'] ?? 'Tunai'}';
    String selected = '${x['variety'] ?? varieties.first}';
    String? mode = x['invoiceMode']?.toString();
    final result = await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:Text(title), content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(var i=0;i<labels.length;i++) Padding(padding:const EdgeInsets.only(bottom:10),child:_field(ctrls[keys[i]]!,labels[i],numeric:const ['amount','qty','count','kg','price','total','paid','weight','cash','transfer','deduction','loanOffset','initialKg','factoryKg','advanceDeduction'].contains(keys[i]))),
        if(keys.contains('variety')) DropdownButtonFormField<String>(value:varieties.contains(selected)?selected:varieties.first,decoration:_dec('Jenis gabah'),items:varieties.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>selected=v??varieties.first)),
        if(keys.contains('invoiceMode')) DropdownButtonFormField<String>(value:invoiceModes.contains(mode)?mode:invoiceModes.first,decoration:_dec('Pola harga nota pabrik'),items:invoiceModes.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>mode=v)),
        if(keys.contains('payment')) DropdownButtonFormField<String>(value:['Tunai','Transfer','Tunai + Transfer','Potong modal pabrik','Tunai + potongan','Transfer + potongan','Lainnya'].contains(method)?method:'Tunai',decoration:_dec('Metode pembayaran'),items:['Tunai','Transfer','Tunai + Transfer','Potong modal pabrik','Tunai + potongan','Transfer + potongan','Lainnya'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>method=v??'Tunai')),
      ])), actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Simpan'))])));
    if(result==true){
      final m=<String,dynamic>{}; for(final k in keys){m[k]=ctrls[k]!.text.trim();}
      if(keys.contains('variety'))m['variety']=selected;
      if(keys.contains('invoiceMode'))m['invoiceMode']=mode??invoiceModes.first;
      if(keys.contains('payment'))m['payment']=method;
      if(type=='PETANI_PEMBAYARAN')m['balanceType']='PINJAMAN';
      final party = '${m['party'] ?? m['name'] ?? m['factory'] ?? m['description'] ?? 'Tanpa nama'}';
      final amount = type == 'PEMBAYARAN_PABRIK' ? n(m['cash']) + n(m['transfer']) + n(m['advanceDeduction']) + n(m['deduction']) : n(m['amount'] ?? m['total'] ?? m['value'] ?? m['purchaseValue']);
      final qty = n(m['qty'] ?? m['count'] ?? m['netKg'] ?? m['weight'] ?? m['factoryKg']);
      try {
        await _save(recordId:old?['id']?.toString(),type:type,party:party,description:'${m['description'] ?? title}',qty:qty,unit:unit,
          buyPrice:n(m['price']),sellPrice:n(m['sellPrice']),total:amount,payment:method,status:status,
          extraData:{...m,'variety':m['variety']??selected,'date':m['date']??DateFormat('yyyy-MM-dd').format(DateTime.now())});
        _msg('Data berhasil disimpan.');
      } catch(e){_msg('Gagal menyimpan: $e');}
    }
    for(final c in ctrls.values){c.dispose();}
  }

  Future<void> _farmerAdvance({Map<String,dynamic>? old}) => _simpleForm(title:old==null?'Catat pinjaman petani':'Edit pinjaman petani',type:'PETANI_PINJAMAN',old:old,
    labels:['Nama petani','Jumlah uang dipinjamkan (Rp)','Tanggal','Catatan'],keys:['party','amount','date','description'],unit:'Rp');
  Future<void> _farmerPurchase({Map<String,dynamic>? old}) async {
    final x=old??{}; final party=_ctl(x['party']); final gross=_ctl(x['grossKg']); final sack=_ctl(x['sackKg']); final price=_ctl(x['price']); final paid=_ctl(x['paid']); final offset=_ctl(x['loanOffset']); final note=_ctl(x['note']);
    String variety='${x['variety']??varieties.first}'; String method='${x['payment']??'Tunai'}';
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:Text(old==null?'Pembelian gabah petani':'Edit pembelian gabah'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      _field(party,'Nama petani'),DropdownButtonFormField<String>(value:varieties.contains(variety)?variety:varieties.first,decoration:_dec('Jenis gabah'),items:varieties.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>variety=v??varieties.first)),const SizedBox(height:10),
      _field(gross,'Berat timbangan awal (kg)',numeric:true),const SizedBox(height:10),_field(sack,'Berat karung (kg)',numeric:true),const SizedBox(height:10),_field(price,'Harga per kg saat timbang (Rp)',numeric:true),const SizedBox(height:10),_field(offset,'Potong pinjaman lama (Rp)',numeric:true),const SizedBox(height:10),_field(paid,'Dibayar sekarang (Rp)',numeric:true),const SizedBox(height:10),_field(note,'Catatan'),const SizedBox(height:10),
      DropdownButtonFormField<String>(value:['Tunai','Transfer','Sebagian','Dibayar setelah dari pabrik'].contains(method)?method:'Tunai',decoration:_dec('Cara pembayaran'),items:['Tunai','Transfer','Sebagian','Dibayar setelah dari pabrik'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>method=v??'Tunai'))
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Simpan'))])));
    if(ok==true){final net=n(gross.text)-n(sack.text), value=net*n(price.text), off=n(offset.text), p=n(paid.text); if(p+off>value||net<=0||party.text.trim().isEmpty||n(price.text)<=0){_msg('Periksa nama, berat netto, harga, dan jumlah pembayaran/potongan.');}else{try{final savedId=await _save(recordId:old?['id']?.toString(),type:'PETANI_PEMBELIAN',party:party.text.trim(),description:'Pembelian ${variety.toLowerCase()} dari petani',qty:net,buyPrice:n(price.text),total:value,payment:method,status:p+off>=value?'Lunas':p+off>0?'Dibayar sebagian':'Belum dibayar',extraData:{'variety':variety,'grossKg':n(gross.text),'sackKg':n(sack.text),'netKg':net,'price':n(price.text),'purchaseValue':value,'loanOffset':off,'paid':p,'note':note.text,'payment':method,'payments':[if(off>0){'date':DateTime.now().toIso8601String(),'amount':off,'method':'Potong pinjaman'},if(p>0){'date':DateTime.now().toIso8601String(),'amount':p,'method':method}],'remaining':(value-off-p).clamp(0.0,double.infinity)});if(p+off>=value){final fresh=rows.firstWhere((z)=>'${z['id']}'==savedId,orElse:()=>{});if(fresh.isNotEmpty){await _shareSettlementReceipt(fresh);}}_msg('Pembelian tersimpan.');}catch(e){_msg('Gagal: $e');}}}
    party.dispose();gross.dispose();sack.dispose();price.dispose();paid.dispose();offset.dispose();note.dispose();
  }

  Future<void> _collectorPaddy({Map<String,dynamic>? old}) async {
    final party=_ctl(old?['party']);final factoryKg=_ctl(old?['factoryKg']);final price=_ctl(old?['price']);final color=_ctl(old?['raffiaColor']);final note=_ctl(old?['note']);String variety='${old?['variety']??varieties.first}';
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:Text(old==null?'Catat gabah pengepul (hasil timbang pabrik)':'Edit gabah pengepul'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[_field(party,'Nama pengepul'),DropdownButtonFormField<String>(value:varieties.contains(variety)?variety:varieties.first,decoration:_dec('Jenis gabah'),items:varieties.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>variety=v??varieties.first)),const SizedBox(height:10),_field(factoryKg,'Berat hasil timbangan pabrik (kg)',numeric:true),const SizedBox(height:10),_field(price,'Harga pengepul per kg (Rp)',numeric:true),const SizedBox(height:10),_field(color,'Warna tali rafia untuk pengiriman ini'),const SizedBox(height:10),_field(note,'Catatan') ])),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Simpan'))])));
    if(ok==true){final value=n(factoryKg.text)*n(price.text);try{await _save(recordId:old?['id']?.toString(),type:'PENGEPUL_PADI',party:party.text.trim(),description:'Gabah pengepul hasil timbang pabrik',qty:n(factoryKg.text),buyPrice:n(price.text),total:value,extraData:{'variety':variety,'factoryKg':n(factoryKg.text),'price':n(price.text),'value':value,'raffiaColor':color.text,'note':note.text});_msg('Hasil timbang pengepul tersimpan.');}catch(e){_msg('Gagal: $e');}}
    party.dispose();factoryKg.dispose();price.dispose();color.dispose();note.dispose();
  }

  Future<void> _recordPayment(Map<String,dynamic> r) async {
    final x=extra(r); final type='${r['type']}';
    double due=0; String balanceType='PEMBELIAN';
    if(type=='PETANI_PEMBELIAN'){due=n(x['purchaseValue'])-n(x['loanOffset'])-n(x['paid']);balanceType='PEMBELIAN';}
    else if(type=='PENGIRIMAN'){due=n(x['grossValue'])-n(x['paid']);balanceType='PABRIK';}
    else if(type=='PENGEPUL_PADI'){due=collectorOwed('${r['party']}');balanceType='PENGEPUL';}
    else {due=n(r['total'])-n(x['paid']);}
    if(due<=0){_msg('Transaksi ini sudah lunas.');return;}
    final amount=_ctl(due); String method='Tunai';
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:Text('Catat pembayaran • ${r['party']}'),content:Column(mainAxisSize:MainAxisSize.min,children:[Text('Sisa kewajiban: ${money.format(due)}'),const SizedBox(height:10),_field(amount,'Jumlah dibayar (Rp)',numeric:true),const SizedBox(height:10),DropdownButtonFormField<String>(value:method,decoration:_dec('Metode'),items:['Tunai','Transfer','Tunai + Transfer','Potongan'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>method=v??'Tunai'))]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Simpan pembayaran'))])));
    if(ok==true){final paid=n(amount.text);if(paid<=0||paid>due){_msg('Jumlah pembayaran tidak valid.');}else{final payments=List<Map<String,dynamic>>.from((x['payments'] is List?x['payments']:[]).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)));payments.add({'date':DateTime.now().toIso8601String(),'amount':paid,'method':method});final newPaid=n(x['paid'])+paid;final newDue=due-paid;
      x['payments']=payments;final newStatus=newDue<=0?'Lunas':'Dibayar sebagian';
      try{
        if(type=='PENGEPUL_PADI'){
          await _save(type:'PENGEPUL_PEMBAYARAN',party:'${r['party']}',description:'Pembayaran pengepul untuk ${r['id']}',total:paid,payment:method,status:newStatus,extraData:{'amount':paid,'sourceRecordId':r['id'],'date':DateTime.now().toIso8601String()});
        } else {
          if(type=='PETANI_PEMBELIAN'){x['paid']=newPaid;x['remaining']=(n(x['purchaseValue'])-n(x['loanOffset'])-newPaid).clamp(0.0,double.infinity);}
          else if(type=='PENGIRIMAN'){x['paid']=newPaid;x['remaining']=(n(x['grossValue'])-newPaid).clamp(0.0,double.infinity);}
          await _save(recordId:'${r['id']}',type:type,party:'${r['party']}',description:'${r['description']}',qty:n(r['qty']),buyPrice:n(r['buy_price']),sellPrice:n(r['sell_price']),total:n(r['total']),payment:method,status:newStatus,extraData:x,date:'${r['date']}');
          if(newDue<=0){final fresh=rows.firstWhere((z)=>'${z['id']}'=='${r['id']}',orElse:()=>{...r,...x,'status':'Lunas'});await _shareSettlementReceipt(fresh);}
        }
        _msg(newDue<=0?'Pelunasan selesai. Nota PDF siap dibagikan.':'Pembayaran sebagian tersimpan.');
      }catch(e){_msg('Gagal mencatat pembayaran: $e');}
    }} amount.dispose();
  }

  Future<void> _shareSettlementReceipt(Map<String,dynamic> r) async {
    final x=extra(r); final pdf=pw.Document(); final payments=(x['payments'] is List?x['payments']:[]).whereType<Map>().toList();
    final total=n(x['purchaseValue']??x['grossValue']??r['total']); final paid=n(x['paid'])+n(x['loanOffset']);
    pdf.addPage(pw.Page(pageFormat:PdfPageFormat.a5,build:(ctx)=>pw.Padding(padding:const pw.EdgeInsets.all(22),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
      pw.Center(child:pw.Text('NOTA PELUNASAN',style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold))),pw.SizedBox(height:8),pw.Divider(),
      pw.Text('No. Transaksi : ${r['id']}'),pw.Text('Tanggal       : ${r['date']}'),pw.Text('Nama          : ${r['party']}'),pw.Text('Jenis         : ${r['type']}'),pw.SizedBox(height:12),
      pw.Text('RINCIAN PEMBAYARAN',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),pw.SizedBox(height:6),
      pw.Table(border:pw.TableBorder.all(),children:[pw.TableRow(children:[pw.Padding(padding:const pw.EdgeInsets.all(5),child:pw.Text('Tanggal')),pw.Padding(padding:const pw.EdgeInsets.all(5),child:pw.Text('Metode')),pw.Padding(padding:const pw.EdgeInsets.all(5),child:pw.Text('Jumlah'))]),...payments.map((p)=>pw.TableRow(children:[pw.Padding(padding:const pw.EdgeInsets.all(5),child:pw.Text('${p['date']??'-'}')),pw.Padding(padding:const pw.EdgeInsets.all(5),child:pw.Text('${p['method']??'-'}')),pw.Padding(padding:const pw.EdgeInsets.all(5),child:pw.Text(money.format(n(p['amount']))))]))]),pw.SizedBox(height:12),
      pw.Text('Total kewajiban : ${money.format(total)}'),pw.Text('Total dibayar   : ${money.format(paid)}'),pw.Text('Sisa            : ${money.format(0)}'),pw.SizedBox(height:14),
      pw.Container(width:double.infinity,padding:const pw.EdgeInsets.all(9),decoration:pw.BoxDecoration(border:pw.Border.all()),child:pw.Center(child:pw.Text('LUNAS',style:pw.TextStyle(fontSize:18,fontWeight:pw.FontWeight.bold)))),pw.Spacer(),pw.Center(child:pw.Text('Terima kasih.',style:const pw.TextStyle(fontSize:10)))
    ]))));
    try { await Printing.sharePdf(bytes:await pdf.save(),filename:'Nota_Pelunasan_${r['id']}.pdf'); }
    catch(e){_msg('Nota PDF dibuat tetapi gagal membuka menu berbagi: $e');}
  }

  Future<void> _shipmentForm({Map<String,dynamic>? old}) async {
    final factory=_ctl(old?['party']);final raffia=_ctl(old?['raffiaColor']);final note=_ctl(old?['note']);final sourceLines=_ctl(old?['sourceLinesText']);
    final weights=<String,TextEditingController>{for(final v in varieties)v:_ctl((old?['typeWeights'] is Map)?old!['typeWeights'][v]:'')};
    final prices=<String,TextEditingController>{for(final v in varieties)v:_ctl((old?['typePrices'] is Map)?old!['typePrices'][v]:'')};
    String mode='${old?['invoiceMode']??invoiceModes.first}';
    final ok=await showDialog<bool>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setD)=>AlertDialog(title:Text(old==null?'Pengiriman ke pabrik':'Edit pengiriman'),content:SizedBox(width:500,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      _field(factory,'Nama pabrik'),DropdownButtonFormField<String>(value:invoiceModes.contains(mode)?mode:invoiceModes.first,decoration:_dec('Pola harga nota pabrik'),items:invoiceModes.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>mode=v??invoiceModes.first)),
      const SizedBox(height:10),for(final v in varieties) Padding(padding:const EdgeInsets.only(bottom:8),child:Row(children:[Expanded(flex:2,child:Text(v)),Expanded(flex:3,child:TextField(controller:weights[v],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:_dec('Berat pabrik kg'))),const SizedBox(width:8),Expanded(flex:3,child:TextField(controller:prices[v],keyboardType:TextInputType.number,decoration:_dec('Harga/kg')))])),
      _field(raffia,'Catatan warna tali / sumber (opsional)'),const SizedBox(height:8),_field(sourceLines,'Alokasi sumber per baris: nama sumber | PETANI/PENGEPUL | jenis | berat awal kg | berat pabrik kg | harga/kg | warna rafia',lines:5),const SizedBox(height:8),_field(note,'Catatan pengiriman')
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Simpan pengiriman'))])));
    if (ok == true) {
      final tw = <String, double>{};
      final tp = <String, double>{};
      double gross = 0;
      double totalKg = 0;
      for (final v in varieties) {
        tw[v] = n(weights[v]!.text);
        tp[v] = n(prices[v]!.text);
        totalKg += tw[v]!;
      }
      if (mode == invoiceModes[0]) {
        for (final v in varieties) { gross += tw[v]! * tp[v]!; }
      } else if (mode == invoiceModes[1]) {
        gross = (tw['Panjang']! + tw['Bulat']!) * tp['Panjang']! +
            tw['Ketan']! * tp['Ketan']! + tw['Merah']! * tp['Merah']!;
      } else {
        gross = (tw['Panjang']! + tw['Bulat']! + tw['Merah']!) * tp['Panjang']! +
            tw['Ketan']! * tp['Ketan']!;
      }
      final allocations = <Map<String, dynamic>>[];
      for (final line in sourceLines.text.split('\n')) {
        final parts = line.split('|').map((v) => v.trim()).toList();
        if (parts.length >= 7) {
          allocations.add({
            'sourceName': parts[0], 'sourceType': parts[1].toUpperCase(),
            'variety': parts[2], 'initialKg': n(parts[3]), 'factoryKg': n(parts[4]),
            'price': n(parts[5]), 'raffiaColor': parts[6],
          });
        }
      }
      if (factory.text.trim().isEmpty || totalKg <= 0) {
        _msg('Masukkan pabrik dan minimal satu berat jenis gabah.');
      } else {
        try {
          await _save(
            recordId: old?['id']?.toString(), type: 'PENGIRIMAN',
            party: factory.text.trim(), description: 'Pengiriman gabah ke pabrik',
            qty: totalKg, sellPrice: gross / totalKg, total: gross,
            status: 'Belum dibayar',
            extraData: {
              'factory': factory.text.trim(), 'invoiceMode': mode,
              'typeWeights': tw, 'typePrices': tp, 'grossValue': gross,
              'paid': 0, 'remaining': gross, 'raffiaColor': raffia.text,
              'sourceLinesText': sourceLines.text, 'allocations': allocations,
              'note': note.text, 'payments': [],
              'date': DateTime.now().toIso8601String(),
            },
          );
          _msg('Pengiriman tersimpan.');
        } catch (e) {
          _msg('Gagal: $e');
        }
      }
    }
    factory.dispose();
    raffia.dispose();
    note.dispose();
    sourceLines.dispose();
    for (final c in weights.values) { c.dispose(); }
    for (final c in prices.values) { c.dispose(); }

  }

  Future<void> _addDialog(int index) async {
    switch(index){
      case 1: await _farmerAdvance(); break;
      case 2: await _simpleForm(title:'Tambah modal pengepul',type:'PENGEPUL_MODAL',labels:['Nama pengepul','Jumlah modal diberikan (Rp)','Tanggal','Catatan'],keys:['party','amount','date','description'],unit:'Rp');break;
      case 3: await _simpleForm(title:'Update harga harian',type:'HARGA_HARIAN',labels:['Tanggal','Harga pabrik Panjang (Rp/kg)','Harga pabrik Bulat (Rp/kg)','Harga pabrik Ketan (Rp/kg)','Harga pabrik Merah (Rp/kg)','Catatan'],keys:['date','panjang','bulat','ketan','merah','description'],unit:'Rp');break;
      case 4: await _shipmentForm();break;
      case 5: await _simpleForm(title:'Pembayaran / pencatatan hasil pabrik',type:'PEMBAYARAN_PABRIK',labels:['Nomor pengiriman','Nama pabrik','Tunai diterima (Rp)','Transfer diterima (Rp)','Potongan modal pabrik (Rp)','Potongan beras/huut (Rp)','Catatan'],keys:['shipmentId','factory','cash','transfer','advanceDeduction','deduction','description'],unit:'Rp');break;
      case 6: await _simpleForm(title:'Catat karung keluar / kembali',type:'KARUNG_KELUAR',labels:['Nama pengepul','Jumlah karung','Tanggal','Catatan'],keys:['party','count','date','description'],unit:'karung');break;
      case 7: await _simpleForm(title:'Tambah biaya operasional',type:'BIAYA',labels:['Nomor pengiriman','Kategori biaya','Keterangan','Jumlah biaya (Rp)','Tanggal'],keys:['shipmentId','category','description','amount','date'],unit:'Rp');break;
    }
  }

  Widget _card(Map<String,dynamic> r,{bool paymentAction=false}) {
    final x=extra(r); final type='${r['type']??''}'; final isPaid='${r['status']??x['status']??''}'.toLowerCase()=='lunas';
    final subtitle=[ '${r['id']} • ${r['date']??''}', '${r['description']??''}', if(r['qty']!=null&&n(r['qty'])>0) '${kg.format(n(r['qty']))} ${r['unit']??'kg'}', if(r['total']!=null) money.format(n(r['total'])), 'Status: ${isPaid?'Lunas':r['status']??'Tercatat'}' ].where((s)=>s.isNotEmpty).join('\n');
    return Card(child:Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Column(children:[ListTile(title:Text('${r['party']??r['type']??'Data'}',style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(subtitle),isThreeLine:true,trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')_editGeneric(r);if(v=='delete')_delete(r);if(v=='pay')_recordPayment(r);if(v=='pdf')_shareSettlementReceipt(r);},itemBuilder:(c)=>[
      const PopupMenuItem(value:'edit',child:Text('Edit')),const PopupMenuItem(value:'delete',child:Text('Hapus')),
      if(['PETANI_PEMBELIAN','PENGIRIMAN'].contains(type)&&!isPaid)const PopupMenuItem(value:'pay',child:Text('Catat pembayaran')),
      if(isPaid)const PopupMenuItem(value:'pdf',child:Text('Bagikan nota pelunasan PDF')),
    ])),if(paymentAction&&!isPaid&&['PETANI_PEMBELIAN','PENGIRIMAN'].contains(type))Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:()=>_recordPayment(r),icon:const Icon(Icons.payments),label:const Text('Bayar / lunasi')))])));
  }

  Future<void> _editGeneric(Map<String,dynamic> r) async {
    final type='${r['type']}';
    if(type=='PETANI_PINJAMAN'){await _farmerAdvance(old:r);return;}
    if(type=='PETANI_PEMBELIAN'){await _farmerPurchase(old:r);return;}
    if(type=='PENGEPUL_PADI'){await _collectorPaddy(old:r);return;}
    if(type=='PENGIRIMAN'){await _shipmentForm(old:r);return;}
    await _simpleForm(title:'Edit ${r['description']??r['type']}',type:type,old:r,
      labels:['Nama / pihak','Jumlah (Rp)','Tanggal','Keterangan'],keys:['party','amount','date','description'],unit:'Rp');
  }

  Widget _section(String title,String subtitle,List<Map<String,dynamic>> records,int addIndex,{bool pay=false}) => ListView(padding:const EdgeInsets.all(12),children:[
    Card(color:const Color(0xFFEAF8EF),child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[const Icon(Icons.info_outline,color:green),const SizedBox(width:8),Expanded(child:Text(subtitle,style:const TextStyle(color:Colors.black87)))]))),
    FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:green),onPressed:()=>_addDialog(addIndex),icon:const Icon(Icons.add),label:Text('Tambah $title')),
    const SizedBox(height:8),...records.reversed.map((r)=>_card(r,paymentAction:pay)),if(records.isEmpty)const Padding(padding:EdgeInsets.all(22),child:Center(child:Text('Belum ada data.')))
  ]);

  Widget _dashboard()=>RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(12),children:[
    if(error.isNotEmpty)Card(color:Colors.red.shade50,child:Padding(padding:const EdgeInsets.all(10),child:Text('Gagal memuat data: $error'))),
    GridView.count(crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),childAspectRatio:1.65,children:[
      _metric('Stok sisa tercatat','${kg.format(stockKg)} kg',Icons.inventory_2),_metric('Pinjaman petani',money.format(farmerAdvance),Icons.account_balance_wallet),
      _metric('Pembelian petani',money.format(farmerPurchase),Icons.grass),_metric('Nilai pengiriman',money.format(shipmentRevenue),Icons.local_shipping),
      _metric('Biaya operasional',money.format(expenses),Icons.receipt_long),_metric('Pengiriman', '${of('PENGIRIMAN').length} kali',Icons.factory)
    ]),const SizedBox(height:12),const Text('Aktivitas terbaru',style:TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
    ...rows.reversed.take(8).map((r)=>_card(r)),if(rows.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('Belum ada transaksi gabah.'))
  ]));
  Widget _metric(String label,String value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,color:green),const SizedBox(height:6),Text(label,style:const TextStyle(fontSize:11,color:Colors.black54)),FittedBox(fit:BoxFit.scaleDown,child:Text(value,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15)))])));

  Widget _farmers()=>ListView(padding:const EdgeInsets.all(12),children:[
    FilledButton.icon(onPressed:()=>_farmerPurchase(),icon:const Icon(Icons.add),label:const Text('Catat pembelian gabah petani')),
    FilledButton.tonalIcon(onPressed:()=>_farmerAdvance(),icon:const Icon(Icons.payments_outlined),label:const Text('Catat pinjaman / uang muka petani')),
    const SizedBox(height:8),FilledButton.tonalIcon(onPressed:()=>_simpleForm(title:'Catat pengembalian pinjaman petani',type:'PETANI_PEMBAYARAN',labels:['Nama petani','Jumlah pengembalian pinjaman (Rp)','Tanggal','Catatan'],keys:['party','amount','date','description'],unit:'Rp'),icon:const Icon(Icons.assignment_return),label:const Text('Catat pengembalian pinjaman')),const Text('Pembelian gabah',style:TextStyle(fontWeight:FontWeight.bold)),...of('PETANI_PEMBELIAN').reversed.map((r)=>_card(r,paymentAction:true)),
    const Text('Pinjaman petani',style:TextStyle(fontWeight:FontWeight.bold)),...of('PETANI_PINJAMAN').reversed.map((r)=>_card(r)),
    const Text('Riwayat pembayaran petani',style:TextStyle(fontWeight:FontWeight.bold)),...of('PETANI_PEMBAYARAN').reversed.map((r)=>_card(r))
  ]);
  Widget _collectors()=>ListView(padding:const EdgeInsets.all(12),children:[
    FilledButton.icon(onPressed:()=>_addDialog(2),icon:const Icon(Icons.add),label:const Text('Catat pemberian modal pengepul')),
    FilledButton.tonalIcon(onPressed:()=>_collectorPaddy(),icon:const Icon(Icons.scale),label:const Text('Catat hasil timbang pabrik pengepul')),
    FilledButton.tonalIcon(onPressed:()=>_simpleForm(title:'Catat pembayaran pengepul',type:'PENGEPUL_PEMBAYARAN',labels:['Nama pengepul','Jumlah dibayar (Rp)','Tanggal','Catatan'],keys:['party','amount','date','description'],unit:'Rp'),icon:const Icon(Icons.payments),label:const Text('Catat pembayaran pengepul')),
    FilledButton.tonalIcon(onPressed:()=>_simpleForm(title:'Karung dipinjamkan',type:'KARUNG_KELUAR',labels:['Nama pengepul','Jumlah karung','Tanggal','Catatan'],keys:['party','count','date','description'],unit:'karung'),icon:const Icon(Icons.outbox),label:const Text('Catat karung keluar')),
    FilledButton.tonalIcon(onPressed:()=>_simpleForm(title:'Karung dikembalikan',type:'KARUNG_KEMBALI',labels:['Nama pengepul','Jumlah karung','Tanggal','Catatan'],keys:['party','count','date','description'],unit:'karung'),icon:const Icon(Icons.move_to_inbox),label:const Text('Catat karung kembali')),
    const SizedBox(height:10),for(final name in <String>{...of('PENGEPUL_MODAL').map((r)=>'${r['party']}'),...of('PENGEPUL_PADI').map((r)=>'${r['party']}')}) Card(child:ListTile(title:Text(name),subtitle:Text('Modal ${money.format(collectorCapital(name))} • Nilai gabah ${money.format(collectorValue(name))}\nSaldo modal minus nilai gabah: ${money.format(collectorOwed(name))} • Karung di luar: ${kg.format(sacksOut(name))}'),isThreeLine:true)),
    const Text('Riwayat modal, timbang, karung dan pembayaran',style:TextStyle(fontWeight:FontWeight.bold)),...([...of('PENGEPUL_MODAL'),...of('PENGEPUL_PADI'),...of('PENGEPUL_PEMBAYARAN'),...of('KARUNG_KELUAR'),...of('KARUNG_KEMBALI')].reversed.map((r)=>_card(r,paymentAction:true)))
  ]);
  Widget _prices()=>ListView(padding:const EdgeInsets.all(12),children:[
    FilledButton.icon(onPressed:()=>_addDialog(3),icon:const Icon(Icons.add),label:const Text('Update harga harian')),
    ...of('HARGA_HARIAN').reversed.map((r)=>_card(r)),if(of('HARGA_HARIAN').isEmpty)const Text('Belum ada harga harian.')
  ]);
  Widget _shipments()=>ListView(padding:const EdgeInsets.all(12),children:[
    FilledButton.icon(onPressed:()=>_shipmentForm(),icon:const Icon(Icons.add),label:const Text('Buat pengiriman ke pabrik')),
    ...of('PENGIRIMAN').reversed.map((r)=>_card(r,paymentAction:true)),if(of('PENGIRIMAN').isEmpty)const Text('Belum ada pengiriman.')
  ]);
  Widget _factoryPayments()=>ListView(padding:const EdgeInsets.all(12),children:[
    _metric('Sisa modal dari pabrik',money.format(factoryAdvanceBalance),Icons.account_balance_wallet),
    FilledButton.tonalIcon(onPressed:()=>_simpleForm(title:'Catat modal diterima dari pabrik',type:'MODAL_PABRIK',labels:['Nama pabrik','Jumlah modal diterima (Rp)','Tanggal','Catatan'],keys:['party','amount','date','description'],unit:'Rp'),icon:const Icon(Icons.savings),label:const Text('Catat modal / uang muka dari pabrik')),
    FilledButton.icon(onPressed:()=>_addDialog(5),icon:const Icon(Icons.add),label:const Text('Catat pembayaran pabrik / potongan beras atau huut')),
    ...of('MODAL_PABRIK').reversed.map((r)=>_card(r)),
    ...of('PEMBAYARAN_PABRIK').reversed.map((r)=>_card(r)),
    const Text('Nota pengiriman dan nilai tagihan',style:TextStyle(fontWeight:FontWeight.bold)),...of('PENGIRIMAN').reversed.map((r)=>_card(r,paymentAction:true))
  ]);
  Widget _stockSacks()=>ListView(padding:const EdgeInsets.all(12),children:[
    _metric('Stok sisa tercatat','${kg.format(stockKg)} kg',Icons.warehouse),
    for(final v in varieties)ListTile(title:Text(v),trailing:Text('${kg.format(stockFor(v))} kg')),
    const Divider(),const Text('Mutasi karung',style:TextStyle(fontWeight:FontWeight.bold)),
    ...([...of('KARUNG_KELUAR'),...of('KARUNG_KEMBALI')].reversed.map((r)=>_card(r)))
  ]);
  Widget _costs()=>_section('biaya operasional','Catat kuli panggul, bensin, kopi/rokok/minuman dan biaya tambahan per pengiriman.',of('BIAYA'),7);

  Widget _reports(){
    final d=reportDate;final selected=rows.where((r){final dt=DateTime.tryParse('${r['date']??''}');if(dt==null)return false;return monthly?dt.year==d.year&&dt.month==d.month:dt.year==d.year&&dt.month==d.month&&dt.day==d.day;}).toList();
    final rev=selected.where((r)=>r['type']=='PENGIRIMAN').fold(0.0,(a,r)=>a+n(r['grossValue']));
    final buy=selected.where((r)=>r['type']=='PETANI_PEMBELIAN').fold(0.0,(a,r)=>a+n(r['purchaseValue']));
    final cost=selected.where((r)=>r['type']=='BIAYA').fold(0.0,(a,r)=>a+n(r['amount']));
    return ListView(padding:const EdgeInsets.all(12),children:[
      SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('Harian')),ButtonSegment(value:true,label:Text('Bulanan'))],selected:{monthly},onSelectionChanged:(v)=>setState(()=>monthly=v.first)),
      ListTile(title:Text(DateFormat(monthly?'MMMM yyyy':'dd MMMM yyyy','id_ID').format(reportDate)),trailing:IconButton(icon:const Icon(Icons.calendar_month),onPressed:()async{final p=await showDatePicker(context:context,initialDate:reportDate,firstDate:DateTime(2020),lastDate:DateTime(2100));if(p!=null)setState(()=>reportDate=p);})),
      _metric('Nilai penjualan pabrik',money.format(rev),Icons.factory),_metric('Pembelian petani',money.format(buy),Icons.grass),_metric('Biaya operasional',money.format(cost),Icons.receipt),
      _metric('Margin sementara',money.format(rev-buy-cost),Icons.analytics),
      const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('Rincian aktivitas periode',style:TextStyle(fontWeight:FontWeight.bold))),...selected.reversed.map((r)=>_card(r))
    ]);
  }

  @override
  Widget build(BuildContext context){
    final pages=<Widget>[_dashboard(),_farmers(),_collectors(),_prices(),_shipments(),_factoryPayments(),_stockSacks(),_costs(),_reports()];
    return Scaffold(
      appBar:AppBar(title:const Text('Jual Beli Gabah / Padi'),backgroundColor:green,foregroundColor:Colors.white,actions:[IconButton(tooltip:'Muat ulang',onPressed:_load,icon:const Icon(Icons.refresh))]),
      body:loading?const Center(child:CircularProgressIndicator()):pages[tab],
      bottomNavigationBar:Container(color:Colors.white,height:68,child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
        for(var i=0;i<tabs.length;i++)InkWell(onTap:()=>setState(()=>tab=i),child:Container(width:100,padding:const EdgeInsets.symmetric(horizontal:5,vertical:8),decoration:BoxDecoration(border:Border(top:BorderSide(color:tab==i?green:Colors.transparent,width:3))),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon([Icons.dashboard,Icons.agriculture,Icons.people,Icons.price_change,Icons.local_shipping,Icons.account_balance,Icons.inventory,Icons.receipt_long,Icons.analytics][i],color:tab==i?green:Colors.grey),Text(tabs[i],textAlign:TextAlign.center,maxLines:2,style:TextStyle(fontSize:10,fontWeight:tab==i?FontWeight.bold:FontWeight.normal,color:tab==i?green:Colors.grey[700]))]))),
      ]))),
    );
  }
}


class LpgModuleScreen extends StatefulWidget {
  final String apiUrl;
  const LpgModuleScreen({super.key, required this.apiUrl});

  @override
  State<LpgModuleScreen> createState() => _LpgModuleScreenState();
}

class _LpgModuleScreenState extends State<LpgModuleScreen> {
  final Color green = const Color(0xFF10B981);
  final List<String> tabs = const [
    'Penjualan', 'Tabung di Luar', 'Pembelian', 'Pelanggan', 'Stok',
    'Retur Gas', 'Kasbon', 'Laporan', 'Riwayat Transaksi', 'Distribusi', 'Laporan Distribusi'
  ];
  int tab = 0;
  bool reportMonthly = false;
  DateTime reportDate = DateTime.now();
  bool loading = false;
  Map<String, List<Map<String, dynamic>>> data = {};
  final Map<String, int> initialFull = {};
  final Map<String, int> initialEmpty = {};
  final Map<String, double> customerPrices = {};
  final NumberFormat money = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  List<Map<String, dynamic>> rows(String key) => data[key] ?? [];
  int n(dynamic v) => (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
  double d(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
  String dateNow() => DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  DateTime? _parseLpgDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) return null;
    try { return DateTime.parse(value.toString()).toLocal(); } catch (_) { return null; }
  }

  String _formatLpgDate(dynamic value) {
    final dt = _parseLpgDate(value);
    return dt == null ? '-' : DateFormat('dd-MM-yyyy HH:mm').format(dt);
  }

  List<Map<String, dynamic>> _saleItems(Map<String, dynamic> sale) {
    try {
      final raw = jsonDecode('${sale['items'] ?? ''}');
      if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    return [
      {'variant': sale['variant'] ?? '-', 'qty': sale['qty'] ?? 0,
       'unitPrice': sale['unitPrice'] ?? 0,
       'total': d(sale['total'])},
    ];
  }

  Map<String, dynamic>? _saleDebt(Map<String, dynamic> sale) {
    final found = rows('LPG_Kasbon').where((x) =>
      x['saleId'] == sale['id'] && x['voided'] != true && d(x['remaining']) > 0).toList();
    if (found.isEmpty) return null;
    return found.first;
  }

  String _salePaymentLabel(Map<String, dynamic> sale, Map<String, dynamic>? debt) {
    if (debt != null) return 'Kasbon / belum lunas';
    final payment = '${sale['payment'] ?? '-'}';
    if (payment == 'Kasbon Sebagian' || payment == 'Kasbon Penuh') return 'Kasbon (lunas)';
    if (payment == 'Split Bill') return 'Tunai + QRIS';
    return payment;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final uri = Uri.parse(widget.apiUrl).replace(queryParameters: {'action': 'getLpgData'});
      final res = await http.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final decoded = json.decode(res.body);
      if (decoded is! Map) throw Exception('Format data LPG tidak valid');
      final Map<String, List<Map<String, dynamic>>> parsed = {};
      decoded.forEach((k, v) {
        parsed[k.toString()] = (v as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
      if (mounted) setState(() { data = parsed; loading = false; });
    } catch (e) {
      if (mounted) setState(() => loading = false);
      _msg('Gagal memuat data LPG: $e');
    }
  }

  Future<void> _commit(List<Map<String, dynamic>> records) async {
    final client = http.Client();
    http.Response res;
    try {
      final request = http.Request('POST', Uri.parse(widget.apiUrl))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = json.encode({'action': 'lpgCommit', 'records': records});
      final streamed = await client.send(request).timeout(const Duration(seconds: 40));
      res = await http.Response.fromStream(streamed);
      // Apps Script ContentService kadang mengembalikan redirect ke googleusercontent.
      if (res.statusCode >= 300 && res.statusCode < 400) {
        final location = res.headers['location'];
        if (location == null || location.isEmpty) {
          throw Exception('Apps Script mengembalikan HTTP ${res.statusCode} tanpa Location.');
        }
        res = await client.get(Uri.parse(location)).timeout(const Duration(seconds: 40));
      }
    } finally {
      client.close();
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}: ${res.body}');
    final result = json.decode(res.body);
    if (result is Map && result['status'] != 'success') {
      throw Exception(result['message'] ?? 'Penyimpanan gagal');
    }
    await _load();
  }

  Future<void> _voidLpgRecord(String sheet, Map<String,dynamic> record) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Batalkan data LPG?'),
      content: const Text('Data akan ditandai batal dan tidak lagi dihitung dalam laporan/stok. Riwayat tetap dipertahankan.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Tidak')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya, batalkan')),
      ],
    ));
    if (ok != true) return;
    final id = '${record['id']}';
    final now = dateNow();
    final updates = <Map<String,dynamic>>[];
    final original = Map<String,dynamic>.from(record)..['voided'] = true..['voidedAt'] = now;
    updates.add({'sheet': sheet, ...original});
    if (sheet == 'LPG_Penjualan' || sheet == 'LPG_Pembelian') {
      for (final m in rows('LPG_MutasiStok').where((m) => '${m['id']}'.startsWith(id))) {
        updates.add({'sheet':'LPG_MutasiStok', ...Map<String,dynamic>.from(m), 'voided':true, 'voidedAt':now});
      }
    }
    if (sheet == 'LPG_Penjualan') {
      for (final p in rows('LPG_Pembayaran').where((p) => p['saleId'] == id)) {
        updates.add({'sheet':'LPG_Pembayaran', ...Map<String,dynamic>.from(p), 'voided':true, 'voidedAt':now});
      }
      for (final debt in rows('LPG_Kasbon').where((x) => x['saleId'] == id)) {
        updates.add({'sheet':'LPG_Kasbon', ...Map<String,dynamic>.from(debt), 'voided':true, 'voidedAt':now});
      }
    }
    updates.add({'sheet':'LPG_Riwayat','id':'BATAL-$id-$now','date':now,'activity':'Pembatalan data','description':'$sheet $id dibatalkan','by':'Aplikasi'});
    try { await _commit(updates); _msg('Data dibatalkan dan stok/laporan disesuaikan.'); }
    catch (e) { _msg('Gagal membatalkan data: $e'); }
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Map<String, int> _stock(String variant) {
    int full = 0, empty = 0, quarantine = 0, borrowed = 0, inTransit = 0;
    for (final r in rows('LPG_MutasiStok')) {
      if (r['voided'] == true) continue;
      if ((r['variant'] ?? '') != variant) continue;
      final type = r['type'] ?? '';
      final qty = n(r['qty']);
      switch (type) {
        case 'OPEN_FULL': full += qty; break;
        case 'OPEN_EMPTY': empty += qty; break;
        case 'PURCHASE_FULL': full += qty; break;
        case 'DIST_LOAD_FULL': full -= qty; break;
        case 'DIST_RETURN_FULL': full += qty; break;
        case 'DIST_RETURN_EMPTY': empty += qty; break;
        case 'DIST_LOAN_FULL': borrowed += qty; break;
        case 'SALE_FULL': full -= qty; break;
        case 'SALE_EMPTY_IN': empty += qty; break;
        case 'PURCHASE_EMPTY_OUT': empty -= qty; break;
        case 'BORROW_EMPTY': empty -= qty; borrowed += qty; break;
        case 'OPEN_BORROWED': borrowed += qty; break;
        case 'RETURN_BORROW_EMPTY': empty += qty; borrowed -= qty; break;
        case 'CUSTOMER_LEAK_RETURN': full -= qty; quarantine += qty; break;
        case 'AGENT_LEAK_RETURN': quarantine -= qty; inTransit += qty; break;
        case 'AGENT_REPLACEMENT_FULL': full += qty; break;
        case 'AGENT_REPLACEMENT_RECEIVED': inTransit -= qty; break;
        case 'MANUAL_FULL': full += n(r['delta']); break;
        case 'MANUAL_EMPTY': empty += n(r['delta']); break;
      }
    }
    return {'full': full, 'empty': empty, 'quarantine': quarantine, 'borrowed': borrowed, 'inTransit': inTransit};
  }

  int _sum(String key) => rows(key).length;
  List<Map<String, dynamic>> get customers => rows('LPG_Pelanggan').where((c)=>c['voided']!=true).toList();
  String _customerName(Map<String, dynamic> c) => '${c['name'] ?? ''}';

  Future<void> _saleDialog() async {
    String customer = 'Umum / Walk-in', payment = 'Tunai';
    bool includeOldDebt = false;
    final selected = <String, bool>{for (final v in lpgVariants) v: v == lpgVariants.first};
    final qtyCtrls = <String, TextEditingController>{for (final v in lpgVariants) v: TextEditingController(text: '1')};
    final priceCtrls = <String, TextEditingController>{for (final v in lpgVariants) v: TextEditingController(text: v == lpgVariants.first ? '17000' : '0')};
    final emptyCtrls = <String, TextEditingController>{for (final v in lpgVariants) v: TextEditingController(text: '1')};
    final buyerC=TextEditingController(), nikC=TextEditingController(), staffC=TextEditingController();
    final paidC=TextEditingController(text:'0'), cashC=TextEditingController(text:'0'), qrisC=TextEditingController(text:'0');
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD){
      final items=<Map<String,dynamic>>[];
      for(final v in lpgVariants){if(selected[v]==true){final q=n(qtyCtrls[v]!.text), pr=d(priceCtrls[v]!.text);items.add({'variant':v,'qty':q,'unitPrice':pr,'emptyReceived':n(emptyCtrls[v]!.text),'total':q*pr});}}
      final total=items.fold<double>(0,(a,x)=>a+d(x['total']));
      final oldDebts = rows('LPG_Kasbon').where((x)=>x['voided']!=true && x['status']!='Lunas' && x['customer']==customer && d(x['remaining'])>0).toList();
      final oldDebtTotal = oldDebts.fold<double>(0,(a,x)=>a+d(x['remaining']));
      final includedDebt = includeOldDebt ? oldDebtTotal : 0.0;
      final invoiceTotal = total + includedDebt;
      final paid=payment=='Kasbon Penuh'?0:payment=='QRIS'?invoiceTotal:payment=='Split Bill'?d(cashC.text)+d(qrisC.text):d(paidC.text);
      final remaining=(invoiceTotal-paid).clamp(0,invoiceTotal);
      return AlertDialog(
        title:const Text('Penjualan LPG'),
        content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<String>(value:customer,decoration:const InputDecoration(labelText:'Pelanggan'),items:['Umum / Walk-in',...customers.map(_customerName)].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){setD(()=>customer=v!);final matched=customers.where((x)=>_customerName(x)==v).toList(); final c=matched.isEmpty?null:matched.first; if(c!=null){for(final variant in lpgVariants){final key=variant=='LPG 3 kg'?'price_3':variant=='LPG 5,5 kg'?'price_55':'price_12';final price=d(c[key]);if(price>0)priceCtrls[variant]!.text=price.toStringAsFixed(0);}}}),
          TextField(controller:buyerC,decoration:const InputDecoration(labelText:'Nama pembeli (opsional)')),
          TextField(controller:nikC,decoration:const InputDecoration(labelText:'NIK (opsional)')),
          const Align(alignment:Alignment.centerLeft,child:Padding(padding:EdgeInsets.only(top:12,bottom:4),child:Text('Pilih satu atau beberapa jenis tabung',style:TextStyle(fontWeight:FontWeight.bold)))),
          for(final v in lpgVariants) Card(margin:const EdgeInsets.symmetric(vertical:4),child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[
            CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,value:selected[v],title:Text(v,style:const TextStyle(fontWeight:FontWeight.bold)),onChanged:(x)=>setD(()=>selected[v]=x??false)),
            if(selected[v]==true) ...[
              TextField(controller:qtyCtrls[v],keyboardType:TextInputType.number,onChanged:(_)=>setD((){final q=n(qtyCtrls[v]!.text);emptyCtrls[v]!.text=q.toString();}),decoration:const InputDecoration(labelText:'Jumlah tabung isi')),
              TextField(controller:priceCtrls[v],keyboardType:TextInputType.number,onChanged:(_)=>setD((){}),decoration:const InputDecoration(labelText:'Harga per tabung')),
              TextField(controller:emptyCtrls[v],keyboardType:TextInputType.number,onChanged:(_)=>setD((){}),decoration:const InputDecoration(labelText:'Tabung kosong diterima (wajib sama dengan jumlah jual)')),
              Align(alignment:Alignment.centerRight,child:Text('Subtotal: ${money.format(n(qtyCtrls[v]!.text)*d(priceCtrls[v]!.text))}',style:const TextStyle(fontWeight:FontWeight.w600))),
            ]
          ]))),
          const Divider(),
          if(oldDebtTotal>0) CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,value:includeOldDebt,title:Text('Sertakan tunggakan lama (${money.format(oldDebtTotal)})'),subtitle:const Text('Total bayar = pembelian baru + tunggakan lama'),onChanged:(v)=>setD(()=>includeOldDebt=v??false)),
          if(includeOldDebt) Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Pembelian baru'),Text(money.format(total))]),
          if(includeOldDebt) Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Tunggakan lama'),Text(money.format(oldDebtTotal))]),
          const Divider(),Text('TOTAL BAYAR: ${money.format(invoiceTotal)}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          DropdownButtonFormField<String>(value:payment,decoration:const InputDecoration(labelText:'Pembayaran'),items:['Tunai','QRIS','Split Bill','Kasbon Penuh','Kasbon Sebagian'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>payment=v!)),
          if(payment=='Tunai'||payment=='Kasbon Sebagian')TextField(controller:paidC,keyboardType:TextInputType.number,onChanged:(_)=>setD((){}),decoration:InputDecoration(labelText:payment=='Tunai'?'Uang diterima':'Uang dibayar / DP')),
          if(payment=='Split Bill')...[
            TextField(controller:cashC,keyboardType:TextInputType.number,onChanged:(_)=>setD((){}),decoration:const InputDecoration(labelText:'Bagian tunai')),
            TextField(controller:qrisC,keyboardType:TextInputType.number,onChanged:(_)=>setD((){}),decoration:const InputDecoration(labelText:'Bagian QRIS')),
          ],
          if(payment=='QRIS'||(payment=='Split Bill'&&d(qrisC.text)>0))Padding(padding:const EdgeInsets.all(8),child:GestureDetector(onTap:()=>showDialog(context:ctx,builder:(c)=>Dialog(child:InteractiveViewer(child:Image.asset('assets/images/qris.png')))),child:Image.asset('assets/images/qris.png',height:120,errorBuilder:(_,__,___)=>const Text('QRIS tidak ditemukan')))),
          if(payment.startsWith('Kasbon'))Text('Sisa kasbon: ${money.format(remaining)}'),
          TextField(controller:staffC,decoration:const InputDecoration(labelText:'Nama kasir/petugas')),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
          if(items.isEmpty){_msg('Pilih minimal satu jenis tabung.');return;}
          for(final item in items){final v='${item['variant']}',q=n(item['qty']),empty=n(item['emptyReceived']);if(q<=0||empty!=q){_msg('Tabung kosong yang diterima untuk $v wajib sama dengan jumlah jual.');return;}if(_stock(v)['full']!<q){_msg('Stok $v tidak mencukupi.');return;}if(d(item['unitPrice'])<=0){_msg('Harga $v harus lebih dari nol.');return;}}
          if(payment=='Split Bill'&&(d(cashC.text)+d(qrisC.text)-invoiceTotal).abs()>0.5){_msg('Tunai + QRIS harus sama dengan total.');return;}
          if((payment=='Tunai'||payment=='Kasbon Sebagian')&&d(paidC.text)>invoiceTotal){_msg('Pembayaran tidak boleh melebihi total.');return;}
          if(payment=='Tunai'&&d(paidC.text)<invoiceTotal){_msg('Pembayaran tunai kurang.');return;}
          if(payment=='Kasbon Sebagian'&&(d(paidC.text)<=0||d(paidC.text)>=invoiceTotal)){_msg('Isi pembayaran sebagian yang valid.');return;}
          final id='LPG-${DateTime.now().millisecondsSinceEpoch}',now=dateNow();
          final paidNow=payment=='Tunai'||payment=='QRIS'||payment=='Split Bill'?invoiceTotal:payment=='Kasbon Penuh'?0:d(paidC.text);
          var cashLeft = payment=='Split Bill' ? d(cashC.text) : (payment=='Tunai'||payment=='Kasbon Sebagian' ? paidNow : 0.0);
          var qrisLeft = payment=='Split Bill' ? d(qrisC.text) : (payment=='QRIS' ? paidNow : 0.0);
          var oldDebtPaid = 0.0;
          final oldDebtUpdates = <Map<String,dynamic>>[];
          if(includeOldDebt) {
            for(final oldDebt in oldDebts) {
              final due=d(oldDebt['remaining']);
              final fromCash=cashLeft.clamp(0.0,due).toDouble(); cashLeft-=fromCash;
              final fromQris=qrisLeft.clamp(0.0,due-fromCash).toDouble(); qrisLeft-=fromQris;
              final alloc=fromCash+fromQris;
              if(alloc>0) {
                oldDebtPaid+=alloc;
                final newRemain=(due-alloc).clamp(0.0,due);
                if(fromCash>0) oldDebtUpdates.add({'sheet':'LPG_Pembayaran','id':'$id-OLD-CASH-${oldDebt['id']}','date':now,'debtId':oldDebt['id'],'customer':customer,'amount':fromCash,'method':'Tunai','staff':staffC.text});
                if(fromQris>0) oldDebtUpdates.add({'sheet':'LPG_Pembayaran','id':'$id-OLD-QRIS-${oldDebt['id']}','date':now,'debtId':oldDebt['id'],'customer':customer,'amount':fromQris,'method':'QRIS','staff':staffC.text});
                oldDebtUpdates.add({'sheet':'LPG_Kasbon','id':oldDebt['id'],'date':oldDebt['date'],'saleId':oldDebt['saleId'],'customer':oldDebt['customer'],'total':oldDebt['total'],'paid':d(oldDebt['paid'])+alloc,'remaining':newRemain,'status':newRemain<=0?'Lunas':'Belum Lunas'});
              }
            }
          }
          final paidForNewSale=(paidNow-oldDebtPaid).clamp(0.0,total);
          final records=<Map<String,dynamic>>[
            {'sheet':'LPG_Penjualan','id':id,'date':now,'variant':items.map((x)=>x['variant']).join(', '),'items':jsonEncode(items),'customer':customer,'buyer':buyerC.text,'nik':nikC.text,'qty':items.fold<int>(0,(a,x)=>a+n(x['qty'])),'unitPrice':0,'total':total,'payment':payment,'paid':paidForNewSale,'remaining':total-paidForNewSale,'staff':staffC.text,'emptyReceived':items.fold<int>(0,(a,x)=>a+n(x['emptyReceived']))},
            {'sheet':'LPG_Riwayat','id':id,'date':now,'activity':'Penjualan LPG','description':'${items.map((x)=>'${x['variant']} ${x['qty']} tabung').join(', ')} kepada $customer; total ${money.format(total)}','by':staffC.text},
          ];
          records.addAll(oldDebtUpdates);
          for(final item in items){final v='${item['variant']}',q=n(item['qty']);records.addAll([
            {'sheet':'LPG_MutasiStok','id':'$id-${lpgVariants.indexOf(v)}-FULL','date':now,'variant':v,'type':'SALE_FULL','qty':q,'note':'Penjualan $id'},
            {'sheet':'LPG_MutasiStok','id':'$id-${lpgVariants.indexOf(v)}-EMPTY','date':now,'variant':v,'type':'SALE_EMPTY_IN','qty':q,'note':'Tabung kosong diterima dari $id'},
          ]);}
          if(paidForNewSale>0 && payment!='Split Bill')records.add({'sheet':'LPG_Pembayaran','id':'$id-PAY','date':now,'saleId':id,'customer':customer,'amount':paidForNewSale,'method':payment=='Kasbon Sebagian'?'Tunai':payment,'staff':staffC.text});
          if(payment=='Split Bill'){final cashForSale=cashLeft.clamp(0.0,paidForNewSale);final qrisForSale=qrisLeft.clamp(0.0,paidForNewSale-cashForSale);if(cashForSale>0)records.add({'sheet':'LPG_Pembayaran','id':'$id-CASH','date':now,'saleId':id,'customer':customer,'amount':cashForSale,'method':'Tunai','staff':staffC.text});if(qrisForSale>0)records.add({'sheet':'LPG_Pembayaran','id':'$id-QRIS','date':now,'saleId':id,'customer':customer,'amount':qrisForSale,'method':'QRIS','staff':staffC.text});}
                    if(total-paidForNewSale>0)records.add({'sheet':'LPG_Kasbon','id':'$id-DEBT','date':now,'saleId':id,'customer':customer,'total':total,'paid':paidForNewSale,'remaining':total-paidForNewSale,'status':'Belum Lunas'});
          try{await _commit(records);if(ctx.mounted)Navigator.pop(ctx);_msg('Penjualan LPG tersimpan.');}catch(e){_msg('Gagal menyimpan: $e');}
        },child:const Text('Simpan Penjualan'))]
      );
    }));
  }

  Future<void> _purchaseDialog() async {
    String variant=lpgVariants.first, agent=lpgAgents.first, payment='Tunai';
    final qty=TextEditingController(text:'1'), price=TextEditingController(), emptyOut=TextEditingController(text:'0'), staff=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Pembelian LPG dari Agen'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField(value:agent,items:lpgAgents.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),decoration:const InputDecoration(labelText:'Agen'),onChanged:(v)=>setD(()=>agent=v!)),
        DropdownButtonFormField(value:variant,items:lpgVariants.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),decoration:const InputDecoration(labelText:'Jenis LPG'),onChanged:(v)=>setD(()=>variant=v!)),
        TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah tabung isi diterima')),
        TextField(controller:price,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Harga beli per tabung')),
        TextField(controller:emptyOut,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Tabung kosong diserahkan ke agen')),
        DropdownButtonFormField(value:payment,items:['Tunai','QRIS','Transfer'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),decoration:const InputDecoration(labelText:'Metode pembayaran'),onChanged:(v)=>setD(()=>payment=v!)),
        TextField(controller:staff,decoration:const InputDecoration(labelText:'Petugas')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
        final q=n(qty.text), e=n(emptyOut.text), st=_stock(variant);
        if(q<=0 || d(price.text)<=0){_msg('Jumlah dan harga pembelian harus valid.');return;}
        if(st['empty']!<e){_msg('Stok tabung kosong tidak cukup untuk diserahkan ke agen.');return;}
        final id='BELI-${DateTime.now().millisecondsSinceEpoch}', now=dateNow();
        try{await _commit([
          {'sheet':'LPG_Pembelian','id':id,'date':now,'agent':agent,'variant':variant,'qty':q,'unitPrice':d(price.text),'total':q*d(price.text),'payment':payment,'emptyToAgent':e,'staff':staff.text},
          {'sheet':'LPG_MutasiStok','id':'$id-F','date':now,'variant':variant,'type':'PURCHASE_FULL','qty':q,'note':'Pembelian dari $agent'},
          if(e>0) {'sheet':'LPG_MutasiStok','id':'$id-E','date':now,'variant':variant,'type':'PURCHASE_EMPTY_OUT','qty':e,'note':'Tabung kosong diserahkan ke agen'},
        ]);if(ctx.mounted)Navigator.pop(ctx);_msg('Pembelian tersimpan.');}catch(x){_msg('Gagal: $x');}
      },child:const Text('Simpan Pembelian'))]
    )));
  }

  Future<void> _customerDialog([Map<String,dynamic>? existing]) async {
    final name=TextEditingController(text:'${existing?['name'] ?? ''}'), owner=TextEditingController(text:'${existing?['owner'] ?? ''}'), address=TextEditingController(text:'${existing?['address'] ?? ''}'), wa=TextEditingController(text:'${existing?['wa'] ?? ''}'), p3=TextEditingController(text:'${existing?['price_3'] ?? 16000}'), p55=TextEditingController(text:'${existing?['price_55'] ?? 0}'), p12=TextEditingController(text:'${existing?['price_12'] ?? 0}');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:Text(existing==null?'Tambah Pelanggan LPG':'Edit Pelanggan LPG'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:name,decoration:const InputDecoration(labelText:'Nama warung/pelanggan')),
      TextField(controller:owner,decoration:const InputDecoration(labelText:'Nama pemilik')),
      TextField(controller:address,decoration:const InputDecoration(labelText:'Alamat/area')),
      TextField(controller:wa,decoration:const InputDecoration(labelText:'Nomor WhatsApp')),
      TextField(controller:p3,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Harga LPG 3 kg')),
      TextField(controller:p55,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Harga LPG 5,5 kg')),
      TextField(controller:p12,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Harga LPG 12 kg')),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
      if(name.text.trim().isEmpty){_msg('Nama pelanggan wajib diisi.');return;}
      final id='${existing?['id'] ?? 'C-${DateTime.now().millisecondsSinceEpoch}'}';
      try{await _commit([{'sheet':'LPG_Pelanggan','id':id,'date':dateNow(),'name':name.text,'owner':owner.text,'address':address.text,'wa':wa.text,'price_3':d(p3.text),'price_55':d(p55.text),'price_12':d(p12.text),'active':true}]);if(ctx.mounted)Navigator.pop(ctx);}catch(e){_msg('Gagal: $e');}
    },child:const Text('Simpan'))]));
  }

  Future<void> _openingBorrowedDialog() async {
    String borrowerType='Warung', variant=lpgVariants.first, borrower=customers.isEmpty?'':_customerName(customers.first);
    final person=TextEditingController(), qty=TextEditingController(text:'1'), given=TextEditingController(), received=TextEditingController(), note=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Input Tabung yang Sudah Berada di Luar'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Untuk mencatat saldo tabung yang sudah dipinjamkan sebelum aplikasi digunakan. Tidak mengurangi stok gudang lagi.'),
        DropdownButtonFormField<String>(value:borrowerType,items:['Warung','Perorangan'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>borrowerType=v!),decoration:const InputDecoration(labelText:'Jenis peminjam')),
        if(borrowerType=='Warung'&&customers.isNotEmpty)DropdownButtonFormField<String>(value:borrower.isEmpty?_customerName(customers.first):borrower,items:customers.map((c)=>DropdownMenuItem(value:_customerName(c),child:Text(_customerName(c)))).toList(),onChanged:(v)=>setD(()=>borrower=v!),decoration:const InputDecoration(labelText:'Nama warung')),
        if(borrowerType=='Perorangan')TextField(controller:person,decoration:const InputDecoration(labelText:'Nama perorangan')),
        DropdownButtonFormField<String>(value:variant,items:lpgVariants.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>variant=v!),decoration:const InputDecoration(labelText:'Jenis tabung')),
        TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah tabung sudah di luar')),
        TextField(controller:given,decoration:const InputDecoration(labelText:'Diserahkan oleh')),
        TextField(controller:received,decoration:const InputDecoration(labelText:'Diterima oleh')),
        TextField(controller:note,decoration:const InputDecoration(labelText:'Catatan / tanggal peminjaman')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
        final who=borrowerType=='Warung'?borrower:person.text.trim(),q=n(qty.text);if(who.isEmpty||q<=0){_msg('Nama peminjam dan jumlah wajib diisi.');return;}
        final id='SALDO-LUAR-${DateTime.now().millisecondsSinceEpoch}',now=dateNow();
        try{await _commit([
          {'sheet':'LPG_Peminjaman','id':id,'date':now,'borrowerType':borrowerType,'borrower':who,'variant':variant,'qty':q,'returned':0,'status':'Belum dikembalikan','givenBy':given.text,'receivedBy':received.text,'free':true,'openingBalance':true,'note':note.text},
          {'sheet':'LPG_MutasiStok','id':id,'date':now,'variant':variant,'type':'OPEN_BORROWED','qty':q,'note':'Saldo awal tabung di luar: $who'},
          {'sheet':'LPG_Riwayat','id':id,'date':now,'activity':'Saldo awal tabung dipinjam','description':'$q $variant berada di luar pada $who','by':given.text},
        ]);if(ctx.mounted)Navigator.pop(ctx);_msg('Saldo tabung di luar berhasil dicatat.');}catch(e){_msg('Gagal mencatat saldo: $e');}
      },child:const Text('Simpan Saldo Tabung Luar'))]
    )));
  }

  Future<void> _borrowDialog() async {
    String borrowerType='Warung', variant=lpgVariants.first, borrower=customers.isEmpty?'':_customerName(customers.first);
    final name=TextEditingController(), qty=TextEditingController(text:'1'), lender=TextEditingController(), receiver=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Peminjaman Tabung Kosong'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField(value:borrowerType,items:['Warung','Perorangan'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),decoration:const InputDecoration(labelText:'Jenis peminjam'),onChanged:(v)=>setD(()=>borrowerType=v!)),
        if(borrowerType=='Warung' && customers.isNotEmpty) DropdownButtonFormField<String>(value:borrower.isEmpty?_customerName(customers.first):borrower,items:customers.map((c)=>DropdownMenuItem(value:_customerName(c),child:Text(_customerName(c)))).toList(),decoration:const InputDecoration(labelText:'Nama warung'),onChanged:(v)=>setD(()=>borrower=v!)),
        if(borrowerType=='Perorangan') TextField(controller:name,decoration:const InputDecoration(labelText:'Nama perorangan')),
        DropdownButtonFormField(value:variant,items:lpgVariants.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),decoration:const InputDecoration(labelText:'Jenis tabung'),onChanged:(v)=>setD(()=>variant=v!)),
        TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah dipinjam')),
        TextField(controller:lender,decoration:const InputDecoration(labelText:'Diserahkan oleh')),
        TextField(controller:receiver,decoration:const InputDecoration(labelText:'Diterima oleh')),
        const Text('Peminjaman gratis, tanpa jaminan.',style:TextStyle(color:Colors.green)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
        final q=n(qty.text), st=_stock(variant);
        final who=borrowerType=='Warung'?borrower:name.text.trim();
        if(q<=0 || who.isEmpty){_msg('Peminjam dan jumlah wajib diisi.');return;}
        if(st['empty']!<q){_msg('Tabung kosong di gudang tidak cukup.');return;}
        final id='PINJAM-${DateTime.now().millisecondsSinceEpoch}', now=dateNow();
        try{await _commit([
          {'sheet':'LPG_Peminjaman','id':id,'date':now,'borrowerType':borrowerType,'borrower':who,'variant':variant,'qty':q,'returned':0,'status':'Belum dikembalikan','givenBy':lender.text,'receivedBy':receiver.text,'free':true},
          {'sheet':'LPG_MutasiStok','id':id,'date':now,'variant':variant,'type':'BORROW_EMPTY','qty':q,'note':'Dipinjam $who'},
          {'sheet':'LPG_Riwayat','id':id,'date':now,'activity':'Peminjaman','description':'$q $variant dipinjam $who','by':lender.text},
        ]);if(ctx.mounted)Navigator.pop(ctx);_msg('Peminjaman tercatat.');}catch(e){_msg('Gagal: $e');}
      },child:const Text('Catat Peminjaman'))]
    )));
  }

  Future<void> _returnBorrowDialog(Map<String,dynamic> loan) async {
    final qty=TextEditingController(text:'${n(loan['qty'])-n(loan['returned'])}');
    final receiver=TextEditingController(), returnedBy=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Pengembalian Tabung'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('${loan['borrower']}  -  ${loan['variant']}'),
      TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah dikembalikan')),
      TextField(controller:returnedBy,decoration:const InputDecoration(labelText:'Diserahkan kembali oleh')),
      TextField(controller:receiver,decoration:const InputDecoration(labelText:'Diterima oleh')),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
      final q=n(qty.text), remain=n(loan['qty'])-n(loan['returned']);
      if(q<=0||q>remain){_msg('Jumlah pengembalian tidak valid.');return;}
      final id='KEMBALI-${DateTime.now().millisecondsSinceEpoch}', now=dateNow();
      try{await _commit([
        {'sheet':'LPG_PengembalianPinjam','id':id,'date':now,'loanId':loan['id'],'borrower':loan['borrower'],'variant':loan['variant'],'qty':q,'returnedBy':returnedBy.text,'receivedBy':receiver.text},
        {'sheet':'LPG_MutasiStok','id':id,'date':now,'variant':loan['variant'],'type':'RETURN_BORROW_EMPTY','qty':q,'note':'Pengembalian dari ${loan['borrower']}'},
        {'sheet':'LPG_Riwayat','id':id,'date':now,'activity':'Pengembalian pinjaman','description':'$q ${loan['variant']} dari ${loan['borrower']}','by':receiver.text},
      ]);
      final newReturned=n(loan['returned'])+q;
      await _commit([{'sheet':'LPG_Peminjaman','id':loan['id'],'date':loan['date'],'borrowerType':loan['borrowerType'],'borrower':loan['borrower'],'variant':loan['variant'],'qty':loan['qty'],'returned':newReturned,'status':newReturned>=n(loan['qty'])?'Sudah dikembalikan':'Dikembalikan sebagian','givenBy':loan['givenBy'],'receivedBy':loan['receivedBy'],'free':true}]);
      if(ctx.mounted)Navigator.pop(ctx);_msg('Pengembalian tercatat.');
      }catch(e){_msg('Gagal: $e');}
    },child:const Text('Simpan Pengembalian'))]));
  }

  Future<void> _leakDialog() async {
    String variant = lpgVariants.first;
    String customer = customers.isEmpty ? 'Umum / Walk-in' : _customerName(customers.first);
    final qty = TextEditingController(text: '1');
    final reason = TextEditingController();
    final staff = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Retur Gas Bocor dari Pelanggan'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: variant,
                  items: lpgVariants.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  decoration: const InputDecoration(labelText: 'Jenis LPG'),
                  onChanged: (v) => setD(() => variant = v!),
                ),
                DropdownButtonFormField<String>(
                  value: customer,
                  items: ['Umum / Walk-in', ...customers.map(_customerName)]
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  decoration: const InputDecoration(labelText: 'Pelanggan'),
                  onChanged: (v) => setD(() => customer = v!),
                ),
                TextField(controller: qty, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Jumlah tabung bocor')),
                TextField(controller: reason,
                    decoration: const InputDecoration(labelText: 'Keterangan kebocoran')),
                TextField(controller: staff,
                    decoration: const InputDecoration(labelText: 'Petugas pengganti')),
                const Text('Pelanggan langsung diberi tabung pengganti tanpa biaya.',
                    style: TextStyle(color: Colors.green)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              FilledButton(
                onPressed: () async {
                  final q = n(qty.text);
                  final st = _stock(variant);
                  if (q <= 0 || st['full']! < q) {
                    _msg('Jumlah tidak valid atau stok tabung pengganti tidak cukup.');
                    return;
                  }
                  final id = 'RETUR-${DateTime.now().millisecondsSinceEpoch}';
                  final now = dateNow();
                  try {
                    await _commit([
                      {'sheet': 'LPG_Retur', 'id': id, 'date': now,
                        'direction': 'Dari Pelanggan', 'customer': customer,
                        'variant': variant, 'qty': q, 'reason': reason.text,
                        'replacementImmediate': true, 'staff': staff.text,
                        'status': 'Menunggu dikembalikan ke agen'},
                      {'sheet': 'LPG_MutasiStok', 'id': id, 'date': now,
                        'variant': variant, 'type': 'CUSTOMER_LEAK_RETURN', 'qty': q,
                        'note': 'Tabung bocor dari $customer; tabung pengganti langsung diberikan'},
                      {'sheet': 'LPG_Riwayat', 'id': id, 'date': now,
                        'activity': 'Retur bocor pelanggan',
                        'description': '$q $variant dari $customer', 'by': staff.text},
                    ]);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _msg('Retur dicatat. Tabung pengganti langsung diberikan.');
                  } catch (e) {
                    _msg('Gagal: $e');
                  }
                },
                child: const Text('Simpan Retur'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _agentReturnDialog() async {
    String variant = lpgVariants.first;
    String agent = lpgAgents.first;
    final qty = TextEditingController(text: '1');
    final replacement = TextEditingController(text: '0');
    final staff = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Retur Tabung Bocor ke Agen'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: agent,
                  items: lpgAgents.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  decoration: const InputDecoration(labelText: 'Agen'),
                  onChanged: (v) => setD(() => agent = v!),
                ),
                DropdownButtonFormField<String>(
                  value: variant,
                  items: lpgVariants.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  decoration: const InputDecoration(labelText: 'Jenis tabung'),
                  onChanged: (v) => setD(() => variant = v!),
                ),
                TextField(controller: qty, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Jumlah dikirim')),
                TextField(controller: replacement, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Tabung pengganti isi diterima sekarang')),
                TextField(controller: staff,
                    decoration: const InputDecoration(labelText: 'Petugas')),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              FilledButton(
                onPressed: () async {
                  final q = n(qty.text);
                  final rep = n(replacement.text);
                  final st = _stock(variant);
                  if (q <= 0 || st['quarantine']! < q || rep < 0 || rep > q) {
                    _msg('Jumlah retur atau tabung pengganti tidak valid.');
                    return;
                  }
                  final id = 'RETUR-AGEN-${DateTime.now().millisecondsSinceEpoch}';
                  final now = dateNow();
                  try {
                    await _commit([
                      {'sheet': 'LPG_Retur', 'id': id, 'date': now,
                        'direction': 'Ke Agen', 'agent': agent, 'variant': variant,
                        'qty': q, 'replacementQty': rep, 'staff': staff.text,
                        'status': rep >= q ? 'Selesai' : 'Menunggu penggantian'},
                      {'sheet': 'LPG_MutasiStok', 'id': '$id-Q', 'date': now,
                        'variant': variant, 'type': 'AGENT_LEAK_RETURN', 'qty': q,
                        'note': 'Retur bocor ke $agent'},
                      if (rep > 0)
                        {'sheet': 'LPG_MutasiStok', 'id': '$id-R', 'date': now,
                          'variant': variant, 'type': 'AGENT_REPLACEMENT_FULL', 'qty': rep,
                          'note': 'Pengganti dari $agent'},
                      if (rep > 0)
                        {'sheet': 'LPG_MutasiStok', 'id': '$id-RCV', 'date': now,
                          'variant': variant, 'type': 'AGENT_REPLACEMENT_RECEIVED', 'qty': rep,
                          'note': 'Penerimaan pengganti dari $agent'},
                    ]);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _msg('Retur agen tersimpan.');
                  } catch (e) {
                    _msg('Gagal: $e');
                  }
                },
                child: const Text('Simpan Retur Agen'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(String title, String value, IconData icon) => Card(child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[Icon(icon,color:green,size:28),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:12,color:Colors.black54)),Text(value,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))]))])));
  Widget _stockPage() => ListView(padding:const EdgeInsets.all(12),children:[
    const Text('Stok Gas Siap Jual dan Tabung',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),
    Card(color:const Color(0xFFE8F7EF),child:ListTile(
      leading:const Icon(Icons.outbound,color:Color(0xFF087F5B),size:32),
      title:const Text('Tabung yang Berada di Luar',style:TextStyle(fontWeight:FontWeight.bold)),
      subtitle:const Text('Catat tabung yang sudah dipinjamkan dan lihat daftar peminjam.'),
      trailing:const Icon(Icons.chevron_right),
      onTap:()=>setState(()=>tab=1),
    )),
    for(final v in lpgVariants) Builder(builder:(_){final s=_stock(v);return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(v,style:const TextStyle(fontWeight:FontWeight.bold)),Wrap(spacing:12,runSpacing:8,children:[Text('Isi: ${s['full']}'),Text('Kosong: ${s['empty']}'),Text('Dipinjam di luar: ${s['borrowed']}'),Text('Karantina: ${s['quarantine']}'),Text('Dalam retur agen: ${s['inTransit']}')])])));}),
    const SizedBox(height:12),FilledButton.icon(onPressed:_openingDialog,icon:const Icon(Icons.add_box),label:const Text('Input Stok Awal')),
    FilledButton.icon(onPressed:_stockOpnameDialog,icon:const Icon(Icons.fact_check),label:const Text('Stock Opname / Koreksi Fisik')),
  ]);

  Future<void> _openingDialog() async {
    String variant = lpgVariants.first;
    final full = TextEditingController(text: '0');
    final empty = TextEditingController(text: '0');
    final staff = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Stok Awal LPG'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: variant,
                items: lpgVariants.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                onChanged: (v) => setD(() => variant = v!),
                decoration: const InputDecoration(labelText: 'Jenis'),
              ),
              TextField(controller: full, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tabung isi di gudang')),
              TextField(controller: empty, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tabung kosong di gudang')),
              TextField(controller: staff,
                  decoration: const InputDecoration(labelText: 'Petugas')),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
              FilledButton(
                onPressed: () async {
                  final id = 'OPEN-${DateTime.now().millisecondsSinceEpoch}';
                  final now = dateNow();
                  try {
                    await _commit([
                      {'sheet': 'LPG_MutasiStok', 'id': '$id-F', 'date': now,
                        'variant': variant, 'type': 'OPEN_FULL', 'qty': n(full.text),
                        'note': 'Stok awal oleh ${staff.text}'},
                      {'sheet': 'LPG_MutasiStok', 'id': '$id-E', 'date': now,
                        'variant': variant, 'type': 'OPEN_EMPTY', 'qty': n(empty.text),
                        'note': 'Stok awal oleh ${staff.text}'},
                    ]);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    _msg('Gagal: $e');
                  }
                },
                child: const Text('Simpan Stok Awal'),
              ),
            ],
          );
        },
      ),
    );
  }


  Future<void> _stockOpnameDialog() async {
    String variant=lpgVariants.first;
    final full=TextEditingController(), empty=TextEditingController(), staff=TextEditingController(), reason=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Stock Opname Tabung'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField(value:variant,items:lpgVariants.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>variant=v!),decoration:const InputDecoration(labelText:'Jenis tabung')),
        Text('Catatan sistem: isi ${_stock(variant)['full']}  -  kosong ${_stock(variant)['empty']}'),
        TextField(controller:full,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah fisik tabung isi')),
        TextField(controller:empty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah fisik tabung kosong')),
        TextField(controller:reason,decoration:const InputDecoration(labelText:'Alasan selisih / pemeriksaan')),
        TextField(controller:staff,decoration:const InputDecoration(labelText:'Petugas pemeriksa')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
        final st=_stock(variant), deltaFull=n(full.text)-st['full']!, deltaEmpty=n(empty.text)-st['empty']!;
        final id='OPNAME-${DateTime.now().millisecondsSinceEpoch}',now=dateNow();
        try{await _commit([
          {'sheet':'LPG_MutasiStok','id':'$id-F','date':now,'variant':variant,'type':'MANUAL_FULL','delta':deltaFull,'qty':deltaFull.abs(),'note':'Stock opname: ${reason.text}; oleh ${staff.text}'},
          {'sheet':'LPG_MutasiStok','id':'$id-E','date':now,'variant':variant,'type':'MANUAL_EMPTY','delta':deltaEmpty,'qty':deltaEmpty.abs(),'note':'Stock opname: ${reason.text}; oleh ${staff.text}'},
          {'sheet':'LPG_Riwayat','id':id,'date':now,'activity':'Stock opname','description':'$variant; selisih isi $deltaFull; selisih kosong $deltaEmpty; ${reason.text}','by':staff.text}
        ]);if(ctx.mounted)Navigator.pop(ctx);_msg('Stock opname tersimpan.');}catch(e){_msg('Gagal: $e');}
      },child:const Text('Simpan Hasil Opname'))]
    )));
  }

  Widget _customersPage()=>ListView(padding:const EdgeInsets.all(12),children:[
    FilledButton.icon(onPressed:_customerDialog,icon:const Icon(Icons.person_add),label:const Text('Tambah Pelanggan')),
    for (final c in customers)
      Card(
        child: ListTile(
          title: Text(_customerName(c)),
          subtitle: Text(
            '${c['owner'] ?? ''}  -  ${c['address'] ?? ''}\\nWA: ${c['wa'] ?? '-'}',
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _customerDialog(c);
              if (v == 'delete') _voidLpgRecord('LPG_Pelanggan', c);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Hapus')),
            ],
            child: Row(mainAxisSize:MainAxisSize.min,children:[Text('3kg ${money.format(d(c['price_3']))}'),const SizedBox(width:4),const Icon(Icons.more_vert)]),
          ),
        ),
      ),
  ]);

  Widget _borrowPage()=>ListView(padding:const EdgeInsets.all(12),children:[
    const Text('TABUNG YANG BERADA DI LUAR',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    const Text('Catat juga saldo tabung yang sudah dipinjamkan sebelum aplikasi digunakan. Pencatatan saldo awal tidak mengurangi stok gudang lagi.'),
    const SizedBox(height:10),
    FilledButton.icon(onPressed:_openingBorrowedDialog,icon:const Icon(Icons.add_business),label:const Text('TAMBAH TABUNG YANG SUDAH DI LUAR')),
    OutlinedButton.icon(onPressed:_borrowDialog,icon:const Icon(Icons.add),label:const Text('Catat Peminjaman Baru dari Gudang')),
    for(final v in lpgVariants) Builder(builder:(_){final st=_stock(v);return Card(color:const Color(0xFFE8F7EF),child:ListTile(leading:const Icon(Icons.propane_tank),title:Text(v,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('Masih dipinjam di luar: ${st['borrowed']} tabung')));}),
    for(final loan in rows('LPG_Peminjaman').where((x)=>x['voided']!=true))
      Card(child:ListTile(
        title:Text('${loan['borrower']}  -  ${loan['variant']}'),
        subtitle:Text('Pinjam: ${loan['qty']}  -  Kembali: ${loan['returned']??0}  -  Sisa di luar: ${n(loan['qty'])-n(loan['returned'])}  -  ${loan['status']}\\nTanggal: ${loan['date']}\\nDiserahkan: ${loan['givenBy']}  -  Diterima: ${loan['receivedBy']}'),
        isThreeLine:true,
        trailing:PopupMenuButton<String>(
          onSelected:(v){
            if(v=='edit')_editLoanDialog(loan);
            if(v=='return' && loan['status']!='Sudah dikembalikan')_returnBorrowDialog(loan);
            if(v=='delete')_deleteLoan(loan);
          },
          itemBuilder:(_)=>[
            const PopupMenuItem(value:'edit',child:Text('Edit peminjaman')),
            if(loan['status']!='Sudah dikembalikan')const PopupMenuItem(value:'return',child:Text('Catat pengembalian')),
            const PopupMenuItem(value:'delete',child:Text('Hapus peminjaman')),
          ],
          child:const Icon(Icons.more_vert),
        ),
      )),
  ]);

  Widget _returnPage()=>ListView(padding:const EdgeInsets.all(12),children:[
    FilledButton.icon(onPressed:_leakDialog,icon:const Icon(Icons.report_problem),label:const Text('Retur Bocor dari Pelanggan')),
    FilledButton.icon(onPressed:_agentReturnDialog,icon:const Icon(Icons.local_shipping),label:const Text('Kirim Tabung Bocor ke Agen')),
    for(final r in rows('LPG_Retur')) Card(child:ListTile(title:Text('${r['direction']}  -  ${r['variant']}'),subtitle:Text('${r['customer']??r['agent']??''}  -  ${r['qty']} tabung  -  ${r['status']}'))),
  ]);


  Future<void> _shareReceipt(Map<String,dynamic> r) async {
    try {
      final doc=pw.Document();
      List<Map<String,dynamic>> items=[];
      try { final raw=jsonDecode('${r['items']??''}'); if(raw is List) items=raw.map((e)=>Map<String,dynamic>.from(e as Map)).toList(); } catch (_) {}
      if(items.isEmpty) items=[{'variant':r['variant'],'qty':r['qty'],'unitPrice':r['unitPrice'],'total':d(r['qty'])*d(r['unitPrice'])}];
      doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a5,margin:const pw.EdgeInsets.all(28),build:(ctx)=>[
        pw.Container(padding:const pw.EdgeInsets.all(16),decoration:pw.BoxDecoration(color:PdfColor.fromInt(0xFFE9F8F1),borderRadius:pw.BorderRadius.circular(8)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
          pw.Text('PANGKALAN LPG',style:pw.TextStyle(fontSize:20,fontWeight:pw.FontWeight.bold,color:PdfColor.fromInt(0xFF087F5B))),
          pw.Text('BUKTI PEMBAYARAN / STRUK PENJUALAN',style:const pw.TextStyle(fontSize:9)),
        ])),
        pw.SizedBox(height:16),
        pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('No. Transaksi: ${r['id']}',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),pw.Text(_formatLpgDate(r['date']))]),
        pw.Divider(),
        pw.Text('Pelanggan: ${r['customer']}'),
        if('${r['buyer']??''}'.isNotEmpty)pw.Text('Nama pembeli: ${r['buyer']}'),
        pw.SizedBox(height:12),
        pw.Table(border:pw.TableBorder.all(color:PdfColors.grey300),columnWidths:{0:const pw.FlexColumnWidth(3),1:const pw.FlexColumnWidth(1),2:const pw.FlexColumnWidth(2),3:const pw.FlexColumnWidth(2)},children:[
          pw.TableRow(decoration:const pw.BoxDecoration(color:PdfColors.grey200),children:['Jenis LPG','Qty','Harga','Jumlah'].map((x)=>pw.Padding(padding:const pw.EdgeInsets.all(7),child:pw.Text(x,style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:9)))).toList()),
          ...items.map((x)=>pw.TableRow(children:[pw.Padding(padding:const pw.EdgeInsets.all(7),child:pw.Text('${x['variant']}',style:const pw.TextStyle(fontSize:9))),pw.Padding(padding:const pw.EdgeInsets.all(7),child:pw.Text('${x['qty']}',style:const pw.TextStyle(fontSize:9))),pw.Padding(padding:const pw.EdgeInsets.all(7),child:pw.Text(money.format(d(x['unitPrice'])),style:const pw.TextStyle(fontSize:9))),pw.Padding(padding:const pw.EdgeInsets.all(7),child:pw.Text(money.format(d(x['total'])),style:const pw.TextStyle(fontSize:9))) ])),
        ]),
        pw.SizedBox(height:12),
        pw.Align(alignment:pw.Alignment.centerRight,child:pw.Container(width:220,padding:const pw.EdgeInsets.all(12),decoration:pw.BoxDecoration(border:pw.Border.all(color:PdfColors.grey400),borderRadius:pw.BorderRadius.circular(6)),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.stretch,children:[
          pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[pw.Text('TOTAL',style:pw.TextStyle(fontWeight:pw.FontWeight.bold)),pw.Text(money.format(d(r['total'])),style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:14))]),
          pw.SizedBox(height:5),pw.Text('Metode: ${r['payment']}'),pw.Text('Dibayar: ${money.format(d(r['paid']))}'),pw.Text('Sisa tagihan: ${money.format(d(r['remaining']))}'),
        ]))),
        pw.SizedBox(height:12),
        pw.Text('Tabung kosong diterima: ${r['emptyReceived']??0} tabung'),
        pw.Text('Petugas: ${r['staff']??'-'}'),
        pw.SizedBox(height:24),
        pw.Center(child:pw.Column(children:[pw.Text('Terima kasih atas kepercayaan Anda',style:pw.TextStyle(fontWeight:pw.FontWeight.bold,color:PdfColor.fromInt(0xFF087F5B))),pw.Text('Simpan struk ini sebagai bukti transaksi.',style:const pw.TextStyle(fontSize:9))])),
      ]));
      await Printing.sharePdf(bytes:await doc.save(),filename:'Struk_LPG_${r['id']}.pdf');
    } catch(e){_msg('Gagal membuat/membagikan PDF: $e');}
  }

  Future<void> _printLpgReceipt(Map<String,dynamic> r) async {
    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (devices.isEmpty) { _msg('Printer Bluetooth belum dipasangkan.'); return; }
      final connected = await PrintBluetoothThermal.connect(macPrinterAddress: devices.first.macAdress);
      if (!connected) { _msg('Tidak dapat terhubung ke printer.'); return; }
      final textReceipt = '       PANGKALAN LPG\n'
        '--------------------------------\nNo: ${r['id']}\nTanggal: ${_formatLpgDate(r['date'])}\n'
        'Pelanggan: ${r['customer']}\n${r['variant']} x ${r['qty']}\n'
        'Harga: ${money.format(d(r['unitPrice']))}\nTotal: ${money.format(d(r['total']))}\n'
        'Bayar: ${money.format(d(r['paid']))}\nSisa: ${money.format(d(r['remaining']))}\n'
        'Tabung kosong diterima: ${r['emptyReceived']}\n'
        '--------------------------------\nTerima kasih\n\n\n';
      await PrintBluetoothThermal.writeString(printText: PrintTextSize(size: 1, text: textReceipt));
      await PrintBluetoothThermal.disconnect;
      _msg('Struk LPG dikirim ke printer.');
    } catch (e) { _msg('Gagal mencetak struk: $e'); }
  }

  Future<void> _shareDebtReceipt(Map<String,dynamic> debt) async {
    try {
      final doc = pw.Document();
      final sale = rows('LPG_Penjualan').where((x) => '${x['id']}' == '${debt['saleId']}').cast<Map<String,dynamic>?>().firstWhere((x) => x != null, orElse: () => null);
      List<Map<String,dynamic>> items = [];
      if (sale != null) {
        try {
          final raw = jsonDecode('${sale['items'] ?? ''}');
          if (raw is List) items = raw.map((e) => Map<String,dynamic>.from(e as Map)).toList();
        } catch (_) {}
        if (items.isEmpty) {
          items = [{'variant': sale['variant'] ?? '-', 'qty': sale['qty'] ?? 0, 'unitPrice': sale['unitPrice'] ?? 0, 'total': sale['total'] ?? debt['total']}];
        }
      }
      final payments = rows('LPG_Pembayaran').where((x) => x['voided'] != true && ('${x['debtId'] ?? ''}' == '${debt['id']}' || '${x['saleId'] ?? ''}' == '${debt['saleId']}')).toList()
        ..sort((a,b) => '${a['date']}'.compareTo('${b['date']}'));
      final customer = customers.where((x) => '${x['name'] ?? x['customer'] ?? ''}' == '${debt['customer']}').toList();
      final address = customer.isEmpty ? (sale?['address'] ?? '-') : (customer.first['address'] ?? '-');
      final total = d(debt['total']);
      final paid = d(debt['paid']);
      final remaining = d(debt['remaining']);
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(26),
        build: (ctx) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE9F8F1), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('PANGKALAN LPG', style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF087F5B))),
              pw.Text('NOTA TAGIHAN & RIWAYAT PELUNASAN', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.SizedBox(height: 12),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('No. Nota: ${debt['id']}'), pw.Text(_formatLpgDate(debt['date']))]),
          pw.Text('No. Penjualan: ${debt['saleId'] ?? '-'}'),
          pw.Text('Pelanggan: ${debt['customer'] ?? '-'}'),
          pw.Text('Alamat: $address'),
          pw.Divider(),
          pw.Text('RINCIAN BARANG', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1), 2: const pw.FlexColumnWidth(2), 3: const pw.FlexColumnWidth(2)}, children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: ['Jenis LPG', 'Qty', 'Harga/tabung', 'Jumlah'].map((v) => pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(v, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))).toList()),
            ...items.map((x) => pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${x['variant'] ?? '-'}', style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${x['qty'] ?? 0}', style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(money.format(d(x['unitPrice'])), style: const pw.TextStyle(fontSize: 8))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(money.format(d(x['total'])), style: const pw.TextStyle(fontSize: 8))),
            ])),
          ]),
          pw.SizedBox(height: 10),
          pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(6)), child: pw.Column(children: [
            _pdfMoneyRow('Total tagihan', money.format(total)),
            _pdfMoneyRow('DP / pembayaran awal', money.format(paid)),
            _pdfMoneyRow('SISA TAGIHAN', money.format(remaining), bold: true, color: remaining > 0 ? PdfColors.red : PdfColors.green800),
          ])),
          pw.SizedBox(height: 12),
          pw.Text('RIWAYAT PEMBAYARAN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          if (payments.isEmpty) pw.Text('Belum ada pembayaran tercatat.', style: const pw.TextStyle(fontSize: 9)),
          if (payments.isNotEmpty) pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: ['Tanggal', 'Metode', 'Jumlah', 'Petugas'].map((v) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)))).toList()),
            ...payments.map((x) => pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(_formatLpgDate(x['date']), style: const pw.TextStyle(fontSize: 7))),
              pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${x['method'] ?? '-'}', style: const pw.TextStyle(fontSize: 7))),
              pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(money.format(d(x['amount'])), style: const pw.TextStyle(fontSize: 7))),
              pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${x['staff'] ?? '-'}', style: const pw.TextStyle(fontSize: 7))),
            ])),
          ]),
          pw.SizedBox(height: 14),
          pw.Text(remaining <= 0 ? 'LUNAS - Terima kasih atas pembayaran Anda.' : 'Mohon menyelesaikan sisa tagihan. Terima kasih atas kepercayaannya.', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF087F5B))),
          pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Dicetak: ${_formatLpgDate(DateTime.now().toIso8601String())}', style: const pw.TextStyle(fontSize: 8))),
        ],
      ));
      await Printing.sharePdf(bytes: await doc.save(), filename: 'Nota_Tagihan_Pelunasan_LPG_${debt['id']}.pdf');
    } catch (e) {
      _msg('Gagal membuat nota PDF: $e');
    }
  }

  pw.Widget _pdfMoneyRow(String label, String value, {bool bold = false, PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
      pw.Text(value, style: pw.TextStyle(fontSize: bold ? 12 : 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
    ]),
  );

  Future<void> _settleDebt(Map<String,dynamic> debt) async {
    String method='Tunai';
    final amount=TextEditingController(text:'${d(debt['remaining']).toStringAsFixed(0)}');
    final staff=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Pembayaran Kasbon LPG'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Sisa: ${money.format(d(debt['remaining']))}'),
        DropdownButtonFormField(value:method,items:['Tunai','QRIS'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setD(()=>method=v!),decoration:const InputDecoration(labelText:'Metode pembayaran')),
        if(method=='QRIS') Image.asset('assets/images/qris.png',height:120,errorBuilder:(_,__,___)=>const Text('QRIS')),
        TextField(controller:amount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah dibayar')),
        TextField(controller:staff,decoration:const InputDecoration(labelText:'Diterima oleh')),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
        final paid=d(amount.text), remain=d(debt['remaining']);
        if(paid<=0||paid>remain){_msg('Jumlah pembayaran tidak valid.');return;}
        final id='BAYAR-${DateTime.now().millisecondsSinceEpoch}', newRemain=remain-paid;
        try{
          await _commit([
            {'sheet':'LPG_Pembayaran','id':id,'date':dateNow(),'debtId':debt['id'],'customer':debt['customer'],'amount':paid,'method':method,'staff':staff.text},
            {'sheet':'LPG_Kasbon','id':debt['id'],'date':debt['date'],'customer':debt['customer'],'saleId':debt['saleId'],'total':debt['total'],'paid':d(debt['paid'])+paid,'remaining':newRemain,'status':newRemain<=0?'Lunas':'Belum Lunas'},
            {'sheet':'LPG_Riwayat','id':id,'date':dateNow(),'activity':'Pembayaran kasbon','description':'${debt['customer']} membayar ${money.format(paid)} via $method','by':staff.text}
          ]);
          if(ctx.mounted)Navigator.pop(ctx);_msg('Pembayaran kasbon tersimpan.');
        }catch(e){_msg('Gagal: $e');}
      },child:const Text('Simpan Pembayaran'))]
    )));
  }


  Future<void> _editSaleDialog(Map<String,dynamic> sale) async {
    try { final parsed=jsonDecode('${sale['items']??''}'); if(parsed is List && parsed.length>1){_msg('Transaksi multi-jenis LPG tersimpan sebagai satu nota. Untuk menjaga mutasi stok tiap jenis tetap akurat, edit transaksi multi-jenis perlu dilakukan melalui pembatalan nota lalu input ulang.');return;} } catch (_) {}
    final qtyC=TextEditingController(text:'${sale['qty']}');
    final priceC=TextEditingController(text:'${sale['unitPrice']}');
    final customerC=TextEditingController(text:'${sale['customer']}');
    final buyerC=TextEditingController(text:'${sale['buyer']??''}');
    final staffC=TextEditingController(text:'${sale['staff']??''}');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Edit Penjualan LPG'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:customerC,decoration:const InputDecoration(labelText:'Pelanggan')),
        TextField(controller:buyerC,decoration:const InputDecoration(labelText:'Nama pembeli')),
        TextField(controller:qtyC,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah tabung')),
        TextField(controller:priceC,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Harga per tabung')),
        TextField(controller:staffC,decoration:const InputDecoration(labelText:'Petugas')),
        const Text('Metode pembayaran tidak diubah pada menu edit ini.'),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),
        FilledButton(onPressed:()async{
          final oldQty=n(sale['qty']), newQty=n(qtyC.text), price=d(priceC.text);
          if(newQty<=0||price<=0||customerC.text.trim().isEmpty){_msg('Data penjualan tidak valid.');return;}
          final stockNow=_stock('${sale['variant']}');
          if(newQty>oldQty && stockNow['full']! < (newQty-oldQty)){_msg('Stok LPG isi tidak cukup untuk menambah jumlah penjualan.');return;}
          final total=newQty*price, oldTotal=d(sale['total']);
          final paid=d(sale['paid']);
          if(paid>total){_msg('Total baru tidak boleh lebih kecil dari pembayaran yang sudah diterima.');return;}
          final id='${sale['id']}', now=dateNow();
          final updated={...sale,'customer':customerC.text.trim(),'buyer':buyerC.text,'staff':staffC.text,'qty':newQty,'unitPrice':price,'total':total,'remaining':total-paid,'editedAt':now};
          final records=<Map<String,dynamic>>[
            {'sheet':'LPG_Penjualan',...updated},
            {'sheet':'LPG_MutasiStok','id':'$id-FULL','date':now,'variant':sale['variant'],'type':'SALE_FULL','qty':newQty,'note':'Penjualan $id (diperbarui)'},
            {'sheet':'LPG_MutasiStok','id':'$id-EMPTY','date':now,'variant':sale['variant'],'type':'SALE_EMPTY_IN','qty':newQty,'note':'Tabung kosong dari pelanggan $id (diperbarui)'},
          ];
          final oldPayments=rows('LPG_Pembayaran').where((x)=>x['saleId']==id && x['voided']!=true).toList();
          final oldPaid=oldPayments.fold<double>(0,(a,x)=>a+d(x['amount']));
          for(final paymentRow in oldPayments){
            final ratio=oldPaid<=0?0:d(paymentRow['amount'])/oldPaid;
            records.add({'sheet':'LPG_Pembayaran',...paymentRow,'amount':paid*ratio,'editedAt':now});
          }
          final debts=rows('LPG_Kasbon').where((x)=>x['saleId']==id && x['voided']!=true).toList();
          if(debts.isNotEmpty){
            final debt=debts.first;
            records.add({'sheet':'LPG_Kasbon','id':debt['id'],'date':debt['date'],'customer':customerC.text.trim(),'saleId':id,'total':total,'paid':paid,'remaining':total-paid,'status':total-paid<=0?'Lunas':'Belum Lunas'});
          } else if(total-paid>0){
            records.add({'sheet':'LPG_Kasbon','id':'$id-DEBT','date':sale['date'],'customer':customerC.text.trim(),'saleId':id,'total':total,'paid':paid,'remaining':total-paid,'status':'Belum Lunas'});
          }
          records.add({'sheet':'LPG_Riwayat','id':'EDIT-$id-$now','date':now,'activity':'Edit penjualan','description':'Penjualan $id diperbarui; total ${money.format(oldTotal)} menjadi ${money.format(total)}','by':staffC.text});
          try{await _commit(records);if(ctx.mounted)Navigator.pop(ctx);_msg('Penjualan diperbarui.');}catch(e){_msg('Gagal edit: $e');}
        },child:const Text('Simpan Perubahan'))
      ],
    ));
  }

  Future<void> _editLoanDialog(Map<String,dynamic> loan) async {
    if(n(loan['returned'])>0){_msg('Peminjaman yang sudah memiliki pengembalian tidak bisa diubah jumlahnya.');return;}
    final borrower=TextEditingController(text:'${loan['borrower']}');
    final qty=TextEditingController(text:'${loan['qty']}');
    final given=TextEditingController(text:'${loan['givenBy']??''}');
    final received=TextEditingController(text:'${loan['receivedBy']??''}');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Edit Peminjaman Tabung'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:borrower,decoration:const InputDecoration(labelText:'Nama peminjam')),
        TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Jumlah tabung')),
        TextField(controller:given,decoration:const InputDecoration(labelText:'Diserahkan oleh')),
        TextField(controller:received,decoration:const InputDecoration(labelText:'Diterima oleh')),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),
        FilledButton(onPressed:()async{
          final q=n(qty.text), old=n(loan['qty']);
          if(q<=0||borrower.text.trim().isEmpty){_msg('Nama dan jumlah wajib diisi.');return;}
          final stockNow=_stock('${loan['variant']}');
          if(loan['openingBalance']!=true && q>old && stockNow['empty']! < (q-old)){_msg('Stok tabung kosong tidak cukup untuk menambah jumlah pinjaman.');return;}
          final id='${loan['id']}', now=dateNow();
          try{
            await _commit([
              {'sheet':'LPG_Peminjaman',...loan,'borrower':borrower.text.trim(),'qty':q,'givenBy':given.text,'receivedBy':received.text,'editedAt':now},
              {'sheet':'LPG_MutasiStok','id':id,'date':loan['date'],'variant':loan['variant'],'type':loan['openingBalance']==true?'OPEN_BORROWED':'BORROW_EMPTY','qty':q,'note':'Dipinjam ${borrower.text.trim()} (diperbarui)'},
              {'sheet':'LPG_Riwayat','id':'EDIT-$id-$now','date':now,'activity':'Edit peminjaman','description':'Jumlah $old menjadi $q; peminjam ${borrower.text}','by':given.text},
            ]);
            if(ctx.mounted)Navigator.pop(ctx);_msg('Peminjaman diperbarui.');
          }catch(e){_msg('Gagal edit peminjaman: $e');}
        },child:const Text('Simpan'))
      ],
    ));
  }

  Future<void> _deleteLoan(Map<String,dynamic> loan) async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Hapus peminjaman?'),
      content:const Text('Catatan peminjaman dan pengembalian terkait akan ditandai batal. Riwayat tetap disimpan.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Hapus'))],
    ));
    if(ok!=true)return;
    final id='${loan['id']}',now=dateNow();
    final records=<Map<String,dynamic>>[
      {'sheet':'LPG_Peminjaman',...loan,'voided':true,'voidedAt':now},
      for(final m in rows('LPG_MutasiStok').where((x)=>'${x['id']}'==id || rows('LPG_PengembalianPinjam').any((ret)=>ret['loanId']==id && ret['id']==x['id'])))
        {'sheet':'LPG_MutasiStok',...m,'voided':true,'voidedAt':now},
      for(final r in rows('LPG_PengembalianPinjam').where((x)=>x['loanId']==id))
        {'sheet':'LPG_PengembalianPinjam',...r,'voided':true,'voidedAt':now},
      {'sheet':'LPG_Riwayat','id':'HAPUS-$id-$now','date':now,'activity':'Hapus peminjaman','description':'Peminjaman $id dibatalkan','by':'Aplikasi'},
    ];
    try{await _commit(records);_msg('Peminjaman dihapus dari daftar aktif.');}catch(e){_msg('Gagal hapus: $e');}
  }

  Future<void> _editDebtDialog(Map<String,dynamic> debt) async {
    final customer=TextEditingController(text:'${debt['customer']}');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Edit Data Kasbon'),
      content:TextField(controller:customer,decoration:const InputDecoration(labelText:'Nama pelanggan')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),
        FilledButton(onPressed:()async{
          if(customer.text.trim().isEmpty){_msg('Nama pelanggan wajib diisi.');return;}
          try{await _commit([{'sheet':'LPG_Kasbon',...debt,'customer':customer.text.trim(),'editedAt':dateNow()}]);if(ctx.mounted)Navigator.pop(ctx);_msg('Data kasbon diperbarui.');}
          catch(e){_msg('Gagal edit kasbon: $e');}
        },child:const Text('Simpan'))
      ],
    ));
  }

  Future<void> _deleteDebt(Map<String,dynamic> debt) async {
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Hapus kasbon?'),
      content:const Text('Kasbon akan ditandai batal. Riwayat pembayaran tetap dipertahankan.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Hapus'))],
    ));
    if(ok!=true)return;
    final now=dateNow(), id='${debt['id']}';
    try{
      await _commit([
        {'sheet':'LPG_Kasbon',...debt,'voided':true,'voidedAt':now},
        {'sheet':'LPG_Riwayat','id':'HAPUS-$id-$now','date':now,'activity':'Hapus kasbon','description':'Kasbon $id dibatalkan','by':'Aplikasi'},
      ]);
      _msg('Kasbon dibatalkan.');
    }catch(e){_msg('Gagal hapus kasbon: $e');}
  }

  Widget _salesPage() => ListView(
    padding: const EdgeInsets.all(10),
    children: [
      FilledButton.icon(
        onPressed: _saleDialog,
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Transaksi Penjualan LPG'),
      ),
      const SizedBox(height: 6),
      for (final r in rows('LPG_Penjualan').where((x) => x['voided'] != true).toList().reversed)
        Builder(builder: (context) {
          final items = _saleItems(r);
          final debt = _saleDebt(r);
          final remaining = debt == null ? 0.0 : d(debt['remaining']);
          final paid = d(r['paid']);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text('${r['customer'] ?? 'Umum / Walk-in'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                  if (debt != null)
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20)), child: Text('ADA TUNGGAKAN', style: TextStyle(color: Colors.red.shade800, fontSize: 10, fontWeight: FontWeight.bold)))
                  else
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)), child: Text('LUNAS', style: TextStyle(color: Colors.green.shade800, fontSize: 10, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 3),
                Text('${r['id'] ?? ''}  -  ${_formatLpgDate(r['date'])}', style: TextStyle(color: Colors.grey.shade700, fontSize: 11)),
                const Divider(height: 12),
                Row(children: const [
                  Expanded(flex: 4, child: Text('Jenis LPG', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
                  Expanded(flex: 2, child: Text('Banyak', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
                  Expanded(flex: 3, child: Text('Harga/tabung', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
                  Expanded(flex: 3, child: Text('Subtotal', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 3),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 4, child: Text('${item['variant'] ?? '-'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                      Expanded(flex: 2, child: Text('${n(item['qty'])} tabung', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                      Expanded(flex: 3, child: Text(money.format(d(item['unitPrice'])), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                      Expanded(flex: 3, child: Text(money.format(d(item['total'])), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                const Divider(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total pembelian', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(money.format(d(r['total'])), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
                const SizedBox(height: 3),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Pembayaran: ${_salePaymentLabel(r, debt)}', style: const TextStyle(fontSize: 12)),
                  if (debt == null) Text('Dibayar ${money.format(paid)}', style: const TextStyle(fontSize: 12)),
                ]),
                if (debt != null) ...[
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Sudah dibayar: ${money.format(d(debt['paid']))}', style: const TextStyle(fontSize: 12)),
                    Text('Sisa: ${money.format(remaining)}', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                  const SizedBox(height: 7),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, visualDensity: VisualDensity.compact),
                    onPressed: () => _settleDebt(debt),
                    icon: const Icon(Icons.payments, size: 17),
                    label: const Text('Bayar Tunggakan'),
                  )),
                ],
                Align(alignment: Alignment.centerRight, child: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'print') _printLpgReceipt(r);
                    if (v == 'wa') _shareReceipt(r);
                    if (v == 'void') _voidLpgRecord('LPG_Penjualan', r);
                    if (v == 'edit') _editSaleDialog(r);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit penjualan')),
                    PopupMenuItem(value: 'print', child: Text('Cetak struk Bluetooth')),
                    PopupMenuItem(value: 'wa', child: Text('Bagikan PDF')),
                    PopupMenuItem(value: 'void', child: Text('Hapus transaksi')),
                  ],
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.more_horiz)),
                )),
              ]),
            ),
          );
        }),
    ],
  );

  Widget _purchasePage()=>ListView(padding:const EdgeInsets.all(12),children:[
    FilledButton.icon(onPressed:_purchaseDialog,icon:const Icon(Icons.add_shopping_cart),label:const Text('Catat Pembelian dari Agen')),
    for(final r in rows('LPG_Pembelian').where((x)=>x['voided']!=true)) Card(child:ListTile(title:Text('${r['agent']}  -  ${r['variant']}'),subtitle:Text('${r['qty']} tabung  -  ${r['payment']}  -  ${_formatLpgDate(r['date'])}'),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='void')_voidLpgRecord('LPG_Pembelian',r);},itemBuilder:(_)=>const [PopupMenuItem(value:'void',child:Text('Batalkan pembelian'))],child:Text(money.format(d(r['total'])))))),
  ]);

  Widget _debtsPage()=>ListView(padding:const EdgeInsets.all(12),children:[
    for(final r in rows('LPG_Kasbon').where((x)=>x['voided']!=true)) Card(child:ListTile(
      title:Text('${r['customer']}'),
      subtitle:Text('Penjualan: ${r['saleId']}  -  ${r['status']}\nTotal ${money.format(d(r['total']))}  -  Dibayar ${money.format(d(r['paid']))}'),
      isThreeLine:true,
      trailing: PopupMenuButton<String>(
        onSelected: (v) { if (v == 'bayar') _settleDebt(r); if (v == 'pdf') _shareDebtReceipt(r); if (v == 'edit') _editDebtDialog(r); if (v == 'delete') _deleteDebt(r); },
        itemBuilder: (_) => [
          if (r['status'] != 'Lunas') const PopupMenuItem(value: 'bayar', child: Text('Bayar kasbon')),
          const PopupMenuItem(value: 'edit', child: Text('Edit kasbon')),
          const PopupMenuItem(value: 'delete', child: Text('Hapus kasbon')),
          const PopupMenuItem(value: 'pdf', child: Text('Cetak / bagikan nota PDF')),
        ],
        child: Padding(padding: const EdgeInsets.all(8), child: Text(r['status']=='Lunas' ? 'Lunas' : money.format(d(r['remaining'])))),
      ),
    )),
  ]);

  bool _inReportPeriod(Map<String,dynamic> r) {
    DateTime? dt = DateTime.tryParse('${r['date'] ?? ''}');
    if (dt == null) return false;
    if (reportMonthly) {
      return dt.year == reportDate.year && dt.month == reportDate.month;
    }
    return dt.year == reportDate.year && dt.month == reportDate.month && dt.day == reportDate.day;
  }

  Future<void> _shareLpgReportPdf() async {
    final sales = rows('LPG_Penjualan').where(_inReportPeriod).where((r) => r['voided'] != true).toList();
    final purchases = rows('LPG_Pembelian').where(_inReportPeriod).where((r) => r['voided'] != true).toList();
    final payments = rows('LPG_Pembayaran').where(_inReportPeriod).where((r) => r['voided'] != true).toList();
    final loans = rows('LPG_Peminjaman').where((r) => r['voided'] != true).toList();
    final consignments = [...rows('LPG_TitipanTabung'), ...rows('LPG_Titipan')].where((r) => r['voided'] != true).toList();
    final totalSales = sales.fold<double>(0, (a,r) => a + d(r['total']));
    final totalPurchases = purchases.fold<double>(0, (a,r) => a + d(r['total']));
    final cash = payments.where((r) => r['method'] == 'Tunai').fold<double>(0,(a,r)=>a+d(r['amount']));
    final qris = payments.where((r) => r['method'] == 'QRIS').fold<double>(0,(a,r)=>a+d(r['amount']));
    final activeDebt = rows('LPG_Kasbon').where((r)=>r['status']!='Lunas' && r['voided']!=true).fold<double>(0,(a,r)=>a+d(r['remaining']));
    final label = reportMonthly ? DateFormat('MMMM yyyy','id_ID').format(reportDate) : DateFormat('dd MMMM yyyy','id_ID').format(reportDate);
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(26), build: (ctx) => [
      pw.Container(padding: const pw.EdgeInsets.all(15), decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE9F8F1), borderRadius: pw.BorderRadius.circular(7)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('PANGKALAN LPG', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF087F5B))),
        pw.Text('LAPORAN ${reportMonthly ? 'BULANAN' : 'HARIAN'}  -  $label', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ])),
      pw.SizedBox(height: 14),
      pw.Text('RINGKASAN KEUANGAN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
        for (final pair in <List<String>>[
          ['Total penjualan', money.format(totalSales)], ['Total pembelian agen', money.format(totalPurchases)],
          ['Penerimaan tunai', money.format(cash)], ['Penerimaan QRIS', money.format(qris)], ['Sisa kasbon aktif', money.format(activeDebt)],
          ['Jumlah transaksi penjualan', '${sales.length}'], ['Jumlah transaksi pembelian', '${purchases.length}'],
        ]) pw.TableRow(children: pair.map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(7), child: pw.Text(v, style: const pw.TextStyle(fontSize: 9)))).toList()),
      ]),
      pw.SizedBox(height: 16),
      pw.Text('RINCIAN PENJUALAN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ...sales.map((r) {
        List<Map<String,dynamic>> items = [];
        try { final raw=jsonDecode('${r['items'] ?? ''}'); if(raw is List) items=raw.map((e)=>Map<String,dynamic>.from(e as Map)).toList(); } catch (_) {}
        if(items.isEmpty) items=[{'variant':r['variant']??'-','qty':r['qty']??0,'unitPrice':r['unitPrice']??0,'total':r['total']??0}];
        final customer = customers.where((c) => '${c['name'] ?? c['customer'] ?? ''}' == '${r['customer']}').toList();
        final address = customer.isEmpty ? '${r['address'] ?? '-'}' : '${customer.first['address'] ?? '-'}';
        return pw.Container(margin: const pw.EdgeInsets.only(top: 6), padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(4)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('${r['customer'] ?? 'Walk-in'}   -   ${_formatLpgDate(r['date'])}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text('Alamat: $address', style: const pw.TextStyle(fontSize: 8)),
          pw.Table(columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(0.7), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1.5)}, children: [
            pw.TableRow(children: ['Jenis LPG','Qty','Harga/tabung','Total'].map((v)=>pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(v, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)))).toList()),
            ...items.map((x)=>pw.TableRow(children: ['${x['variant']??'-'}','${x['qty']??0}',money.format(d(x['unitPrice'])),money.format(d(x['total']))].map((v)=>pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Text(v, style: const pw.TextStyle(fontSize: 7)))).toList())),
          ]),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Total: ${money.format(d(r['total']))}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)), pw.Text('Bayar: ${money.format(d(r['paid']))}   -   Sisa: ${money.format(d(r['remaining']))}', style: const pw.TextStyle(fontSize: 8))]),
          pw.Text('Metode: ${r['payment'] ?? '-'}${d(r['remaining']) > 0 ? '   -   ADA TUNGGAKAN' : ''}   -   Tabung kosong diterima: ${r['emptyReceived'] ?? 0}', style: pw.TextStyle(fontSize: 8, color: d(r['remaining']) > 0 ? PdfColors.red : PdfColors.black)),
        ]));
      }),
      pw.SizedBox(height: 14),
      pw.Text('RINCIAN PEMBELIAN AGEN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: ['Tanggal','Agen','Jenis','Jumlah','Harga beli','Total'].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)))).toList()),
        ...purchases.map((r)=>pw.TableRow(children: ['${_formatLpgDate(r['date'])}','${r['agent']??'-'}','${r['variant']??'-'}','${r['qty']??0}',money.format(d(r['unitPrice'])),money.format(d(r['total']))].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: const pw.TextStyle(fontSize: 7)))).toList())),
      ]),
      pw.SizedBox(height: 14),
      pw.Text('DAFTAR KASBON / TUNGGAKAN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: ['Pelanggan','No. Penjualan','Tanggal','Total','DP dibayar','Sisa'].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)))).toList()),
        ...rows('LPG_Kasbon').where((r)=>r['voided']!=true && d(r['remaining'])>0).map((r)=>pw.TableRow(children: ['${r['customer']??'-'}','${r['saleId']??'-'}','${_formatLpgDate(r['date'])}',money.format(d(r['total'])),money.format(d(r['paid'])),money.format(d(r['remaining']))].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: const pw.TextStyle(fontSize: 7)))).toList())),
      ]),
      pw.SizedBox(height: 14),
      pw.Text('TABUNG DIPINJAM / BERADA DI LUAR', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: ['Peminjam','Jenis','Tanggal pinjam','Jumlah','Kembali','Sisa di luar','Petugas'].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)))).toList()),
        ...loans.where((r)=>n(r['qty'])-n(r['returned'])>0).map((r)=>pw.TableRow(children: ['${r['borrower']??'-'}','${r['variant']??'-'}','${_formatLpgDate(r['date'])}','${r['qty']??0}','${r['returned']??0}','${n(r['qty'])-n(r['returned'])}','${r['givenBy']??'-'}'].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: const pw.TextStyle(fontSize: 7)))).toList())),
      ]),
      if (consignments.isNotEmpty) ...[
        pw.SizedBox(height: 12), pw.Text('TABUNG TITIPAN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: ['Nama penitip','Jenis','Jumlah','Tanggal','Keterangan'].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)))).toList()),
          ...consignments.map((r)=>pw.TableRow(children: ['${r['customer']??r['owner']??r['name']??'-'}','${r['variant']??r['type']??'-'}','${r['qty']??r['quantity']??0}','${_formatLpgDate(r['date'])}','${r['note']??r['status']??'-'}'].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: const pw.TextStyle(fontSize: 7)))).toList())),
        ]),
      ],
      pw.SizedBox(height: 14),
      pw.Text('REKAP INVENTARIS TABUNG', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey300), children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: ['Jenis','Isi di gudang','Kosong di gudang','Dipinjam di luar','Total gudang (isi+kosong)'].map((v)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(v, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)))).toList()),
        ...lpgVariants.map((v) { final st=_stock(v); return pw.TableRow(children: [v,'${st['full']}','${st['empty']}','${st['borrowed']}','${st['full']!+st['empty']!}'].map((x)=>pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(x, style: const pw.TextStyle(fontSize: 8)))).toList()); }),
      ]),
      pw.SizedBox(height: 8),
      pw.Text('Total semua jenis: isi ${lpgVariants.fold<int>(0,(a,v)=>a+_stock(v)['full']!)}, kosong ${lpgVariants.fold<int>(0,(a,v)=>a+_stock(v)['empty']!)}, dipinjam ${lpgVariants.fold<int>(0,(a,v)=>a+_stock(v)['borrowed']!)}, total di gudang ${lpgVariants.fold<int>(0,(a,v)=>a+_stock(v)['full']!+_stock(v)['empty']!)} tabung.', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 16),
      pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Dicetak: ${_formatLpgDate(DateTime.now().toIso8601String())}', style: const pw.TextStyle(fontSize: 8))),
    ]));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'Laporan_LPG_${reportMonthly ? 'Bulanan' : 'Harian'}_${DateFormat('yyyyMMdd').format(reportDate)}.pdf');
  }

  Widget _reportPage() {
    final sales = rows('LPG_Penjualan').where(_inReportPeriod).where((r) => r['voided'] != true).toList();
    final purchases = rows('LPG_Pembelian').where(_inReportPeriod).where((r) => r['voided'] != true).toList();
    final paidRows = rows('LPG_Pembayaran').where(_inReportPeriod).where((r) => r['voided'] != true).toList();
    final totalSales = sales.fold<double>(0, (a, r) => a + d(r['total']));
    final totalPurchases = purchases.fold<double>(0, (a, r) => a + d(r['total']));
    final cash = paidRows.where((r) => r['method'] == 'Tunai').fold<double>(0, (a,r)=>a+d(r['amount']));
    final qris = paidRows.where((r) => r['method'] == 'QRIS').fold<double>(0, (a,r)=>a+d(r['amount']));
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('Laporan LPG', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:_shareLpgReportPdf,icon:const Icon(Icons.picture_as_pdf),label:const Text('Cetak / Bagikan PDF'))),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Harian'), icon: Icon(Icons.today)),
          ButtonSegment(value: true, label: Text('Bulanan'), icon: Icon(Icons.calendar_month)),
        ],
        selected: {reportMonthly},
        onSelectionChanged: (v) => setState(() => reportMonthly = v.first),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(reportMonthly ? DateFormat('MMMM yyyy', 'id_ID').format(reportDate) : DateFormat('dd MMMM yyyy', 'id_ID').format(reportDate)),
        trailing: IconButton(icon: const Icon(Icons.date_range), onPressed: () async {
          if (reportMonthly) {
            final picked = await showDatePicker(context: context, initialDate: reportDate, firstDate: DateTime(2020), lastDate: DateTime(2100), helpText: 'Pilih tanggal dalam bulan laporan');
            if (picked != null) setState(() => reportDate = picked);
          } else {
            final picked = await showDatePicker(context: context, initialDate: reportDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (picked != null) setState(() => reportDate = picked);
          }
        }),
      ),
      _card('Total penjualan', money.format(totalSales), Icons.point_of_sale),
      _card('Total pembelian', money.format(totalPurchases), Icons.shopping_cart),
      _card('Penerimaan tunai', money.format(cash), Icons.payments),
      _card('Penerimaan QRIS', money.format(qris), Icons.qr_code),
      _card('Sisa kasbon aktif', money.format(rows('LPG_Kasbon').where((r)=>r['status']!='Lunas' && r['voided']!=true).fold<double>(0,(a,r)=>a+d(r['remaining']))), Icons.account_balance_wallet),
      _card('Jumlah transaksi penjualan', '${sales.length}', Icons.receipt_long),
      _card('Jumlah pembelian', '${purchases.length}', Icons.inventory),
      const Divider(),
      const Text('Posisi stok saat ini', style: TextStyle(fontWeight: FontWeight.bold)),
      for (final v in lpgVariants) Builder(builder: (_) {
        final s = _stock(v);
        final total = s['full']! + s['empty']! + s['quarantine']! + s['borrowed']! + s['inTransit']!;
        return _card('$v  -  Isi / kosong / dipinjam / karantina / retur agen',
          '${s['full']} / ${s['empty']} / ${s['borrowed']} / ${s['quarantine']} / ${s['inTransit']}  -  Total $total tabung', Icons.propane_tank);
      }),
    ]);
  }

  // -------------------------------------------------------------------------
  // MANAJEMEN DISTRIBUSI LPG
  // -------------------------------------------------------------------------
  static const Map<String, List<String>> _distributionRoutes = {
    'Senin': ['Kudadepa','Ragamukti','Balandongan','Tajurhalang','Karang Mulya','Cijoho','Kiarajangkung'],
    'Rabu': ['Jl Baru Cisinga','Pasirgede','Kiarajangkung','Cintamanah','Cimulya','Cilamgen'],
    'Kamis': ['Cijoho','Buniruum','Sukamulya','Pasirjaya','Kiarajangkung'],
    'Jumat': ['Jl Baru Cisinga','Pasirgede','Kiarajangkung'],
  };

  String _distributionRef() => 'DST-LPG-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}';
  List<Map<String,dynamic>> get _distributions => rows('LPG_Distribusi').where((x)=>x['voided']!=true).toList();
  List<Map<String,dynamic>> get _distributionExpenses => rows('LPG_BiayaDistribusi').where((x)=>x['voided']!=true).toList();
  double _distributionExpenseTotal(String id) => _distributionExpenses.where((x)=>'${x['distributionId']}'==id).fold<double>(0,(a,x)=>a+d(x['amount']));
  double _distributionSalesTotal(String id) => _distributionExpenses.where((x)=>false).fold<double>(0,(a,x)=>a); // sales detail is recorded on the distribution record

  Future<void> _distributionDialog({Map<String,dynamic>? existing}) async {
    String day='${existing?['day'] ?? 'Senin'}';
    String supplier='${existing?['supplier'] ?? (day=='Rabu'||day=='Jumat'?'PT. Petrolindo Jaya Utama':'PT. Mutiara Sri Rengganis')}';
    String status='${existing?['status'] ?? 'Terjadwal'}';
    final date=TextEditingController(text: existing?['date']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final route=TextEditingController(text: existing?['route']?.toString() ?? (_distributionRoutes[day]??[]).join(', '));
    final driver=TextEditingController(text: existing?['driver']?.toString() ?? 'Pemilik');
    final helper=TextEditingController(text: existing?['helper']?.toString() ?? 'Karyawan');
    final start=TextEditingController(text: existing?['startTime']?.toString() ?? '');
    final end=TextEditingController(text: existing?['endTime']?.toString() ?? '');
    final note=TextEditingController(text: existing?['note']?.toString() ?? '');
    final salesDetail=TextEditingController(text: existing?['salesDetail']?.toString() ?? '');
    final qty={for(final v in lpgVariants) v:TextEditingController(text:'${(jsonDecode('${existing?['items']??'{}'}') is Map ? (jsonDecode('${existing?['items']??'{}'}') as Map)[v]??0 : 0)}')};
    await showDialog(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:Text(existing==null?'Buat Distribusi LPG':'Edit Distribusi LPG'),
      content:SizedBox(width:520,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(value:day,decoration:const InputDecoration(labelText:'Jadwal hari'),items:_distributionRoutes.keys.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v){if(v!=null)setD((){day=v;supplier=(day=='Rabu'||day=='Jumat')?'PT. Petrolindo Jaya Utama':'PT. Mutiara Sri Rengganis';route.text=(_distributionRoutes[day]??[]).join(', ');});}),
        TextField(controller:date,decoration:const InputDecoration(labelText:'Tanggal (yyyy-MM-dd)')),
        DropdownButtonFormField<String>(value:supplier,decoration:const InputDecoration(labelText:'Agen'),items:const ['PT. Mutiara Sri Rengganis','PT. Petrolindo Jaya Utama'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v){if(v!=null)setD(()=>supplier=v);}),
        const SizedBox(height:8),Align(alignment:Alignment.centerLeft,child:Text('Jumlah tabung yang diambil',style:TextStyle(fontWeight:FontWeight.bold))),
        for(final v in lpgVariants) TextField(controller:qty[v],keyboardType:TextInputType.number,decoration:InputDecoration(labelText:v, suffixText:'tabung')),
        TextField(controller:route,maxLines:3,decoration:const InputDecoration(labelText:'Rute / daftar wilayah (bisa diedit)',helperText:'Pisahkan setiap wilayah dengan koma')),
        TextField(controller:driver,decoration:const InputDecoration(labelText:'Pengemudi')),
        TextField(controller:helper,decoration:const InputDecoration(labelText:'Karyawan / pembantu')),
        Row(children:[Expanded(child:TextField(controller:start,decoration:const InputDecoration(labelText:'Jam berangkat (HH:mm)'))),const SizedBox(width:8),Expanded(child:TextField(controller:end,decoration:const InputDecoration(labelText:'Jam kembali (HH:mm)')))]),
        DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Status'),items:const ['Terjadwal','Pembayaran Agen','Pembelian','Muat Tabung','Dalam Distribusi','Distribusi Selesai','Kembali ke Gudang','Ditutup'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v){if(v!=null)setD(()=>status=v);}),
        TextField(controller:salesDetail,maxLines:3,decoration:const InputDecoration(labelText:'Penjualan per pelanggan/wilayah (catatan)')),
        TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Catatan')), 
        const SizedBox(height:6),const Text('Upah otomatis per distribusi: pengemudi/pemilik Rp50.000 dan karyawan Rp65.000.',style:TextStyle(fontSize:12)),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
        final items={for(final v in lpgVariants) v:(int.tryParse(qty[v]!.text) ?? 0)};
        final totalQty=items.values.fold<int>(0,(a,b)=>a+b);
        if(totalQty<=0){_msg('Isi jumlah minimal satu jenis tabung.');return;}
        final id='${existing?['id'] ?? _distributionRef()}';
        final record={'sheet':'LPG_Distribusi','id':id,'date':date.text.trim(),'day':day,'supplier':supplier,'items':jsonEncode(items),'totalQty':totalQty,'route':route.text.trim(),'driver':driver.text.trim(),'helper':helper.text.trim(),'driverWage':50000,'helperWage':65000,'startTime':start.text.trim(),'endTime':end.text.trim(),'status':status,'salesDetail':salesDetail.text.trim(),'note':note.text.trim(),'updatedAt':dateNow()};
        try{await _commit([record,{'sheet':'LPG_Riwayat','id':'$id-${DateTime.now().millisecondsSinceEpoch}','date':dateNow(),'activity':existing==null?'Distribusi dibuat':'Distribusi diperbarui','description':'$id • $day • $totalQty tabung • $status','by':'Aplikasi'}]);if(ctx.mounted)Navigator.pop(ctx);_msg('Data distribusi tersimpan.');}catch(e){_msg('Gagal menyimpan distribusi: $e');}
      },child:const Text('Simpan'))]
    )));
  }

  Future<void> _distributionExpenseDialog(Map<String, dynamic> dist) async {
    String category = 'BBM';
    final amount = TextEditingController();
    final desc = TextEditingController();
    final paidBy = TextEditingController(text: 'Pemilik');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              title: const Text('Biaya Distribusi'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: category,
                      decoration: const InputDecoration(
                        labelText: 'Kategori biaya',
                      ),
                      items: const [
                        'BBM',
                        'Rokok',
                        'Kopi / Makanan',
                        'Parkir / Lainnya',
                        'Biaya Lainnya',
                      ].map((x) => DropdownMenuItem(
                            value: x,
                            child: Text(x),
                          )).toList(),
                      onChanged: (v) {
                        if (v != null) setD(() => category = v);
                      },
                    ),
                    TextField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah rupiah',
                      ),
                    ),
                    TextField(
                      controller: desc,
                      decoration: const InputDecoration(
                        labelText: 'Keterangan',
                      ),
                    ),
                    TextField(
                      controller: paidBy,
                      decoration: const InputDecoration(
                        labelText: 'Dibayar oleh',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () async {
                    final value = d(amount.text);
                    if (value <= 0) {
                      _msg('Masukkan jumlah biaya.');
                      return;
                    }

                    final id =
                        'DST-BIAYA-${DateTime.now().millisecondsSinceEpoch}';
                    try {
                      await _commit([
                        {
                          'sheet': 'LPG_BiayaDistribusi',
                          'id': id,
                          'distributionId': dist['id'],
                          'date': dateNow(),
                          'category': category,
                          'amount': value,
                          'description': desc.text.trim(),
                          'paidBy': paidBy.text.trim(),
                        },
                        {
                          'sheet': 'LPG_Riwayat',
                          'id': '$id-LOG',
                          'date': dateNow(),
                          'activity': 'Biaya distribusi',
                          'description':
                              '${dist['id']} • $category • ${money.format(value)}',
                          'by': paidBy.text.trim(),
                        },
                      ]);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      _msg('Gagal menyimpan biaya: $e');
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );

    amount.dispose();
    desc.dispose();
    paidBy.dispose();
  }

  Future<void> _closeDistributionDialog(Map<String,dynamic> dist) async {
    final Map<String,dynamic> loadedByType=(() { try { return Map<String,dynamic>.from(jsonDecode('${dist['items']??'{}'}')); } catch (_) { return <String,dynamic>{}; } })();
    final sold={for(final v in lpgVariants) v:TextEditingController(text:'0')};
    final empties={for(final v in lpgVariants) v:TextEditingController(text:'0')};
    final loaned={for(final v in lpgVariants) v:TextEditingController(text:'0')};
    final remaining={for(final v in lpgVariants) v:TextEditingController(text:'${loadedByType[v]??0}')};
    final salesAmount=TextEditingController(text:'${dist['salesAmount']??0}');
    final cashSales=TextEditingController(text:'${dist['cashSales']??0}');
    final qrisSales=TextEditingController(text:'${dist['qrisSales']??0}');
    final creditSales=TextEditingController(text:'${dist['creditSales']??0}');
    final mismatch=TextEditingController();
    await showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('Rekonsiliasi & Tutup Distribusi'),content:SizedBox(width:520,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('Referensi: ${dist['id']}'),
      for(final v in lpgVariants) Card(child:Padding(padding:const EdgeInsets.all(8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('$v • dimuat: ${loadedByType[v]??0} tabung',style:const TextStyle(fontWeight:FontWeight.bold)),
        Row(children:[Expanded(child:TextField(controller:sold[v],keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Terjual'))),const SizedBox(width:6),Expanded(child:TextField(controller:remaining[v],keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Isi kembali')))]),
        Row(children:[Expanded(child:TextField(controller:empties[v],keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Kosong diterima'))),const SizedBox(width:6),Expanded(child:TextField(controller:loaned[v],keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Dipinjam/dititip')))]),
      ]))),
      const Divider(),
      TextField(controller:salesAmount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Total nilai penjualan (Rp)')),
      Row(children:[Expanded(child:TextField(controller:cashSales,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Tunai (Rp)'))),const SizedBox(width:6),Expanded(child:TextField(controller:qrisSales,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'QRIS (Rp)')))]),
      TextField(controller:creditSales,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Kasbon (Rp)')),
      TextField(controller:mismatch,maxLines:2,decoration:const InputDecoration(labelText:'Penjelasan selisih (jika ada)')),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Batal')),FilledButton(onPressed:()async{
      final totalLoaded=loadedByType.values.fold<int>(0,(a,x)=>a+n(x));
      final totalSold=sold.values.fold<int>(0,(a,x)=>a+n(x.text));
      final totalLoaned=loaned.values.fold<int>(0,(a,x)=>a+n(x.text));
      final totalRemaining=remaining.values.fold<int>(0,(a,x)=>a+n(x.text));
      final diff=totalLoaded-totalSold-totalLoaned-totalRemaining;
      if(diff!=0&&mismatch.text.trim().isEmpty){_msg('Jelaskan selisih tabung sebelum menutup distribusi.');return;}
      final closeDate=dateNow(),distId='${dist['id']}';
      final records=<Map<String,dynamic>>[
        {'sheet':'LPG_Distribusi',...dist,'loadedQty':totalLoaded,'soldQty':totalSold,'emptyReceived':empties.values.fold<int>(0,(a,x)=>a+n(x.text)),'loanedQty':totalLoaned,'returnedFullQty':totalRemaining,'soldByType':jsonEncode({for(final v in lpgVariants)v:n(sold[v]!.text)}),'emptyByType':jsonEncode({for(final v in lpgVariants)v:n(empties[v]!.text)}),'loanedByType':jsonEncode({for(final v in lpgVariants)v:n(loaned[v]!.text)}),'returnedByType':jsonEncode({for(final v in lpgVariants)v:n(remaining[v]!.text)}),'salesAmount':d(salesAmount.text),'cashSales':d(cashSales.text),'qrisSales':d(qrisSales.text),'creditSales':d(creditSales.text),'reconciliationDiff':diff,'reconciliationNote':mismatch.text.trim(),'status':'Ditutup','closedAt':closeDate},
        for(final v in lpgVariants) if(n(loadedByType[v])>0) {'sheet':'LPG_MutasiStok','id':'$distId-DIST-$v-LOAD','date':closeDate,'variant':v,'type':'DIST_LOAD_FULL','qty':n(loadedByType[v]),'note':'Tabung dimuat untuk distribusi $distId'},
        for(final v in lpgVariants) if(n(remaining[v]!.text)>0) {'sheet':'LPG_MutasiStok','id':'$distId-DIST-$v-RETURN','date':closeDate,'variant':v,'type':'DIST_RETURN_FULL','qty':n(remaining[v]!.text),'note':'Tabung isi kembali dari distribusi $distId'},
        for(final v in lpgVariants) if(n(empties[v]!.text)>0) {'sheet':'LPG_MutasiStok','id':'$distId-DIST-$v-EMPTY','date':closeDate,'variant':v,'type':'DIST_RETURN_EMPTY','qty':n(empties[v]!.text),'note':'Tabung kosong diterima pada distribusi $distId'},
        for(final v in lpgVariants) if(n(loaned[v]!.text)>0) {'sheet':'LPG_MutasiStok','id':'$distId-DIST-$v-LOAN','date':closeDate,'variant':v,'type':'DIST_LOAN_FULL','qty':n(loaned[v]!.text),'note':'Tabung dipinjamkan/dititipkan pada distribusi $distId'},
        {'sheet':'LPG_Riwayat','id':'$distId-CLOSE-${DateTime.now().millisecondsSinceEpoch}','date':closeDate,'activity':'Distribusi ditutup','description':'$distId • dimuat $totalLoaded • terjual $totalSold • kembali $totalRemaining • selisih $diff','by':'Aplikasi'},
      ];
      try{await _commit(records);if(ctx.mounted)Navigator.pop(ctx);}catch(e){_msg('Gagal menutup distribusi: $e');}
    },child:const Text('Tutup Distribusi'))]));
  }

  Widget _distributionPage()=>ListView(padding:const EdgeInsets.all(12),children:[
    Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Jadwal Distribusi LPG',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
      for(final entry in _distributionRoutes.entries) Padding(padding:const EdgeInsets.only(top:7),child:Text('${entry.key}: ${entry.value.join(' • ')}',style:const TextStyle(fontSize:12))),
      const SizedBox(height:8),const Text('Jadwal dan rute di atas dapat diubah saat membuat atau mengedit distribusi.',style:TextStyle(fontSize:12,color:Colors.black54)),
    ]))),
    FilledButton.icon(onPressed:()=>_distributionDialog(),icon:const Icon(Icons.add_road),label:const Text('Buat Distribusi Baru')),
    const SizedBox(height:6),
    for(final r in _distributions.reversed) Builder(builder:(ctx){
      final id='${r['id']}';final expenses=_distributionExpenseTotal(id);final items=(() { try { return Map<String,dynamic>.from(jsonDecode('${r['items']??'{}'}')); } catch (_) { return <String,dynamic>{}; } })();
      return Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Expanded(child:Text(id,style:const TextStyle(fontWeight:FontWeight.bold))),Chip(label:Text('${r['status']??'Terjadwal'}'))]),
        Text('${r['day']??'-'} • ${_formatLpgDate(r['date'])} • ${r['supplier']??'-'}'),
        Text('Tabung: ${lpgVariants.map((v)=>'$v ${items[v]??0}').join(' | ')}'),
        Text('Rute: ${r['route']??'-'}',maxLines:2,overflow:TextOverflow.ellipsis),
        Text('Pengemudi: ${r['driver']??'-'} • Karyawan: ${r['helper']??'-'}'),
        Text('Upah: ${money.format(d(r['driverWage']))} + ${money.format(d(r['helperWage']))} • Biaya tercatat: ${money.format(expenses)}'),
        if(r['status']=='Ditutup') Text('Penjualan: ${money.format(d(r['salesAmount']))} • Tunai ${money.format(d(r['cashSales']))} • QRIS ${money.format(d(r['qrisSales']))} • Kasbon ${money.format(d(r['creditSales']))}'),
        if(r['status']=='Ditutup') Text('Rekonsiliasi: dimuat ${r['loadedQty']??0}, terjual ${r['soldQty']??0}, kosong ${r['emptyReceived']??0}, dipinjam/dititip ${r['loanedQty']??0}, kembali ${r['returnedFullQty']??0}, selisih ${r['reconciliationDiff']??0}'),
        Wrap(spacing:6,children:[if(r['status']!='Ditutup') OutlinedButton.icon(onPressed:()=>_distributionDialog(existing:r),icon:const Icon(Icons.edit,size:16),label:const Text('Edit')),OutlinedButton.icon(onPressed:()=>_distributionExpenseDialog(r),icon:const Icon(Icons.receipt_long,size:16),label:const Text('Tambah Biaya')),if(r['status']!='Ditutup')FilledButton.tonalIcon(onPressed:()=>_closeDistributionDialog(r),icon:const Icon(Icons.task_alt,size:16),label:const Text('Rekonsiliasi / Tutup'))]),
      ])));
    }),
    const Divider(),
    const Text('Ringkasan biaya distribusi',style:TextStyle(fontWeight:FontWeight.bold)),
    for(final r in _distributionExpenses.reversed.take(30)) ListTile(dense:true,title:Text('${r['category']} • ${money.format(d(r['amount']))}'),subtitle:Text('${r['distributionId']} • ${r['description']??''} • ${_formatLpgDate(r['date'])}')),
  ]);

  Widget _distributionReportPage() {
    final records=_distributions.where((r){final dt=DateTime.tryParse('${r['date']??''}');if(dt==null)return false;return reportMonthly?(dt.year==reportDate.year&&dt.month==reportDate.month):(dt.year==reportDate.year&&dt.month==reportDate.month&&dt.day==reportDate.day);}).toList();
    final expenses=_distributionExpenses.where((e){final dt=DateTime.tryParse('${e['date']??''}');if(dt==null)return false;return reportMonthly?(dt.year==reportDate.year&&dt.month==reportDate.month):(dt.year==reportDate.year&&dt.month==reportDate.month&&dt.day==reportDate.day);}).toList();
    final sales=records.fold<double>(0,(a,r)=>a+d(r['salesAmount']));
    final cash=records.fold<double>(0,(a,r)=>a+d(r['cashSales']));
    final qris=records.fold<double>(0,(a,r)=>a+d(r['qrisSales']));
    final credit=records.fold<double>(0,(a,r)=>a+d(r['creditSales']));
    final expense=expenses.fold<double>(0,(a,e)=>a+d(e['amount']));
    final wages=records.fold<double>(0,(a,r)=>a+d(r['driverWage'])+d(r['helperWage']));
    return ListView(padding:const EdgeInsets.all(12),children:[
      SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('Harian')),ButtonSegment(value:true,label:Text('Bulanan'))],selected:{reportMonthly},onSelectionChanged:(v)=>setState(()=>reportMonthly=v.first)),
      ListTile(title:Text(DateFormat(reportMonthly?'MMMM yyyy':'dd MMMM yyyy','id_ID').format(reportDate)),trailing:IconButton(icon:const Icon(Icons.calendar_month),onPressed:()async{final picked=await showDatePicker(context:context,initialDate:reportDate,firstDate:DateTime(2020),lastDate:DateTime(2100));if(picked!=null)setState(()=>reportDate=picked);})),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        _reportLine('Jumlah distribusi','${records.length} trip'),_reportLine('Nilai penjualan',money.format(sales)),_reportLine('Tunai',money.format(cash)),_reportLine('QRIS',money.format(qris)),_reportLine('Kasbon',money.format(credit)),_reportLine('Biaya operasional',money.format(expense)),_reportLine('Upah tetap distribusi',money.format(wages)),_reportLine('Sisa setelah biaya & upah',money.format(sales-expense-wages)),
      ]))),
      const Text('Rincian distribusi',style:TextStyle(fontWeight:FontWeight.bold)),
      for(final r in records) Card(child:ListTile(title:Text('${r['id']} • ${r['day']}'),subtitle:Text('${r['supplier']} • ${r['totalQty']} tabung • ${r['status']}\nPenjualan ${money.format(d(r['salesAmount']))} • Biaya ${money.format(_distributionExpenseTotal('${r['id']}'))}'),isThreeLine:true)),
      const Text('Rincian biaya',style:TextStyle(fontWeight:FontWeight.bold)),
      for(final e in expenses) ListTile(dense:true,title:Text('${e['category']} • ${money.format(d(e['amount']))}'),subtitle:Text('${e['distributionId']} • ${e['description']??''}')),
    ]);
  }

  Widget _reportLine(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(child:Text(label)),Text(value,style:const TextStyle(fontWeight:FontWeight.w600))]));

  Widget _historyPage()=>ListView(padding:const EdgeInsets.all(12),children:[
    for(final r in rows('LPG_Riwayat').reversed) ListTile(leading:const Icon(Icons.history),title:Text(r['activity']??''),subtitle:Text('${r['description']??''}  -  ${_formatLpgDate(r['date'])}')),
    for(final r in rows('LPG_Penjualan').where((x)=>x['voided']!=true).toList().reversed) ListTile(leading:const Icon(Icons.receipt),title:Text('Penjualan ${r['id']}'),subtitle:Text('${r['customer']}  -  ${_formatLpgDate(r['date'])}')),
  ]);

  @override
  Widget build(BuildContext context) {
    final pages=<Widget>[_salesPage(),_borrowPage(),_purchasePage(),_customersPage(),_stockPage(),_returnPage(),_debtsPage(),_reportPage(),_historyPage(),_distributionPage(),_distributionReportPage()];
    return Scaffold(
      appBar:AppBar(title:const Text('Pangkalan GAS LPG'),backgroundColor:green,foregroundColor:Colors.white,actions:[IconButton(tooltip:'Tabung di luar',onPressed:()=>setState(()=>tab=1),icon:const Icon(Icons.outbound)),IconButton(tooltip:'Laporan harian/bulanan',onPressed:()=>setState(()=>tab=7),icon:const Icon(Icons.analytics_outlined)),IconButton(onPressed:_load,icon:const Icon(Icons.refresh))]),
      body:loading?const Center(child:CircularProgressIndicator()):pages[tab],
      floatingActionButton: (tab==7 || tab==9 || tab==10) ? null : FloatingActionButton.extended(
        heroTag: 'lpg_report_shortcut',
        backgroundColor: green,
        foregroundColor: Colors.white,
        onPressed: () => setState(() => tab=7),
        icon: const Icon(Icons.analytics_outlined),
        label: const Text('Laporan'),
      ),
      bottomNavigationBar:Container(color:Colors.white,height:68,child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
        for(int i=0;i<tabs.length;i++) InkWell(onTap:()=>setState(()=>tab=i),child:Container(width:96,padding:const EdgeInsets.symmetric(horizontal:5,vertical:8),decoration:BoxDecoration(border:Border(top:BorderSide(color:tab==i?green:Colors.transparent,width:3))),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon([Icons.point_of_sale,Icons.outbound,Icons.shopping_cart,Icons.people,Icons.inventory,Icons.report,Icons.account_balance_wallet,Icons.analytics,Icons.history,Icons.local_shipping,Icons.summarize][i],color:tab==i?green:Colors.grey),Text(tabs[i],textAlign:TextAlign.center,maxLines:2,style:TextStyle(fontSize:10,fontWeight:tab==i?FontWeight.bold:FontWeight.normal,color:tab==i?green:Colors.grey[700]))]))),
      ]))),
    );
  }
}
