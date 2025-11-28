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
  // REMOVE PERSON
  // -------------------------------------------------------------
  Future<void> _removePerson(int apptId, int index) async {
    final col = "patient_name${index + 1}";
    final colPres = "patient_presence${index + 1}";

    await supabase
        .from('appointments')
        .update({col: null, colPres: null})
        .eq('id', apptId);

    if (!mounted) return;

    final appt = _appointments.firstWhere((a) => a['id'] == apptId);
    appt[col] = null;
    appt[colPres] = null;

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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);        // close immediately
              _removePerson(apptId, index);        // async afterwards
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
    await supabase
        .from('appointments')
        .update({column: name, "patient_presence${index + 1}": null})
        .eq('id', apptId);

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
        title: const Text("Add patient"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter name"),
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

              Navigator.pop(dialogContext);
              _addPerson(apptId, index, column, name);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // EDIT PERSON
  // -------------------------------------------------------------
  Future<void> _editPerson(
    int apptId,
    int index,
    String column,
    String newName,
  ) async {
    await supabase
        .from('appointments')
        .update({column: newName})
        .eq('id', apptId);

    if (!mounted) return;

    final appt = _appointments.firstWhere((a) => a['id'] == apptId);
    appt[column] = newName;
    setState(() {});
  }

  Future<void> _editPersonDialog(int apptId, int index, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final column = "patient_name${index + 1}";

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Edit name"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Enter new name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              if (newName == currentName) return;

              Navigator.pop(dialogContext);
              _editPerson(apptId, index, column, newName);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // PRESENCE
  // -------------------------------------------------------------
  bool? _nextPresence(bool? current) {
    if (current == null) return true;
    if (current == true) return false;
    return null;
  }

  Future<void> _updatePresence(int apptId, int index, bool? value) async {
    await supabase
        .from('appointments')
        .update({'patient_presence${index + 1}': value})
        .eq('id', apptId);
  }

  void _updateLocalPresence(int apptId, int index, bool? value) {
    final appt = _appointments.firstWhere((a) => a['id'] == apptId);
    appt['patient_presence${index + 1}'] = value;
    setState(() {});
  }

  // -------------------------------------------------------------
  // PATIENT ROW
  // -------------------------------------------------------------
  Widget _buildPatientRow(int apptId, int index, String? name, bool? presence) {
    final empty = name == null || name.trim().isEmpty;

    IconData icon;
    Color color;

    if (empty) {
      icon = Icons.add_circle_outline;
      color = Colors.blue.withValues(alpha: 0.7);
    } else if (presence == null) {
      icon = Icons.help_outline;
      color = Colors.grey;
    } else if (presence == true) {
      icon = Icons.check;
      color = Colors.green;
    } else {
      icon = Icons.close;
      color = Colors.red;
    }

    return GestureDetector(
      onLongPress: empty
          ? null
          : () => _confirmRemoveDialog(apptId, index, name),

      onTap: () async {
        if (empty) {
          await _addPersonDialog(apptId, index);
        } else {
          await _editPersonDialog(apptId, index, name);
        }
      },

      onDoubleTap: empty
          ? null
          : () async {
              final next = _nextPresence(presence);
              await _updatePresence(apptId, index, next);
              if (!mounted) return;
              _updateLocalPresence(apptId, index, next);
            },

      child: Row(
        children: [
          Expanded(
            child: Text(
              empty ? "(empty)" : name,
              style: TextStyle(
                fontSize: 16,
                color: empty
                    ? Colors.black.withValues(alpha: 0.4)
                    : Colors.black,
              ),
            ),
          ),
          Icon(icon,
              size: 28,
              color: color,
              weight: 900,
              shadows: const [
                Shadow(
                  blurRadius: 2,
                  color: Colors.black26,
                  offset: Offset(0, 1),
                )
              ]),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // APPOINTMENT CARD
  // -------------------------------------------------------------
  Widget _buildAppointmentCard(Map<String, dynamic> appt) {
    final dt = DateTime.parse(appt['appointment_datetime']);
    final hour = DateFormat("HH:mm").format(dt);
    final apptId = appt['id'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPatientRow(apptId, 0, appt['patient_name1'],
                        appt['patient_presence1']),
                    _buildPatientRow(apptId, 1, appt['patient_name2'],
                        appt['patient_presence2']),
                    _buildPatientRow(apptId, 2, appt['patient_name3'],
                        appt['patient_presence3']),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // FLATTEN LIST WITH HEADERS
  // -------------------------------------------------------------
  List<Map<String, dynamic>> _flatten() {
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
  // WEEK SWITCH
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.grey.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              onPressed: _prevWeek,
              icon: const Icon(Icons.chevron_left, size: 32)),
          Text(
            "${fmt.format(_currentWeekMonday)} — ${fmt.format(_currentWeekFriday)}",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
              onPressed: _nextWeek,
              icon: const Icon(Icons.chevron_right, size: 32)),
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

    final items = _flatten();

    return Scaffold(
      appBar: AppBar(title: const Text("Agenda")),
      body: Column(
        children: [
          _buildPaginator(),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child:
                        Text("No appointments for this week", style: TextStyle(fontSize: 18)),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      if (item['type'] == 'header') {
                        final day = item['date'] as DateTime;
                        return Container(
                          padding:
                              const EdgeInsets.fromLTRB(12, 16, 12, 6),
                          color: Colors.grey.withValues(alpha: 0.12),
                          child: Text(
                            DateFormat("EEEE, dd MMM").format(day),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18),
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
