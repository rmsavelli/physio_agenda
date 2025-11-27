import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  final supabaseUrl = dotenv.env['SUPABASE_URL']!;
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Agenda', home: AgendaPage());
  }
}

class AgendaPage extends StatefulWidget {
  const AgendaPage({super.key});
  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  List<Map<String, dynamic>> _appointments = [];
  bool _loading = true;

  late DateTime _currentWeekMonday;
  late DateTime _currentWeekFriday;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _currentWeekMonday = today.subtract(Duration(days: today.weekday - 1));
    _currentWeekFriday = _currentWeekMonday.add(const Duration(days: 4));
    _loadWeek();
  }

  Future<void> _loadWeek() async {
    setState(() => _loading = true);

    final mondayUtc = DateTime.utc(
        _currentWeekMonday.year, _currentWeekMonday.month, _currentWeekMonday.day);
    final fridayUtc = DateTime.utc(
        _currentWeekFriday.year, _currentWeekFriday.month, _currentWeekFriday.day, 23, 59, 59);

    final data = await supabase
        .from('appointments')
        .select()
        .gte('appointment_datetime', mondayUtc.toIso8601String())
        .lte('appointment_datetime', fridayUtc.toIso8601String())
        .order('appointment_datetime');

    _appointments = List<Map<String, dynamic>>.from(data);
    setState(() => _loading = false);
  }

  Future<void> _updatePresence(int id, int index, bool? newValue) async {
    await supabase.from('appointments').update({
      'patient_presence${index + 1}': newValue,
    }).eq('id', id);
  }

  bool? _nextPresence(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  void _updateLocalPresence(int apptId, int index, bool? value) {
    final appt = _appointments.firstWhere((a) => a['id'] == apptId);
    appt['patient_presence${index + 1}'] = value;
    setState(() {});
  }

  Widget _buildPatientRow(int apptId, int index, String? name, bool? presence) {
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
      icon = Icons.close;
      iconColor = Colors.red;
    }

    return GestureDetector(
      onTap: isEmpty
          ? null
          : () async {
              final newPresence = _nextPresence(presence);
              await _updatePresence(apptId, index, newPresence);
              _updateLocalPresence(apptId, index, newPresence);
            },
      child: Row(
        children: [
          Expanded(
            child: Text(
              isEmpty ? "(empty)" : name,
              style: TextStyle(
                fontSize: 16,
                color: isEmpty ? Colors.black.withValues(alpha: 0.4) : Colors.black,
              ),
            ),
          ),
          Icon(
            icon,
            color: iconColor,
            size: 24,
            weight: 900,
            shadows: const [Shadow(blurRadius: 2, color: Colors.black26, offset: Offset(0, 1))],
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
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  /// Flatten appointments with day headers
  List<Map<String, dynamic>> _flattenAppointments() {
    final sorted = <DateTime, List<Map<String, dynamic>>>{};
    for (final appt in _appointments) {
      final dt = DateTime.parse(appt['appointment_datetime']);
      final day = DateTime(dt.year, dt.month, dt.day);
      if (day.weekday <= 5) {
        sorted.putIfAbsent(day, () => []).add(appt);
      }
    }

    final result = <Map<String, dynamic>>[];
    final days = sorted.keys.toList()..sort();
    for (final day in days) {
      result.add({'type': 'header', 'date': day});
      final list = sorted[day]!..sort((a, b) {
        final t1 = DateTime.parse(a['appointment_datetime']);
        final t2 = DateTime.parse(b['appointment_datetime']);
        return t1.compareTo(t2);
      });
      for (final appt in list) {
        result.add({'type': 'appointment', 'data': appt});
      }
    }
    return result;
  }

  void _prevWeek() {
    _currentWeekMonday = _currentWeekMonday.subtract(const Duration(days: 7));
    _currentWeekFriday = _currentWeekMonday.add(const Duration(days: 4));
    _loadWeek();
  }

  void _nextWeek() {
    _currentWeekMonday = _currentWeekMonday.add(const Duration(days: 7));
    _currentWeekFriday = _currentWeekMonday.add(const Duration(days: 4));
    _loadWeek();
  }

  Widget _buildPaginator() {
    final fmt = DateFormat("dd MMM");
    final label = "${fmt.format(_currentWeekMonday)} — ${fmt.format(_currentWeekFriday)}";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.grey.withValues(alpha: 0.10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left, size: 32), onPressed: _prevWeek),
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.chevron_right, size: 32), onPressed: _nextWeek),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final flattened = _flattenAppointments();

    return Scaffold(
      appBar: AppBar(title: const Text("Agenda")),
      body: Column(
        children: [
          _buildPaginator(),
          Expanded(
            child: flattened.isEmpty
                ? const Center(child: Text("No appointments found.", style: TextStyle(fontSize: 18)))
                : ListView.builder(
                    itemCount: flattened.length,
                    itemBuilder: (context, index) {
                      final item = flattened[index];
                      if (item['type'] == 'header') {
                        final day = item['date'] as DateTime;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                          child: Text(
                            DateFormat("EEEE, dd MMM").format(day),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        );
                      } else {
                        final appt = item['data'] as Map<String, dynamic>;
                        return _buildAppointmentCard(appt);
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
