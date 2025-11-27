import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables first
  await dotenv.load();

  final supabaseUrl = dotenv.env['SUPABASE_URL']!;
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Agenda',
      home: AgendaPage(),
    );
  }
}

class AgendaPage extends StatefulWidget {
  const AgendaPage({super.key});

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  late Future<List<Map<String, dynamic>>> _futureAppointments;

  @override
  void initState() {
    super.initState();
    _futureAppointments = _fetchAppointments();
  }

  Future<List<Map<String, dynamic>>> _fetchAppointments() async {
    final data = await supabase
        .from('appointments')
        .select()
        .order('appointment_datetime');
    return List<Map<String, dynamic>>.from(data);
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appt) {
    final dt = DateTime.parse(appt["appointment_datetime"]);
    final hour = DateFormat("HH:mm").format(dt);
    final date = DateFormat("dd/MM/yyyy").format(dt);

    List<Widget> patients = [];

    void addPatient(String? name, bool? presence) {
      if (name != null && name.trim().isNotEmpty) {
        patients.add(
          Row(
            children: [
              Icon(
                presence == null
                    ? Icons.help_outline
                    : presence
                        ? Icons.check_circle
                        : Icons.cancel,
                color: presence == null
                    ? Colors.grey
                    : presence
                        ? Colors.green
                        : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        );
      }
    }

    addPatient(appt['patient_name1'], appt['patient_presence1']);
    addPatient(appt['patient_name2'], appt['patient_presence2']);
    addPatient(appt['patient_name3'], appt['patient_presence3']);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "$date  •  $hour",
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...patients,
          ],
        ),
      ),
    );
  }

  /// Group appointments by day for display
  Map<DateTime, List<Map<String, dynamic>>> _groupByDay(
      List<Map<String, dynamic>> rows) {
    final map = <DateTime, List<Map<String, dynamic>>>{};

    for (final a in rows) {
      final dt = DateTime.parse(a['appointment_datetime']);
      final day = DateTime(dt.year, dt.month, dt.day);
      map.putIfAbsent(day, () => []).add(a);
    }

    final sorted = <DateTime, List<Map<String, dynamic>>>{};
    for (final k in map.keys.toList()..sort()) {
      sorted[k] = map[k]!;
    }

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Agenda"),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureAppointments,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text("Error: ${snapshot.error}",
                  style: const TextStyle(color: Colors.red)),
            );
          }

          final data = snapshot.data!;
          if (data.isEmpty) {
            return const Center(
              child: Text("No appointments found.",
                  style: TextStyle(fontSize: 18)),
            );
          }

          final grouped = _groupByDay(data);

          return ListView(
            children: grouped.entries.map((entry) {
              final day = entry.key;
              final list = entry.value;
              final label = DateFormat("EEEE, dd MMM yyyy").format(day);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  ...list.map(_buildAppointmentCard),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
