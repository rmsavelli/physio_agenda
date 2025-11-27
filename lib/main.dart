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

    // Build patient rows
    List<String?> names = [
      appt['patient_name1'],
      appt['patient_name2'],
      appt['patient_name3'],
    ];

    List<bool?> presences = [
      appt['patient_presence1'],
      appt['patient_presence2'],
      appt['patient_presence3'],
    ];

    List<Widget> patientRows = [];

    for (int i = 0; i < names.length; i++) {
      final name = names[i];
      final presence = presences[i];

      if (name == null || name.trim().isEmpty) continue;

      IconData icon;
      Color color;

      if (presence == null) {
        icon = Icons.help_outline;
        color = Colors.grey;
      } else if (presence == true) {
        icon = Icons.check_circle;
        color = Colors.green;
      } else {
        icon = Icons.cancel;
        color = Colors.red;
      }

      patientRows.add(
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            Icon(icon, color: color, size: 20),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // LEFT — TIME
            SizedBox(
              width: 60,
              child: Center(
                child: Text(
                  hour,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // MIDDLE — PATIENT NAMES
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: patientRows,
              ),
            ),

            // RIGHT — PRESENCE ICONS (already included in the rows above)
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

    // Sort days AND sort items inside each day
    final sorted = <DateTime, List<Map<String, dynamic>>>{};
    for (final k in map.keys.toList()..sort()) {
      final dayList = map[k]!;
      dayList.sort((a, b) {
        final t1 = DateTime.parse(a['appointment_datetime']);
        final t2 = DateTime.parse(b['appointment_datetime']);
        return t1.compareTo(t2);
      });
      sorted[k] = dayList;
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
