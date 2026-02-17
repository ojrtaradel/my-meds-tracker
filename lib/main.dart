import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// --- PDF, PRINTING, SHARE & WEB IMPORTS ---
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html; 

// --- IMPORT SECRETS ---
import 'secrets.dart'; // Loads passwords from the hidden file

// --- GLOBAL APP CONFIGURATION ---
class AppConfig {
  static bool isPrivacyMode = false; // Toggles based on login
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(AppRoot());
}

DateTime getManilaTime() {
  return DateTime.now().toUtc().add(const Duration(hours: 8));
}

class AppRoot extends StatefulWidget {
  @override
  _AppRootState createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Med Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        cardTheme: CardThemeData(surfaceTintColor: Colors.white),
      ),
      home: FutureBuilder(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _buildErrorScreen(snapshot.error.toString());
          if (snapshot.connectionState == ConnectionState.waiting) return _buildLoadingScreen();
          return AuthCheck(); 
        },
      ),
    );
  }

  Widget _buildErrorScreen(String error) => Scaffold(
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error, color: Colors.red, size: 50),
      Text("Connection Failed", style: TextStyle(fontWeight: FontWeight.bold)),
      Padding(padding: EdgeInsets.all(20), child: Text(error, textAlign: TextAlign.center))
    ])),
  );

  Widget _buildLoadingScreen() => Scaffold(
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      CircularProgressIndicator(), SizedBox(height: 20), Text("Connecting...")
    ])),
  );
}

// --- DATA MODELS ---

class Ingredient {
  String name;
  double mg;
  Ingredient(this.name, this.mg);
  Map<String, dynamic> toMap() => {'name': name, 'mg': mg};
  factory Ingredient.fromMap(Map<String, dynamic> map) => Ingredient(map['name'], map['mg']);
}

class RefillLog {
  DateTime date;
  int quantity;
  String source;
  double cost;
  String? dispenser;

  RefillLog(this.date, this.quantity, this.source, {this.cost = 0.0, this.dispenser});

  Map<String, dynamic> toMap() => {
    'date': date.toIso8601String(),
    'quantity': quantity,
    'source': source,
    'cost': cost,
    'dispenser': dispenser,
  };

  factory RefillLog.fromMap(Map<String, dynamic> map) {
    // --- PRIVACY MODE (LOGS) ---
    String finalDispenser = map['dispenser'] ?? "";
    String finalSource = map['source'] ?? "";

    if (AppConfig.isPrivacyMode) {
      if (finalDispenser.isNotEmpty) finalDispenser = "Community Pharmacy";
      if (finalSource == "DOH") finalSource = "Gov Program";
    }

    return RefillLog(
      DateTime.parse(map['date']),
      map['quantity'],
      finalSource.isNotEmpty ? finalSource : (map['source'] ?? "Unknown"),
      cost: (map['cost'] ?? 0.0).toDouble(),
      dispenser: finalDispenser.isEmpty ? null : finalDispenser,
    );
  }
}

class Medication {
  String id; 
  String brandName;
  String source;
  int currentStock; 
  int cycleDuration; 
  DateTime lastRefillDate;
  DateTime lastDeductionDate;
  String? lastDispenser; 
  List<Ingredient> ingredients; 
  bool isCritical;
  List<RefillLog> history; 

  Medication({
    required this.id,
    required this.brandName,
    required this.ingredients,
    required this.source, 
    required this.currentStock, 
    required this.cycleDuration,
    required this.lastRefillDate,
    required this.lastDeductionDate,
    this.lastDispenser,
    this.isCritical = false,
    List<RefillLog>? history,
  }) : this.history = history ?? [];

  Map<String, dynamic> toMap() {
    return {
      'brandName': brandName,
      'source': source,
      'currentStock': currentStock,
      'cycleDuration': cycleDuration,
      'lastRefillDate': lastRefillDate.toIso8601String(),
      'lastDeductionDate': lastDeductionDate.toIso8601String(),
      'lastDispenser': lastDispenser,
      'isCritical': isCritical ? 1 : 0,
      'ingredients': ingredients.map((x) => x.toMap()).toList(),
      'history': history.map((x) => x.toMap()).toList(),
    };
  }

  factory Medication.fromMap(Map<String, dynamic> map, String docId) {
    // --- PRIVACY MODE (MEDICINES) ---
    String bName = map['brandName'] ?? 'Unknown';
    String src = map['source'] ?? 'DOH';
    
    if (AppConfig.isPrivacyMode) {
      String lower = bName.toLowerCase();
      // Masking Logic
      if (lower.contains('duo') || lower.contains('rifam')) bName = "Antibiotic (Combined)";
      else if (lower.contains('teld') || lower.contains('dolute')) bName = "Antiviral (Maintenance)";
      else if (lower.contains('cotri')) bName = "Antibiotic (Prophylaxis)";
      else if (lower.contains('rosu')) bName = "Cholesterol Med";
      else if (lower.contains('clop')) bName = "Blood Thinner";
      else if (lower.contains('amlo')) bName = "Blood Pressure Med";
      else if (lower.contains('valsa')) bName = "Heart Med (V)";
      else if (lower.contains('vit')) bName = "Vitamin Supplement";
      else bName = "Maintenance Med";

      src = src == "DOH" ? "Gov Program" : "Private";
    }

    return Medication(
      id: docId,
      brandName: bName,
      source: src,
      currentStock: map['currentStock'] ?? map['initialStock'] ?? 0,
      cycleDuration: map['cycleDuration'] ?? 30,
      lastRefillDate: DateTime.tryParse(map['lastRefillDate'] ?? map['lastStockUpdate'] ?? "") ?? getManilaTime(),
      lastDeductionDate: DateTime.tryParse(map['lastDeductionDate'] ?? "") ?? getManilaTime(),
      lastDispenser: map['lastDispenser'],
      isCritical: (map['isCritical'] ?? 0) == 1,
      ingredients: List<Ingredient>.from(map['ingredients']?.map((x) => Ingredient.fromMap(x)) ?? []),
      history: List<RefillLog>.from(map['history']?.map((x) => RefillLog.fromMap(x)) ?? []),
    );
  }

  double get totalDosage {
    double sum = 0;
    for (var i in ingredients) sum += i.mg;
    return sum;
  }

  int get remainingPills => currentStock;

  DateTime get nextRefillDate => lastRefillDate.add(Duration(days: cycleDuration));
  bool get isOOP => source.contains("OOP") || source.contains("Private"); 
  
  bool get isInCriticalWindow {
    final daysUntilDue = nextRefillDate.difference(getManilaTime()).inDays;
    return daysUntilDue <= 10;
  }

  bool get isWeekendDue {
    int weekday = nextRefillDate.weekday;
    return weekday == DateTime.saturday || weekday == DateTime.sunday;
  }
}

// --- FILE HELPERS ---

void downloadFile(List<int> bytes, String downloadName) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute("download", downloadName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

Future<void> smartSaveImage(List<int> bytes, String fileName) async {
  if (kIsWeb) {
    downloadFile(bytes, fileName);
  } else {
    final xFile = XFile.fromData(
      Uint8List.fromList(bytes),
      mimeType: 'image/png',
      name: fileName
    );
    await Share.shareXFiles([xFile], text: 'My Med Tracker Snapshot');
  }
}

// --- EXPORT PREVIEW SCREEN ---
class ExportPreviewScreen extends StatelessWidget {
  final List<Medication> meds;

  ExportPreviewScreen({required this.meds});

  Future<pw.Document> _buildReportDoc() async {
    final pdf = pw.Document();
    Map<String, List<Map<String, dynamic>>> groupedLogs = {};
    Map<String, double> dailyTotals = {};

    for (var med in meds) {
      for (var log in med.history) {
        String dateKey = DateFormat('yyyy-MM-dd').format(log.date);
        if (!groupedLogs.containsKey(dateKey)) {
          groupedLogs[dateKey] = [];
          dailyTotals[dateKey] = 0.0;
        }
        groupedLogs[dateKey]!.add({'brand': med.brandName, 'log': log});
        dailyTotals[dateKey] = dailyTotals[dateKey]! + log.cost;
      }
    }
    List<String> sortedDates = groupedLogs.keys.toList()..sort((a, b) => b.compareTo(a));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(AppConfig.isPrivacyMode ? "Medication Report" : "Medication Refill Report", style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)), pw.Text(DateFormat('MMM dd, yyyy').format(getManilaTime()), style: pw.TextStyle(color: PdfColors.grey))])),
            pw.SizedBox(height: 20),
            ...sortedDates.map((dateKey) {
              DateTime dateObj = DateTime.parse(dateKey);
              List<Map<String, dynamic>> items = groupedLogs[dateKey]!;
              double total = dailyTotals[dateKey]!;
              return pw.Container(margin: pw.EdgeInsets.only(bottom: 20), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Container(color: PdfColors.grey200, padding: pw.EdgeInsets.all(6), child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(DateFormat('MMMM dd, yyyy').format(dateObj), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text("Total Spend: PHP ${total.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold))])),
                pw.Table(border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5), children: [
                  pw.TableRow(decoration: pw.BoxDecoration(color: PdfColors.grey100), children: [
                    _pdfCell("Medicine", bold: true, width: 3),
                    _pdfCell("Source", bold: true, width: 1),
                    _pdfCell("Dispensed By / Pharmacy", bold: true, width: 2), 
                    _pdfCell("Qty", bold: true, align: pw.TextAlign.center, width: 1),
                    _pdfCell("Cost", bold: true, align: pw.TextAlign.right, width: 1.5)
                  ]),
                  ...items.map((item) {
                    RefillLog log = item['log'];
                    return pw.TableRow(children: [
                      _pdfCell(item['brand']),
                      _pdfCell(log.source),
                      _pdfCell(log.dispenser ?? "-", bold: true),
                      _pdfCell(log.quantity.toString(), align: pw.TextAlign.center),
                      _pdfCell(log.cost > 0 ? "PHP ${log.cost.toStringAsFixed(2)}" : "PHIC", align: pw.TextAlign.right)
                    ]);
                  }).toList()
                ])
              ]));
            }).toList()
          ];
        },
      ),
    );
    return pdf;
  }

  Future<void> _printPdf(BuildContext context) async {
    try {
      final pdf = await _buildReportDoc();
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'MedReport');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _saveAsImage(BuildContext context) async {
    try {
      final pdf = await _buildReportDoc();
      await for (var page in Printing.raster(await pdf.save(), pages: [0], dpi: 200)) {
        final imageBytes = await page.toPng();
        await smartSaveImage(imageBytes, 'MedReport_Image.png');
        if (kIsWeb) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Image Downloaded!"), backgroundColor: Colors.green));
        break; 
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Image Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _downloadExcel(BuildContext context) async {
    try {
      StringBuffer csvBuffer = StringBuffer();
      csvBuffer.writeln("Date,Medicine,Source,Dispensed By / Pharmacy,Quantity,Cost");

      for (var med in meds) {
        for (var log in med.history) {
          String date = DateFormat('yyyy-MM-dd').format(log.date);
          String brand = med.brandName.replaceAll(",", " ");
          String source = log.source;
          String disp = (log.dispenser ?? "-").replaceAll(",", " ");
          String qty = log.quantity.toString();
          String cost = log.cost > 0 ? log.cost.toStringAsFixed(2) : "PHIC";
          csvBuffer.writeln("$date,$brand,$source,$disp,$qty,$cost");
        }
      }
      downloadFile(utf8.encode(csvBuffer.toString()), 'MedReport.csv');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Excel Error: $e"), backgroundColor: Colors.red));
    }
  }

  pw.Widget _pdfCell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left, double? width}) {
    return pw.Padding(padding: pw.EdgeInsets.all(5), child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)));
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List<Map<String, dynamic>>> groupedLogs = {};
    Map<String, double> dailyTotals = {};
    for (var med in meds) {
      for (var log in med.history) {
        String dateKey = DateFormat('yyyy-MM-dd').format(log.date);
        if (!groupedLogs.containsKey(dateKey)) { groupedLogs[dateKey] = []; dailyTotals[dateKey] = 0.0; }
        groupedLogs[dateKey]!.add({'brand': med.brandName, 'log': log});
        dailyTotals[dateKey] = dailyTotals[dateKey]! + log.cost;
      }
    }
    List<String> sortedDates = groupedLogs.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text(AppConfig.isPrivacyMode ? "Report" : "Export Preview"), backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(child: ElevatedButton.icon(icon: Icon(Icons.print), label: Text("PDF"), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50, foregroundColor: Colors.blue, padding: EdgeInsets.symmetric(vertical: 12)), onPressed: () => _printPdf(context))),
                SizedBox(width: 8),
                Expanded(child: ElevatedButton.icon(icon: Icon(Icons.image), label: Text("Image"), style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade50, foregroundColor: Colors.purple, padding: EdgeInsets.symmetric(vertical: 12)), onPressed: () => _saveAsImage(context))),
                SizedBox(width: 8),
                Expanded(child: ElevatedButton.icon(icon: Icon(Icons.table_chart), label: Text("CSV"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade50, foregroundColor: Colors.green[700], padding: EdgeInsets.symmetric(vertical: 12)), onPressed: () => _downloadExcel(context))),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: sortedDates.isEmpty 
            ? Center(child: Text("No records to export.")) 
            : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: sortedDates.length,
              itemBuilder: (ctx, i) {
                String dateKey = sortedDates[i];
                DateTime dateObj = DateTime.parse(dateKey);
                List<Map<String, dynamic>> items = groupedLogs[dateKey]!;
                double total = dailyTotals[dateKey]!;

                return Card(
                  margin: EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  child: Column(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(DateFormat('MMMM dd, yyyy').format(dateObj), style: TextStyle(fontWeight: FontWeight.bold)),
                          Text("Total: ₱${total.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: Text("Medicine", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            Expanded(flex: 2, child: Text("Dispensed By / Pharmacy", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            Expanded(flex: 1, child: Text("Qty", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            Expanded(flex: 2, child: Text("Cost", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                        ),
                      ),
                      Divider(height: 1),
                      ...items.map((item) {
                        RefillLog log = item['log'];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(item['brand'], style: TextStyle(fontWeight: FontWeight.bold)),
                                Text(log.source, style: TextStyle(fontSize: 10, color: log.source=="OOP" ? Colors.red : Colors.teal)),
                              ])),
                              Expanded(flex: 2, child: Text(log.dispenser ?? "-", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              Expanded(flex: 1, child: Text("${log.quantity}", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold))),
                              Expanded(flex: 2, child: Text(log.cost > 0 ? "₱${log.cost.toStringAsFixed(2)}" : "PHIC", textAlign: TextAlign.right, style: TextStyle(fontSize: 12))),
                            ],
                          ),
                        );
                      }).toList(),
                      SizedBox(height: 8),
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
}

// --- AUTH ---
class AuthCheck extends StatefulWidget {
  @override
  _AuthCheckState createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  bool? isLoggedIn;
  
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    bool loggedIn = prefs.getBool('logged_in') ?? false;
    
    // RESTORE THE PRIVACY MODE STATE
    if (loggedIn) {
      AppConfig.isPrivacyMode = prefs.getBool('privacy_mode') ?? false;
    }
    
    setState(() => isLoggedIn = loggedIn);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoggedIn == null) return Scaffold(body: Center(child: CircularProgressIndicator()));
    return isLoggedIn! ? DashboardScreen() : LoginScreen();
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _passController = TextEditingController();
  String errorMsg = "";

  void _login() async {
    final input = _passController.text;
    bool isValid = false;
    bool isPrivacy = false;

    // --- DUAL LOGIN LOGIC (USING SECRETS) ---
    if (input == kAdminPassword) { // Uses secret constant
      isValid = true;
      isPrivacy = false; // ADMIN (Real Data)
    } else if (input == kTesterPassword) { // Uses secret constant
      isValid = true;
      isPrivacy = true; // TESTER (Hidden Data)
    }

    if (isValid) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', true);
      await prefs.setBool('privacy_mode', isPrivacy); 
      
      AppConfig.isPrivacyMode = isPrivacy;

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => DashboardScreen()));
    } else {
      setState(() => errorMsg = "Wrong Password!");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal.shade50,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/app_logo.png', 
                height: 150, 
                fit: BoxFit.contain,
              ),
              SizedBox(height: 20),
              Text("My Meds Tracker", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: InputDecoration(
                  filled: true, fillColor: Colors.white, hintText: "Enter Passcode",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: errorMsg.isEmpty ? null : errorMsg,
                ),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15)),
                child: Text("Unlock"),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// --- DASHBOARD ---
class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _customVisitLabel;
  DateTime _stickyDate = DateTime(2025, 12, 18);
  String _stickySource = "DOH";
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadVisitLabel();
    _runDailyDeduction();
  }

  void _runDailyDeduction() async {
    // --- CRITICAL SAFETY: DO NOT RUN DEDUCTION IF TESTER ---
    if (AppConfig.isPrivacyMode) return; 

    final snapshot = await FirebaseFirestore.instance.collection('meds').get();
    final nowManila = getManilaTime();

    for (var doc in snapshot.docs) {
      Medication med = Medication.fromMap(doc.data(), doc.id);
      DateTime lastDate = DateUtils.dateOnly(med.lastDeductionDate);
      DateTime today = DateUtils.dateOnly(nowManila);
      int daysPassed = today.difference(lastDate).inDays;

      if (daysPassed > 0) {
        int newStock = med.currentStock - daysPassed;
        if (newStock < 0) newStock = 0; 

        await FirebaseFirestore.instance.collection('meds').doc(med.id).update({
          'currentStock': newStock,
          'lastDeductionDate': nowManila.toIso8601String(), 
        });
      }
    }
  }

  void _loadVisitLabel() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('settings').doc('config').get();
      if (doc.exists && doc.data()!.containsKey('visitLabel')) {
        setState(() {
          _customVisitLabel = doc['visitLabel'];
        });
      }
    } catch (e) {}
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged_in', false);
    await prefs.remove('privacy_mode'); 
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
  }

  Color _getHeaderColor(List<Medication> meds) {
    if (meds.isEmpty) return Colors.blue.shade900; 
    DateTime soonest = meds.map((m) => m.nextRefillDate).reduce((a, b) => a.isBefore(b) ? a : b);
    int daysLeft = soonest.difference(getManilaTime()).inDays;
    if (daysLeft <= 3) return Colors.red.shade900; 
    if (daysLeft <= 7) return Colors.orange.shade800; 
    return Colors.green.shade800; 
  }

  // --- SNAPSHOT GENERATOR ---
  Future<void> _showSnapshotDialog(List<Medication> meds) async {
    setState(() => _isGenerating = true);
    try {
      double contentHeight = 100.0 + (meds.length * 40.0) + 50.0;
      
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(500, contentHeight, marginAll: 20),
          build: (pw.Context context) {
            return pw.Column(
              children: [
                pw.Header(level: 0, child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text("Current Stock", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)), pw.Text(DateFormat('MMM dd, yyyy').format(getManilaTime()), style: pw.TextStyle(color: PdfColors.grey))])),
                pw.SizedBox(height: 10),
                pw.Table(border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5), children: [
                  pw.TableRow(decoration: pw.BoxDecoration(color: PdfColors.grey200), children: [
                    _pdfCell("Medicine", bold: true, width: 4),
                    _pdfCell(AppConfig.isPrivacyMode ? "Last Update" : "Refill Date", bold: true, width: 2), // HIDE "REFILL" IN HEADER
                    _pdfCell("Stock", bold: true, align: pw.TextAlign.center, width: 1.5),
                  ]),
                  ...meds.map((med) {
                    String details = med.brandName;
                    if (!AppConfig.isPrivacyMode) { // HIDE INGREDIENTS IN PRIVACY MODE
                       details += "\n" + med.ingredients.map((i) => "${i.name} ${i.mg}mg").join(", ");
                    }
                    return pw.TableRow(children: [
                      pw.Padding(padding: pw.EdgeInsets.all(5), child: pw.Text(details, style: pw.TextStyle(fontSize: 10))),
                      _pdfCell(DateFormat('MMM dd, yyyy').format(med.lastRefillDate)),
                      pw.Padding(padding: pw.EdgeInsets.all(5), child: pw.Text("${med.currentStock}", textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14))),
                    ]);
                  }).toList()
                ])
              ]
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      Uint8List? imageBytes;
      await for (var page in Printing.raster(pdfBytes, pages: [0], dpi: 200)) {
        imageBytes = await page.toPng();
        break; 
      }

      if (imageBytes != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("Snapshot Preview"),
            content: Container(
              width: double.maxFinite,
              child: InteractiveViewer( 
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(imageBytes!),
              ),
            ),
            actions: [
              TextButton(child: Text("Close"), onPressed: () => Navigator.pop(ctx)),
              ElevatedButton.icon(
                icon: Icon(Icons.download), 
                label: Text(kIsWeb ? "Download Image" : "Share Image"), 
                onPressed: () {
                  smartSaveImage(imageBytes!, 'Med_Snapshot.png');
                  Navigator.pop(ctx);
                },
              )
            ],
          )
        );
      }
    } catch (e) {
      print(e);
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  pw.Widget _pdfCell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left, double? width}) {
    return pw.Padding(padding: pw.EdgeInsets.all(5), child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)));
  }

  // --- ADD PAST RECORD DIALOG ---
  Future<bool?> _showAddPastRecordDialog(List<Medication> meds) async {
    Medication? selectedMed = meds.isNotEmpty ? meds.first : null;
    TextEditingController qtyCtrl = TextEditingController(text: "30");
    TextEditingController priceCtrl = TextEditingController(text: "0");
    TextEditingController dispenserCtrl = TextEditingController(text: ""); 

    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          double price = double.tryParse(priceCtrl.text) ?? 0.0;
          int qty = int.tryParse(qtyCtrl.text) ?? 0;
          double total = price * qty;

          return AlertDialog(
            title: Text("Add Past Record"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (AppConfig.isPrivacyMode)
                    Container(
                      padding: EdgeInsets.all(8),
                      margin: EdgeInsets.only(bottom: 10),
                      color: Colors.red.shade100,
                      child: Text("DEMO MODE: Saving Disabled", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  Text("Adds to history. Does NOT change current stock.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  SizedBox(height: 15),
                  DropdownButton<Medication>(isExpanded: true, value: selectedMed, items: meds.map((m) => DropdownMenuItem(value: m, child: Text(m.brandName))).toList(), onChanged: (val) => setDialogState(() => selectedMed = val)),
                  SizedBox(height: 10),
                  Row(children: [Text("Date: "), TextButton(child: Text(DateFormat('MMM dd, yyyy').format(_stickyDate)), onPressed: () async { DateTime? picked = await showDatePicker(context: context, initialDate: _stickyDate, firstDate: DateTime(2020), lastDate: DateTime.now()); if (picked != null) { setDialogState(() => _stickyDate = picked); setState(() => _stickyDate = picked); } })]),
                  Row(children: [Expanded(child: DropdownButton<String>(value: _stickySource, items: ["DOH", "OOP"].map((v)=>DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) { setDialogState(() => _stickySource = v!); setState(() => _stickySource = v!); })), SizedBox(width: 10), Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "Qty"), onChanged: (v)=>setDialogState((){})))]),
                  if (_stickySource == "DOH") ...[SizedBox(height: 10), TextField(controller: dispenserCtrl, decoration: InputDecoration(labelText: "Dispensed By (Optional)", border: OutlineInputBorder()))],
                  if (_stickySource == "OOP") ...[
                    SizedBox(height: 10), 
                    TextField(controller: dispenserCtrl, decoration: InputDecoration(labelText: "Pharmacy Name (Optional)", border: OutlineInputBorder())),
                    SizedBox(height: 10), 
                    TextField(controller: priceCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: "Price per Tablet (₱)"), onChanged: (v)=>setDialogState((){})), SizedBox(height: 5), Text("Total Spend: ₱${total.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]
                ],
              ),
            ),
            actions: [
              TextButton(child: Text("Cancel"), onPressed: () => Navigator.pop(ctx, false)),
              ElevatedButton(
                child: Text("Add to History"),
                onPressed: AppConfig.isPrivacyMode ? null : () async { 
                  if (selectedMed != null) {
                    double cost = _stickySource == "OOP" ? (double.tryParse(priceCtrl.text) ?? 0.0) * (int.tryParse(qtyCtrl.text) ?? 0) : 0.0;
                    String? disp = dispenserCtrl.text.isNotEmpty ? dispenserCtrl.text : null;
                    selectedMed!.history.add(RefillLog(_stickyDate, int.tryParse(qtyCtrl.text) ?? 0, _stickySource, cost: cost, dispenser: disp));
                    if (disp != null) selectedMed!.lastDispenser = disp;
                    await FirebaseFirestore.instance.collection('meds').doc(selectedMed!.id).update(selectedMed!.toMap());
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Record Added! Date Saved."), backgroundColor: Colors.black87));
                    Navigator.pop(ctx, true); 
                  }
                },
              )
            ],
          );
        }
      ),
    );
  }

  // --- SPEND HISTORY DIALOG ---
  void _showSpendHistory(List<Medication> meds) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setHistoryState) {
          Map<String, List<Map<String, dynamic>>> groupedLogs = {};
          Map<String, double> dailyTotals = {};

          for (var med in meds) {
            for (var log in med.history) {
              String dateKey = DateFormat('yyyy-MM-dd').format(log.date);
              if (!groupedLogs.containsKey(dateKey)) { groupedLogs[dateKey] = []; dailyTotals[dateKey] = 0.0; }
              groupedLogs[dateKey]!.add({'brand': med.brandName, 'log': log});
              dailyTotals[dateKey] = dailyTotals[dateKey]! + log.cost;
            }
          }
          List<String> sortedDates = groupedLogs.keys.toList()..sort((a, b) => b.compareTo(a));

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
            child: Container(
              padding: EdgeInsets.all(16),
              height: 600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppConfig.isPrivacyMode ? "History Log" : "Refill History", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                      Row(
                        children: [
                          IconButton(icon: Icon(Icons.output, color: Colors.blue, size: 30), tooltip: "Generate Report", onPressed: () { Navigator.pop(ctx); Navigator.push(context, MaterialPageRoute(builder: (context) => ExportPreviewScreen(meds: meds))); }),
                          SizedBox(width: 8),
                          IconButton(icon: Icon(Icons.add_circle, color: Colors.teal, size: 30), tooltip: "Add Past Record", onPressed: () async { bool? added = await _showAddPastRecordDialog(meds); if (added == true) setHistoryState(() {}); }),
                        ],
                      )
                    ],
                  ),
                  Divider(),
                  Expanded(
                    child: sortedDates.isEmpty 
                    ? Center(child: Text("No history yet.", style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: sortedDates.length,
                        itemBuilder: (ctx, i) {
                          String dateKey = sortedDates[i];
                          DateTime dateObj = DateTime.parse(dateKey);
                          List<Map<String, dynamic>> items = groupedLogs[dateKey]!;
                          double totalDaily = dailyTotals[dateKey]!;
                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 4), elevation: 0, color: Colors.grey.shade50,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
                            child: ExpansionTile(
                              title: Text(DateFormat('MMMM dd, yyyy').format(dateObj), style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: totalDaily > 0 ? Text("Total: ₱${totalDaily.toStringAsFixed(2)}", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)) : Text("No Spend Recorded", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              children: items.map((item) {
                                RefillLog log = item['log'];
                                return ListTile(
                                  dense: true,
                                  title: Text(item['brand'], style: TextStyle(fontWeight: FontWeight.w500)),
                                  subtitle: Text("${log.source} ${log.dispenser != null ? '• ${log.dispenser}' : ''}", style: TextStyle(fontSize: 12, color: log.source == "OOP" ? Colors.red : Colors.teal)),
                                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text("+${log.quantity}", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), 
                                    Text(log.cost > 0 ? "₱${log.cost.toStringAsFixed(2)}" : "PHIC", style: TextStyle(fontSize: 12))
                                  ]),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                  ),
                  Divider(),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Center(child: Text("Close")))
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  void _editVisitLabel(BuildContext context) {
    TextEditingController _txt = TextEditingController(text: _customVisitLabel ?? "");
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Set Next Planned Visit"),
        content: TextField(controller: _txt, decoration: InputDecoration(hintText: "Feb 12-25, 2026")),
        actions: [
          TextButton(child: Text("Cancel"), onPressed: () => Navigator.pop(ctx)),
          ElevatedButton(
            child: Text("Save"),
            onPressed: () async {
              String newVal = _txt.text;
              await FirebaseFirestore.instance.collection('settings').doc('config').set({'visitLabel': newVal}, SetOptions(merge: true));
              setState(() => _customVisitLabel = newVal);
              Navigator.pop(ctx);
            },
          )
        ],
      )
    );
  }

  // --- DASHBOARD BUILD METHOD (FILTERING APPLIED HERE) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], 
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('meds').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: TextStyle(color: Colors.red)));

          List<Medication> meds = snapshot.hasData ? snapshot.data!.docs.map((doc) => Medication.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList() : <Medication>[];
          
          // --- STRICT PRIVACY FILTER: REMOVE SENSITIVE MEDS ENTIRELY ---
          if (AppConfig.isPrivacyMode) {
            meds.removeWhere((m) {
              String name = m.brandName.toLowerCase();
              return name.contains('teldy') || 
                     name.contains('duomax') || 
                     name.contains('cotrim') || 
                     name.contains('rifam') || 
                     name.contains('dolute') ||
                     name.contains('antiviral') || // Catch-all if already renamed
                     name.contains('antibiotic');
            });
          }

          meds.sort((a, b) {
             bool aPriority = (a.brandName.toLowerCase().contains("teldy") || a.brandName.toLowerCase().contains("antiviral") || a.source.contains("DOH") || a.source.contains("Gov"));
             bool bPriority = (b.brandName.toLowerCase().contains("teldy") || b.brandName.toLowerCase().contains("antiviral") || b.source.contains("DOH") || b.source.contains("Gov"));
             if (aPriority && !bPriority) return -1;
             if (!aPriority && bPriority) return 1;
             return a.nextRefillDate.compareTo(b.nextRefillDate);
          });

          String headerText = _customVisitLabel?.isNotEmpty == true ? _customVisitLabel! : 
             (meds.isEmpty ? DateFormat('MMM dd, yyyy').format(getManilaTime()) : DateFormat('MMM dd, yyyy').format(meds.map((m) => m.nextRefillDate).reduce((a, b) => a.isBefore(b) ? a : b)));

          Color headerColor = _getHeaderColor(meds);

          return Column(children: [
            SafeArea(bottom: false, child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(color: headerColor), 
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(AppConfig.isPrivacyMode ? "Medication Status (DEMO)" : "Medication Status", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  GestureDetector(onTap: _logout, child: Row(children: [Icon(Icons.logout, color: Colors.white.withOpacity(0.8), size: 16), SizedBox(width: 4), Text("Logout", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14))]))
                ]),
                SizedBox(height: 5), 
                Text("Next Planned Visit", style: TextStyle(color: Colors.white70, fontSize: 12)),
                SizedBox(height: 2),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _showSpendHistory(meds),
                      child: Icon(Icons.calendar_month, color: Colors.white, size: 24),
                    ),
                    SizedBox(width: 15),
                    InkWell(
                      onTap: () => _showSnapshotDialog(meds),
                      child: _isGenerating ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Icon(Icons.camera_alt, color: Colors.white, size: 24),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _editVisitLabel(context),
                        child: Row(children: [
                          Expanded(child: Text(headerText, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: Colors.white30), overflow: TextOverflow.ellipsis)),
                          SizedBox(width: 5),
                          Icon(Icons.edit, color: Colors.white30, size: 16)
                        ]),
                      ),
                    ),
                  ],
                ),
              ]),
            )),
            Expanded(child: meds.isEmpty 
              ? Center(child: Text("Tap + to add medicines", style: TextStyle(color: Colors.grey)))
              : ListView(padding: EdgeInsets.all(16), children: [...meds.map((med) => buildMedCard(med)).toList(), SizedBox(height: 80)])
            ),
          ]);
        }
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal.shade100,
        child: Icon(Icons.add, size: 30, color: Colors.black87),
        onPressed: _showAddDialog,
      ),
    );
  }

  // --- WIDGET: MEDICINE CARD ---
  Widget buildMedCard(Medication med) {
    bool isLow = med.currentStock < 10;
    bool isDOH = med.source.contains("DOH") || med.source.contains("Gov") || med.brandName.toLowerCase().contains("teldy") || med.brandName.toLowerCase().contains("antiviral");
    
    Color cardColor = med.isOOP ? Colors.red.shade50 : (isLow ? Colors.orange.shade50 : Colors.green.shade50);
    Color textColor = med.isOOP ? Colors.red.shade900 : Colors.black87;
    String totalDisplay = med.totalDosage % 1 == 0 ? med.totalDosage.toInt().toString() : med.totalDosage.toString();
    bool isWeekend = med.isWeekendDue;
    double totalSpent = med.history.fold(0, (sum, log) => sum + log.cost);

    return Card(
      color: cardColor, elevation: 2, margin: EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(12.0), child: Column(children: [
        if (isWeekend) Container(
          margin: EdgeInsets.only(bottom: 10), padding: EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [Icon(Icons.access_time, color: Colors.orange[800], size: 16), SizedBox(width: 8), Expanded(child: Text("Due on Weekend! Clinic Closed.", style: TextStyle(color: Colors.orange[900], fontSize: 12, fontWeight: FontWeight.bold)))])
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(med.brandName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)), 
              if (isDOH) Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.star, size: 18, color: Colors.orange))
            ]),
            
            // --- HIDE INGREDIENTS SUBTITLE IN PRIVACY MODE ---
            if (!AppConfig.isPrivacyMode) ...[
              SizedBox(height: 4), ...med.ingredients.map((ing) => Text("${ing.name} ${ing.mg % 1 == 0 ? ing.mg.toInt() : ing.mg}mg", style: TextStyle(color: Colors.grey[800], height: 1.2))).toList(),
              if (med.ingredients.length > 1) 
                 Padding(padding: EdgeInsets.only(top: 4), child: Text("Total: ${totalDisplay}mg", style: TextStyle(color: Colors.teal[700], fontWeight: FontWeight.bold))),
            ],
            
            if (med.isOOP)
               Padding(padding: EdgeInsets.only(top: 4), child: Text("Total Spent: ₱${totalSpent.toStringAsFixed(2)}", style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold))),
            
          ])),
          Container(
            margin: EdgeInsets.only(left: 8), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: textColor.withOpacity(0.3))),
            child: Column(children: [Text("${med.remainingPills}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)), Text("left", style: TextStyle(fontSize: 10, color: Colors.grey))]),
          )
        ]),
        Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: med.isOOP ? Colors.red : Colors.teal, borderRadius: BorderRadius.circular(4)), child: Text("${med.source} (${med.cycleDuration}d)", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          // --- HIDE "REFILL" WORD IN PRIVACY MODE ---
          TextButton.icon(icon: Icon(Icons.edit, size: 16, color: textColor), label: Text(AppConfig.isPrivacyMode ? "Edit / Manage" : "Edit / Refill", style: TextStyle(color: textColor)), onPressed: () => _showEditDialog(med))
        ])
      ])),
    );
  }

  // --- DIALOG: EDIT MED ---
  void _showEditDialog(Medication med) {
    TextEditingController brandCtrl = TextEditingController(text: med.brandName);
    TextEditingController stockCtrl = TextEditingController(text: med.currentStock.toString());
    TextEditingController refillCtrl = TextEditingController(text: "");
    TextEditingController priceCtrl = TextEditingController(text: ""); 
    TextEditingController dispenserCtrl = TextEditingController(text: med.lastDispenser ?? ""); 
    
    DateTime selectedRefillDate = med.lastRefillDate;
    int selectedCycle = med.cycleDuration; 
    String currentSource = med.source.contains("DOH") ? "DOH" : "OOP"; 
    if (AppConfig.isPrivacyMode && med.source.contains("Gov")) currentSource = "DOH"; 

    List<Map<String, dynamic>> tempIngredients = med.ingredients.map((ing) => {
      "nameCtrl": TextEditingController(text: ing.name),
      "mgCtrl": TextEditingController(text: ing.mg.toString())
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          double pricePerTab = double.tryParse(priceCtrl.text) ?? 0.0;
          int qty = int.tryParse(refillCtrl.text) ?? 0;
          double totalCost = pricePerTab * qty;

          return AlertDialog(
            title: Text("Manage Medicine"),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (AppConfig.isPrivacyMode)
                Container(
                  padding: EdgeInsets.all(8),
                  margin: EdgeInsets.only(bottom: 10),
                  color: Colors.red.shade100,
                  child: Text("DEMO MODE: Saving Disabled", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              TextField(controller: brandCtrl, decoration: InputDecoration(labelText: "Brand Name")),
              SizedBox(height: 15),
              
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("Source:", style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: currentSource, 
                  items: ["DOH", "OOP"].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), 
                  onChanged: (val) => setDialogState(() => currentSource = val!)
                )
              ]),
              Divider(),
              
              Text(AppConfig.isPrivacyMode ? "Last Update Date" : "Last Refill Date (Schedule Anchor)", style: TextStyle(fontSize: 12, color: Colors.grey)), 
              OutlinedButton(
                child: Text(DateFormat('MMM dd, yyyy').format(selectedRefillDate)),
                onPressed: () async {
                  DateTime? picked = await showDatePicker(
                    context: context, initialDate: selectedRefillDate, firstDate: DateTime(2025), lastDate: DateTime.now()
                  );
                  if (picked != null) setDialogState(() => selectedRefillDate = picked);
                },
              ),
              
              if (currentSource == "DOH") ...[
                SizedBox(height: 10),
                TextField(controller: dispenserCtrl, decoration: InputDecoration(labelText: "Dispensed By (Optional)", border: OutlineInputBorder())),
              ],
              
              if (currentSource == "OOP") ...[
                SizedBox(height: 10),
                TextField(controller: dispenserCtrl, decoration: InputDecoration(labelText: "Pharmacy Name (Optional)", border: OutlineInputBorder())),
              ],
              
              SizedBox(height: 10),
              
              Row(children: [
                Expanded(child: Text("Count on Hand (Today):")),
                SizedBox(width: 60, child: TextField(controller: stockCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center))
              ]),
              
              Divider(),
              
              Text(AppConfig.isPrivacyMode ? "Cycle" : "Refill Cycle", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)), 
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                ChoiceChip(label: Text("30d"), selected: selectedCycle == 30, onSelected: (b) => setDialogState(() => selectedCycle = 30)),
                ChoiceChip(label: Text("60d"), selected: selectedCycle == 60, onSelected: (b) => setDialogState(() => selectedCycle = 60)),
                ChoiceChip(label: Text("90d"), selected: selectedCycle == 90, onSelected: (b) => setDialogState(() => selectedCycle = 90)),
              ]),
              
              Divider(height: 20),
              
              if (!AppConfig.isPrivacyMode) ...[ // HIDE INGREDIENTS EDIT IN DEMO
                Text("Generic Names / Ingredients:", style: TextStyle(fontWeight: FontWeight.bold)),
                ...tempIngredients.asMap().entries.map((entry) {
                   int index = entry.key;
                   return Row(children: [
                     Expanded(flex: 3, child: TextField(controller: entry.value['nameCtrl'], decoration: InputDecoration(hintText: "Generic Name"))), 
                     SizedBox(width: 10), 
                     Expanded(flex: 2, child: TextField(controller: entry.value['mgCtrl'], decoration: InputDecoration(hintText: "Mg"))), 
                     IconButton(icon: Icon(Icons.delete, color: Colors.red), onPressed: () => setDialogState(() { if(tempIngredients.length > 1) tempIngredients.removeAt(index); }))
                   ]);
                }).toList(),
                TextButton.icon(icon: Icon(Icons.add), label: Text("Add Ingredient"), onPressed: () => setDialogState(() => tempIngredients.add({"nameCtrl": TextEditingController(), "mgCtrl": TextEditingController(text: "0")}))),
                Divider(height: 20),
              ],

              if (currentSource == "OOP") ...[
                Row(
                  children: [
                    Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.numberWithOptions(decimal: true), onChanged: (v) => setDialogState((){}), decoration: InputDecoration(labelText: "Price / Tablet (₱)", border: OutlineInputBorder()))),
                    SizedBox(width: 10), Text("x", style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(width: 10),
                    Expanded(child: TextField(controller: refillCtrl, keyboardType: TextInputType.number, onChanged: (v) => setDialogState((){}), decoration: InputDecoration(labelText: "Quantity", border: OutlineInputBorder()))),
                  ],
                ),
                SizedBox(height: 5),
                Text("Total: ₱${totalCost.toStringAsFixed(2)}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                SizedBox(height: 15),
              ] else ...[
                 TextField(controller: refillCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: "Refill Amount (Optional)", border: OutlineInputBorder(), suffixText: "tabs")),
                SizedBox(height: 10),
              ],

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, minimumSize: Size(double.infinity, 45)),
                child: Text(AppConfig.isPrivacyMode ? "Save Changes" : "Save Changes / Refill"), // CHANGED TEXT
                onPressed: AppConfig.isPrivacyMode ? null : () async { 
                  int refillAmount = int.tryParse(refillCtrl.text) ?? 0;
                  int userCountToday = int.tryParse(stockCtrl.text) ?? med.currentStock;
                  int finalStock = userCountToday;

                  double finalCost = 0.0;
                  if (currentSource == "OOP") {
                     double price = double.tryParse(priceCtrl.text) ?? 0.0;
                     finalCost = price * refillAmount;
                  }
                  
                  String? disp = dispenserCtrl.text.isNotEmpty ? dispenserCtrl.text : null;

                  if (refillAmount > 0) {
                     // Add New Refill Log
                     finalStock += refillAmount;
                     med.history.add(RefillLog(getManilaTime(), refillAmount, currentSource, cost: finalCost, dispenser: disp));
                  } else {
                     // --- GUARANTEED UPDATE: SEARCH BY STRING DATE ---
                     if (disp != null) {
                        try {
                           // 1. Convert selected date to "YYYY-MM-DD"
                           String targetDateStr = DateFormat('yyyy-MM-dd').format(selectedRefillDate);
                           
                           // 2. Iterate and update ANY log matching that day
                           for (var log in med.history) {
                              if (DateFormat('yyyy-MM-dd').format(log.date) == targetDateStr) {
                                 log.dispenser = disp;
                              }
                           }
                        } catch (e) {
                           // Ignore
                        }
                     }
                  }

                  List<Ingredient> finalIngredients = [];
                  for (var item in tempIngredients) {
                    String name = (item['nameCtrl'] as TextEditingController).text;
                    double mg = double.tryParse((item['mgCtrl'] as TextEditingController).text) ?? 0;
                    if (name.isNotEmpty) finalIngredients.add(Ingredient(name, mg));
                  }

                  med.brandName = brandCtrl.text;
                  med.ingredients = finalIngredients; 
                  med.currentStock = finalStock; 
                  med.cycleDuration = selectedCycle;
                  med.lastRefillDate = selectedRefillDate; 
                  med.source = currentSource; 
                  if (disp != null) med.lastDispenser = disp; 

                  await FirebaseFirestore.instance.collection('meds').doc(med.id).update(med.toMap());
                  Navigator.pop(ctx);
                },
              )
            ])),
          );
        });
      },
    );
  }

  // --- SHOW ADD DIALOG ---
  void _showAddDialog() {
    TextEditingController brandCtrl = TextEditingController();
    TextEditingController qtyCtrl = TextEditingController(text: "30");
    List<Map<String, dynamic>> tempIngredients = [{"nameCtrl": TextEditingController(), "mgCtrl": TextEditingController(text: "0")}];
    String selectedSource = "DOH";
    int selectedCycle = 30; // Default
    bool isSaving = false; 

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text("Add New Medicine"),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (AppConfig.isPrivacyMode)
                Container(
                  padding: EdgeInsets.all(8),
                  margin: EdgeInsets.only(bottom: 10),
                  color: Colors.red.shade100,
                  child: Text("DEMO MODE: Saving Disabled", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              TextField(controller: brandCtrl, decoration: InputDecoration(labelText: "Brand Name")),
              SizedBox(height: 10),
              Row(children: [Text("Source: "), DropdownButton<String>(value: selectedSource, items: ["DOH", "OOP"].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (val) => setDialogState(() => selectedSource = val!))]),
              Row(children: [
                Expanded(child: Text("Initial Stock:")),
                SizedBox(width: 80, child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10))))
              ]),
              SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                ChoiceChip(label: Text("30d"), selected: selectedCycle == 30, onSelected: (b) => setDialogState(() => selectedCycle = 30)),
                ChoiceChip(label: Text("60d"), selected: selectedCycle == 60, onSelected: (b) => setDialogState(() => selectedCycle = 60)),
                ChoiceChip(label: Text("90d"), selected: selectedCycle == 90, onSelected: (b) => setDialogState(() => selectedCycle = 90)),
              ]),
              SizedBox(height: 15),
              Text("Ingredients:", style: TextStyle(fontWeight: FontWeight.bold)),
              ...tempIngredients.asMap().entries.map((entry) {
                 int index = entry.key;
                 return Row(children: [Expanded(flex: 3, child: TextField(controller: entry.value['nameCtrl'])), SizedBox(width: 10), Expanded(flex: 2, child: TextField(controller: entry.value['mgCtrl'])), IconButton(icon: Icon(Icons.delete, color: Colors.red), onPressed: () => setDialogState(() { if(tempIngredients.length > 1) tempIngredients.removeAt(index); }))]);
              }).toList(),
              TextButton.icon(icon: Icon(Icons.add), label: Text("Add Ingredient"), onPressed: () => setDialogState(() => tempIngredients.add({"nameCtrl": TextEditingController(), "mgCtrl": TextEditingController(text: "0")})))
            ])),
            actions: [
              TextButton(child: Text("Cancel"), onPressed: () => Navigator.pop(ctx)),
              ElevatedButton(
                child: isSaving ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text("Create Med"), 
                onPressed: (AppConfig.isPrivacyMode || isSaving) ? null : () async { 
                  List<Ingredient> newIngredients = [];
                  for (var item in tempIngredients) {
                    String name = (item['nameCtrl'] as TextEditingController).text;
                    double mg = double.tryParse((item['mgCtrl'] as TextEditingController).text) ?? 0;
                    if (name.isNotEmpty) newIngredients.add(Ingredient(name, mg));
                  }
                  if (brandCtrl.text.isNotEmpty) {
                    setDialogState(() => isSaving = true);
                    try {
                        final newMed = Medication(
                          id: "", 
                          brandName: brandCtrl.text, 
                          ingredients: newIngredients, 
                          source: selectedSource, 
                          currentStock: int.tryParse(qtyCtrl.text) ?? 30, 
                          cycleDuration: selectedCycle, 
                          lastRefillDate: getManilaTime(),
                          lastDeductionDate: getManilaTime()
                        );
                        await FirebaseFirestore.instance.collection('meds').add(newMed.toMap());
                        Navigator.pop(ctx);
                    } catch (e) { setDialogState(() => isSaving = false); }
                  }
              })
            ],
          );
        });
      },
    );
  }
}