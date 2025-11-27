import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  /// Update presence in DB
  Future<void> _updatePresence(
      int id, int index, bool? newValue) async {

    await supabase.from('appointments').update({
      'patient_presence${index + 1}': newValue,
    }).eq('id', id);
  }

  /// Cycle presence: NULL → TRUE → FALSE → NULL
  bool? _nextPresence(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  /// Build interactive patient row with NEW icons
  Widget _buildPatientRow(
      int apptId, int index, String? name, bool? presence) {
    final isEmpty = name == null || name.trim().isEmpty;

    IconData icon;
    Color iconColor;

    if (isEmpty) {
      icon = Icons.remove_circle_outline;
      iconColor = Colors.grey.withValues(alpha: 0.3);
    } else if (presence == null) {
      icon = Icons.help_outline;
      iconColor = Colors.grey;
    } else if (presence == true) {
      icon = Icons.check;
      iconColor = Colors.green;
    } else {
      // NEW: Red X instead of red square
      icon = Icons.close;
      iconColor = Colors.red;
    }

    return GestureDetector(
      onTap: isEmpty
          ? null
          : () async {
              final newPresence = _nextPresence(presence);

              await _updatePresence(apptId, index, newPresence);

              setState(() {
                _futureAppointments = _fetchAppointments();
              });
            },
      child: Row(
        children: [
          Expanded(
            child: Text(
              isEmpty ? "(empty)" : name,
              style: TextStyle(
                fontSize: 16,
                color: isEmpty
                    ? Colors.black.withValues(alpha: 0.4)
                    : Colors.black,
              ),
            ),
          ),
          Icon(
            icon,
            color: iconColor,
            size: 24,          // bigger = more visible
            weight: 900,       // makes it bold
            shadows: [
              Shadow(
                blurRadius: 2,
                color: Colors.black26,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appt) {
    final dt = DateTime.parse(appt["appointment_datetime"]);
    final hour = DateFormat("HH:mm").format(dt);
    final apptId = appt["id"] as int;

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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      elevation: 2,
      child: SizedBox(
        height: 120,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
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

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPatientRow(apptId, 0, names[0], presences[0]),
                    _buildPatientRow(apptId, 1, names[1], presences[1]),
                    _buildPatientRow(apptId, 2, names[2], presences[2]),
                  ],
                ),
              ),
            ],
          ),
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
      final list = map[k]!;
      list.sort((a, b) {
        final t1 = DateTime.parse(a['appointment_datetime']);
        final t2 = DateTime.parse(b['appointment_datetime']);
        return t1.compareTo(t2);
      });
      sorted[k] = list;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Agenda")),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureAppointments,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
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
              final label =
                  DateFormat("EEEE, dd MMM yyyy").format(day);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(12, 16, 12, 6),
                    child: Text(
                      label,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
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
