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
  // ADD / EDIT PERSON
  // -------------------------------------------------------------
  Future<void> _addOrEditPersonDialog(int apptId, int index, String? currentName) async {
    final controller = TextEditingController(text: currentName);
    final column = "patient_name${index + 1}";

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(currentName == null ? "Add person" : "Edit person"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter patient name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              Navigator.of(dialogContext).pop(); // Close dialog first
              _addOrEditPerson(apptId, index, column, name);
            },
            child: Text(currentName == null ? "Add" : "Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _addOrEditPerson(int apptId, int index, String column, String name) async {
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

  // -------------------------------------------------------------
  // REMOVE PERSON
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
              Navigator.of(dialogContext).pop(); // close dialog first
              _removePerson(apptId, index);
            },
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // PRESENCE CYCLE
  // -------------------------------------------------------------
  Future<void> _cyclePresence(int apptId, int index, bool? current) async {
    bool? next;
    if (current == null) {
      next = true;
    } else if (current == true) {
      next = false;
    } else {
      next = null;
    }

    final column = "patient_presence${index + 1}";

    await supabase.from('appointments').update({column: next}).eq('id', apptId);

    if (!mounted) return;

    final appt = _appointments.firstWhere((a) => a['id'] == apptId);
    appt[column] = next;
    setState(() {});
  }

  // -------------------------------------------------------------
  // PATIENT ROW
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
  iconColor = Colors.grey; // grey already fine
} else if (presence == true) {
  icon = Icons.check_circle;
  iconColor = Colors.green;
} else {
  icon = Icons.cancel;
  iconColor = Colors.red;
}


    return GestureDetector(
      onTap: isEmpty
          ? () => _addOrEditPersonDialog(apptId, index, null)
          : () => _cyclePresence(apptId, index, presence),
      onLongPress: (isEmpty) ? null : () => _confirmRemoveDialog(apptId, index, name),
      onDoubleTap: isEmpty ? null : () => _addOrEditPersonDialog(apptId, index, name),
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
    final byDay = <DateTime, List<Map<String, dynamic>>>{};

    for (final a in _appointments) {
      final dt = DateTime.parse(a['appointment_datetime']);
      final key = DateTime(dt.year, dt.month, dt.day);
      byDay.putIfAbsent(key, () => []).add(a);
    }

    final output = <Map<String, dynamic>>[];
    final days = byDay.keys.toList()..sort();

    for (final d in days) {
      output.add({'type': 'header', 'date': d});
      final list = byDay[d]!
        ..sort((a, b) => DateTime.parse(a['appointment_datetime'])
            .compareTo(DateTime.parse(b['appointment_datetime'])));
      for (final a in list) {
        output.add({'type': 'appointment', 'data': a});
      }
    }

    return output;
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
