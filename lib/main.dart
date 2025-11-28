import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

  await Supabase.initialize(url: supabaseUrl!, anonKey: supabaseAnonKey!);
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

  // -------------------------------------------------------------
  // LOAD WEEK
  // -------------------------------------------------------------
  Future<void> _loadWeek() async {
    setState(() => _loading = true);

    final mondayUtc = DateTime.utc(
      _currentWeekMonday.year,
      _currentWeekMonday.month,
      _currentWeekMonday.day,
    );

    final fridayUtc = DateTime.utc(
      _currentWeekFriday.year,
      _currentWeekFriday.month,
      _currentWeekFriday.day,
      23,
      59,
      59,
    );

    final data = await supabase
        .from('appointments')
        .select()
        .gte('appointment_datetime', mondayUtc.toIso8601String())
        .lte('appointment_datetime', fridayUtc.toIso8601String())
        .order('appointment_datetime');

    if (!mounted) return;

    setState(() {
      _appointments = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  // -------------------------------------------------------------
  // REMOVE PERSON (long-press gesture)
  // -------------------------------------------------------------
  Future<void> _removePerson(int apptId, int index) async {
    final columnName = "patient_name${index + 1}";
    final colPresence = "patient_presence${index + 1}";

    await supabase.from('appointments').update({
      columnName: null,
      colPresence: null,
    }).eq('id', apptId);

    if (!mounted) return;

    final appt = _appointments.firstWhere((a) => a['id'] == apptId);
    appt[columnName] = null;
    appt[colPresence] = null;

    setState(() {});
  }

  Future<void> _confirmRemoveDialog(int apptId, int index, String name) async {
  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Remove person"),
      content: Text("Remove \"$name\" from this appointment?"),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();  // close dialog first
            _removePerson(apptId, index);       // do async work safely
          },
          child: const Text("Remove"),
        ),
      ],
    ),
  );
}


  // -------------------------------------------------------------
  // ADD PERSON
  // -------------------------------------------------------------
  Future<void> _addPerson(
    int apptId,
    int index,
    String column,
    String name,
  ) async {
    await supabase.from('appointments').update({
      column: name,
      "patient_presence${index + 1}": null,
    }).eq('id', apptId);

    if (!mounted) return;

    final appt = _appointments.firstWhere((a) => a['id'] == apptId);
    appt[column] = name;
    appt["patient_presence${index + 1}"] = null;

    setState(() {});
  }

  Future<void> _addPersonDialog(int apptId, int index) async {
    final controller = TextEditingController();
    final column = "patient_name${index + 1}";

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Add person"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter patient name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),

          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              // 1️⃣ Close the dialog immediately – before async calls
              Navigator.pop(dialogContext);

              // 2️⃣ Now run async work safely outside the dialog
              _addPerson(apptId, index, column, name);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // PRESENCE CYCLE
  // -------------------------------------------------------------
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

  // -------------------------------------------------------------
  // PATIENT ROW (now includes long-press remove)
  // -------------------------------------------------------------
  Widget _buildPatientRow(int apptId, int index, String? name, bool? presence) {
    final isEmpty = name == null || name.trim().isEmpty;

    IconData icon;
    Color iconColor;

    if (isEmpty) {
      icon = Icons.add_circle_outline;
      iconColor = Colors.blue.withValues(alpha: 0.7);
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
      onLongPress: isEmpty
          ? null
          : () => _confirmRemoveDialog(apptId, index, name), // REMOVE PERSON
      onTap: () async {
        if (isEmpty) {
          await _addPersonDialog(apptId, index);
        } else {
          final newPresence = _nextPresence(presence);
          await _updatePresence(apptId, index, newPresence);
          if (!mounted) return;
          _updateLocalPresence(apptId, index, newPresence);
        }
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
            size: 28,
            weight: 900,
            shadows: const [
              Shadow(blurRadius: 2, color: Colors.black26, offset: Offset(0, 1)),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // APPOINTMENT CARD
  // -------------------------------------------------------------
  Widget _buildAppointmentCard(Map<String, dynamic> appt) {
    final dt = DateTime.parse(appt["appointment_datetime"]);
    final hour = DateFormat("HH:mm").format(dt);
    final apptId = appt["id"] as int;

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
                    _buildPatientRow(apptId, 0, appt['patient_name1'], appt['patient_presence1']),
                    _buildPatientRow(apptId, 1, appt['patient_name2'], appt['patient_presence2']),
                    _buildPatientRow(apptId, 2, appt['patient_name3'], appt['patient_presence3']),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // FLATTEN APPOINTMENTS
  // -------------------------------------------------------------
  List<Map<String, dynamic>> _flattenAppointments() {
    final sorted = <DateTime, List<Map<String, dynamic>>>{};

    for (final appt in _appointments) {
      final dt = DateTime.parse(appt['appointment_datetime']);
      final day = DateTime(dt.year, dt.month, dt.day);
      sorted.putIfAbsent(day, () => []).add(appt);
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

  // -------------------------------------------------------------
  // WEEK PAGINATION
  // -------------------------------------------------------------
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

  // -------------------------------------------------------------
  // BUILD
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
                      }

                      return _buildAppointmentCard(item['data']);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
