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
    return const MaterialApp(title: "Agenda", home: AgendaPage());
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
  bool _copying = false;
  String _copyMessage = "";

  late DateTime _currentMonday;
  late DateTime _currentFriday;

  // Allowed fixed times
  final List<String> fixedTimes = [
    "08:30",
    "09:30",
    "10:30",
    "11:30",
    "12:30",
    "14:00",
    "15:00",
    "16:00",
    "17:00",
  ];

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _currentMonday = today.subtract(Duration(days: today.weekday - 1));
    _currentFriday = _currentMonday.add(const Duration(days: 4));
    _loadWeek();
  }

  // -------------------------
  // Load appointments for current week (Mon-Fri)
  // -------------------------
  Future<void> _loadWeek() async {
    setState(() => _loading = true);

    final mondayUtc = DateTime.utc(_currentMonday.year, _currentMonday.month, _currentMonday.day);
    final fridayUtc = DateTime.utc(
      _currentFriday.year,
      _currentFriday.month,
      _currentFriday.day,
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

  // -------------------------
  // Helpers
  // -------------------------
  DateTime _stripTime(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _weekStartsInFuture() {
    final today = DateTime.now();
    final todayStripped = DateTime(today.year, today.month, today.day);
    return _currentMonday.isAfter(todayStripped);
  }

  bool get _isCurrentWeekEmpty {
    // A week is empty if none of the appointments in that week have any patient_name filled.
    for (final a in _appointments) {
      if ((a['patient_name1'] as dynamic) != null ||
          (a['patient_name2'] as dynamic) != null ||
          (a['patient_name3'] as dynamic) != null) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic>? _findAppointment(DateTime dt) {
    for (final a in _appointments) {
      final stored = DateTime.parse(a['appointment_datetime']).toLocal();
      if (stored.year == dt.year &&
          stored.month == dt.month &&
          stored.day == dt.day &&
          stored.hour == dt.hour &&
          stored.minute == dt.minute) {
        return a;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _createAppointment(DateTime dt) async {
    final inserted = await supabase.from("appointments").insert({
      "appointment_datetime": dt.toUtc().toIso8601String(),
      "patient_name1": null,
      "patient_name2": null,
      "patient_name3": null,
      "patient_presence1": null,
      "patient_presence2": null,
      "patient_presence3": null,
    }).select().single();

    return inserted;
  }

  Future<void> _applyAddOrEdit(
    DateTime dt,
    int index,
    Map<String, dynamic>? appt,
    String colName,
    String colPresence,
    String name,
  ) async {
    if (name.isEmpty) return;

    Map<String, dynamic> row;
    if (appt == null) {
      row = await _createAppointment(dt);
      _appointments.add(row);
    } else {
      row = appt;
    }

    await supabase.from("appointments").update({
      colName: name,
      colPresence: null,
    }).eq('id', row['id']);

    if (!mounted) return;

    row[colName] = name;
    row[colPresence] = null;

    setState(() {});
  }

  Future<void> _removePerson(Map<String, dynamic> appt, int index) async {
    final colName = "patient_name${index + 1}";
    final colPresence = "patient_presence${index + 1}";

    await supabase.from("appointments").update({
      colName: null,
      colPresence: null,
    }).eq("id", appt['id']);

    if (!mounted) return;

    appt[colName] = null;
    appt[colPresence] = null;

    setState(() {});
  }

  Future<void> _cyclePresence(Map<String, dynamic> appt, int index) async {
    final col = "patient_presence${index + 1}";
    final current = appt[col] as bool?;
    bool? next;
    if (current == null) {
      next = true;
    } else if (current == true) {
      next = false;
    } else {
      next = null;
    }

    await supabase.from("appointments").update({col: next}).eq("id", appt['id']);

    if (!mounted) return;

    appt[col] = next;
    setState(() {});
  }

  // -------------------------
  // Copy algorithm: day-by-day
  // For each target weekday (Mon..Fri):
  //  - If target day has appointments with patients -> skip (shouldn't happen since we show button only on empty week)
  //  - Else search backwards by 7-day steps for the earliest previous same weekday that has at least one patient.
  //  - Copy ALL appointments found on that source day to the target day (presences set to null).
  //  - Only allow fixedTimes to be copied.
  // -------------------------
  Future<void> _copyWeekDayByDay() async {
    // Guard
    if (!_weekStartsInFuture() || !_isCurrentWeekEmpty) return;

    setState(() {
      _copying = true;
      _copyMessage = "Preparing to copy...";
    });

    // We'll look back up to 52 weeks (1 year). Adjust if you need more.
    const int maxWeeksBack = 52;

    for (int dayOffset = 0; dayOffset < 5; dayOffset++) {
      final targetDay = _stripTime(_currentMonday.add(Duration(days: dayOffset)));
      // If target day already has any patient booked (defensive), skip
      final targetHasPatient = _appointments.any((a) {
        final dt = DateTime.parse(a['appointment_datetime']).toLocal();
        return dt.year == targetDay.year &&
            dt.month == targetDay.month &&
            dt.day == targetDay.day &&
            ((a['patient_name1'] as dynamic) != null ||
                (a['patient_name2'] as dynamic) != null ||
                (a['patient_name3'] as dynamic) != null);
      });
      if (targetHasPatient) {
        // Update progress and continue
        if (!mounted) break;
        setState(() => _copyMessage = "Day ${DateFormat.EEEE().format(targetDay)} already has data — skipping.");
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      // search backwards week-by-week for the earliest previous same weekday that has at least one patient
      DateTime checkDay = targetDay.subtract(const Duration(days: 7));
      bool copiedThisDay = false;

      for (int weekBack = 0; weekBack < maxWeeksBack && !copiedThisDay; weekBack++) {
        if (!mounted) break;

        setState(() => _copyMessage =
            "Searching for ${DateFormat.EEEE().format(targetDay)} — week ${weekBack + 1} back...");

        final startUtc = DateTime.utc(checkDay.year, checkDay.month, checkDay.day);
        final endUtc = startUtc.add(const Duration(hours: 23, minutes: 59, seconds: 59));

        final raw = await supabase
            .from('appointments')
            .select()
            .gte('appointment_datetime', startUtc.toIso8601String())
            .lte('appointment_datetime', endUtc.toIso8601String())
            .order('appointment_datetime');

        final List<Map<String, dynamic>> dayRows = List<Map<String, dynamic>>.from(raw);

        // Keep only rows that have at least one patient (non-null name)
        final nonEmptyRows = dayRows.where((r) {
          return (r['patient_name1'] as dynamic) != null ||
              (r['patient_name2'] as dynamic) != null ||
              (r['patient_name3'] as dynamic) != null;
        }).toList();

        if (nonEmptyRows.isNotEmpty) {
          // We found a source day to copy. Copy each appointment, but only if its time is in fixedTimes.
          setState(() => _copyMessage =
              "Copying ${nonEmptyRows.length} appointments from ${DateFormat.yMd().format(checkDay)} to ${DateFormat.yMd().format(targetDay)}...");

          // Build list of inserts (batch)
          final inserts = <Map<String, dynamic>>[];

          for (final r in nonEmptyRows) {
            final srcDtLocal = DateTime.parse(r['appointment_datetime']).toLocal();
            final hhmm = DateFormat("HH:mm").format(srcDtLocal);

            if (!fixedTimes.contains(hhmm)) {
              // skip if source time not allowed
              continue;
            }

            final newDt = DateTime(
              targetDay.year,
              targetDay.month,
              targetDay.day,
              srcDtLocal.hour,
              srcDtLocal.minute,
            );

            inserts.add({
              "appointment_datetime": newDt.toUtc().toIso8601String(),
              "patient_name1": r['patient_name1'],
              "patient_name2": r['patient_name2'],
              "patient_name3": r['patient_name3'],
              "patient_presence1": null,
              "patient_presence2": null,
              "patient_presence3": null,
            });
          }

          if (inserts.isNotEmpty) {
            // Batch insert
            await supabase.from('appointments').insert(inserts);
          }

          copiedThisDay = true;
        }

        // move to previous week
        checkDay = checkDay.subtract(const Duration(days: 7));
      } // end weekBack loop

      // Visual pause to show progress (small)
      if (!mounted) break;
      setState(() {
        if (copiedThisDay) {
          _copyMessage =
              "Finished copying for ${DateFormat.EEEE().format(targetDay)}.";
        } else {
          _copyMessage =
              "No previous non-empty ${DateFormat.EEEE().format(targetDay)} found (skipped).";
        }
      });

      // small delay so user sees status change
      await Future.delayed(const Duration(milliseconds: 400));
    } // end dayOffset loop

    // reload week to reflect new data and hide copy UI
    await _loadWeek();

    if (!mounted) return;
    setState(() {
      _copying = false;
      _copyMessage = "";
    });
  }

  // -------------------------
  // UI pieces: add/edit dialog, remove confirm (kept lightweight)
  // -------------------------
  Future<void> _addOrEditPersonDialog(DateTime dt, int index, Map<String, dynamic>? appt, String? currentName) async {
    final controller = TextEditingController(text: currentName);
    final colName = "patient_name${index + 1}";
    final colPresence = "patient_presence${index + 1}";

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
              Navigator.of(dialogContext).pop();
              _applyAddOrEdit(dt, index, appt, colName, colPresence, controller.text.trim());
            },
            child: Text(currentName == null ? "Add" : "Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveDialog(Map<String, dynamic> appt, int index, String name) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Remove person"),
        content: Text("Remove \"$name\" from this appointment?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _removePerson(appt, index);
            },
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientRow(DateTime dt, Map<String, dynamic>? appt, int index) {
    final name = appt?["patient_name${index + 1}"] as String?;
    final presence = appt?["patient_presence${index + 1}"] as bool?;
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
      icon = Icons.check_circle;
      iconColor = Colors.green;
    } else {
      icon = Icons.cancel;
      iconColor = Colors.red;
    }

    return GestureDetector(
      onTap: () => isEmpty
          ? _addOrEditPersonDialog(dt, index, appt, null)
          : _cyclePresence(appt!, index),
      onDoubleTap: isEmpty ? null : () => _addOrEditPersonDialog(dt, index, appt, name),
      onLongPress: isEmpty ? null : () => _confirmRemoveDialog(appt!, index, name),
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
          Icon(icon, color: iconColor, size: 28),
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(DateTime dt, Map<String, dynamic>? appt) {
    final hour = DateFormat("HH:mm").format(dt);

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
                child: Center(child: Text(hour, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPatientRow(dt, appt, 0),
                    _buildPatientRow(dt, appt, 1),
                    _buildPatientRow(dt, appt, 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginator() {
    final fmt = DateFormat("dd MMM");
    final label = "${fmt.format(_currentMonday)} — ${fmt.format(_currentFriday)}";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.grey.withValues(alpha: 0.12),
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

  void _prevWeek() {
    _currentMonday = _currentMonday.subtract(const Duration(days: 7));
    _currentFriday = _currentMonday.add(const Duration(days: 4));
    _loadWeek();
  }

  void _nextWeek() {
    _currentMonday = _currentMonday.add(const Duration(days: 7));
    _currentFriday = _currentMonday.add(const Duration(days: 4));
    _loadWeek();
  }

  // -------------------------
  // Build
  // -------------------------
  @override
  Widget build(BuildContext context) {
    // If we're copying show full-screen progress so user has clear feedback
    if (_copying) {
      return Scaffold(
        appBar: AppBar(title: const Text("Agenda")),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_copyMessage, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text("Copying day-by-day... please wait"),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Agenda"),
        actions: [
          // Copy button appears only if the current week is empty AND starts in the future
          if (_isCurrentWeekEmpty && _weekStartsInFuture())
            IconButton(
              icon: const Icon(Icons.auto_fix_high),
              tooltip: "Copy previous weeks day-by-day",
              onPressed: _copyWeekDayByDay,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildPaginator(),
          Expanded(
            child: ListView.builder(
              itemCount: 5 * fixedTimes.length,
              itemBuilder: (context, index) {
                final dayOffset = index ~/ fixedTimes.length;
                final timeOffset = index % fixedTimes.length;

                final day = _currentMonday.add(Duration(days: dayOffset));
                final parts = fixedTimes[timeOffset].split(":");
                final hour = int.parse(parts[0]);
                final minute = int.parse(parts[1]);

                final dt = DateTime(day.year, day.month, day.day, hour, minute);
                final appt = _findAppointment(dt);

                // Header at first slot of each day
                if (timeOffset == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                        child: Text(DateFormat("EEEE, dd MMM").format(day),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      _buildAppointmentCard(dt, appt),
                    ],
                  );
                }

                return _buildAppointmentCard(dt, appt);
              },
            ),
          ),
        ],
      ),
    );
  }
}
