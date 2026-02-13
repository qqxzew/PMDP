// Transfer node model - represents a connection point between lines

/// Priority: which line waits for which
enum TransferPriority {
  /// Both wait symmetrically
  equal,
  /// Line 1 has priority (line 2 waits for line 1)
  line1First,
  /// Line 2 has priority (line 1 waits for line 2)
  line2First,
}

class TransferNode {
  final String id;
  final String stopId1;
  final String stopName1;
  final String lineNumber1;
  final String stopId2;
  final String stopName2;
  final String lineNumber2;
  final bool isAutomatic;
  int maxWaitMinutes;
  bool isEnabled;
  TransferPriority priority;

  TransferNode({
    required this.id,
    required this.stopId1,
    required this.stopName1,
    required this.lineNumber1,
    required this.stopId2,
    required this.stopName2,
    required this.lineNumber2,
    required this.isAutomatic,
    this.maxWaitMinutes = 5,
    this.isEnabled = true,
    this.priority = TransferPriority.equal,
  });

  /// Whether this is a same-stop transfer (automatic)
  bool get isSameStop => stopId1 == stopId2;

  String get displayLabel =>
      'Linka $lineNumber1 <-> Linka $lineNumber2 @ $stopName1${isSameStop ? '' : ' / $stopName2'}';

  String get priorityLabel {
    switch (priority) {
      case TransferPriority.equal:
        return 'Oba čekají';
      case TransferPriority.line1First:
        return 'Linka $lineNumber2 čeká na $lineNumber1';
      case TransferPriority.line2First:
        return 'Linka $lineNumber1 čeká na $lineNumber2';
    }
  }

  TransferNode copyWith({
    int? maxWaitMinutes,
    bool? isEnabled,
    TransferPriority? priority,
  }) {
    return TransferNode(
      id: id,
      stopId1: stopId1,
      stopName1: stopName1,
      lineNumber1: lineNumber1,
      stopId2: stopId2,
      stopName2: stopName2,
      lineNumber2: lineNumber2,
      isAutomatic: isAutomatic,
      maxWaitMinutes: maxWaitMinutes ?? this.maxWaitMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
      priority: priority ?? this.priority,
    );
  }
}
