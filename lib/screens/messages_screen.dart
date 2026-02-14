import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/vehicle.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _replyController = TextEditingController();
  String? _replyToVehicleId;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final messages = List.of(state.messages)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zprávy a oznámení',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Komunikace s řidiči',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showComposeDialog(context, state),
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Nová zpráva'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (state.unreadCount > 0)
                    OutlinedButton(
                      onPressed: () => state.markAllRead(),
                      child: Text(
                          'Označit vše jako přečtené (${state.unreadCount})'),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Quick reply bar
              if (_replyToVehicleId != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.infoLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Odpověď pro: $_replyToVehicleId',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.info,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _replyController,
                          decoration: const InputDecoration(
                            hintText: 'Vaše odpověď...',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendReply(state),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _sendReply(state),
                        child: const Text('Odeslat'),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () =>
                            setState(() => _replyToVehicleId = null),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Messages list
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.message_outlined,
                                size: 48, color: AppTheme.textMuted),
                            SizedBox(height: 12),
                            Text(
                              'Žádné zprávy',
                              style: TextStyle(
                                fontSize: 16,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          return _MessageCard(
                            message: msg,
                            onReply:
                                msg.direction == MessageDirection.incoming
                                    ? () => setState(() {
                                          _replyToVehicleId =
                                              msg.vehicleId;
                                          _replyController.clear();
                                        })
                                    : null,
                            onMarkRead: !msg.isRead &&
                                    msg.direction ==
                                        MessageDirection.incoming
                                ? () => state.markMessageRead(msg.id)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _sendReply(AppState state) {
    if (_replyController.text.trim().isNotEmpty &&
        _replyToVehicleId != null) {
      state.sendMessage(_replyToVehicleId!, _replyController.text.trim());
      _replyController.clear();
      setState(() => _replyToVehicleId = null);
    }
  }

  void _showComposeDialog(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (ctx) => _ComposeMessageDialog(state: state),
    );
  }
}

class _ComposeMessageDialog extends StatefulWidget {
  final AppState state;

  const _ComposeMessageDialog({required this.state});

  @override
  State<_ComposeMessageDialog> createState() => _ComposeMessageDialogState();
}

class _ComposeMessageDialogState extends State<_ComposeMessageDialog> {
  final _messageController = TextEditingController();
  String _targetType = 'broadcast';
  String? _selectedDriverId;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectedIds = widget.state.connectedDriverIds;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.send, color: AppTheme.accent, size: 22),
          SizedBox(width: 8),
          Text('Nová zpráva řidiči'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Příjemce',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Všichni řidiči'),
                  selected: _targetType == 'broadcast',
                  onSelected: (_) => setState(() {
                    _targetType = 'broadcast';
                    _selectedDriverId = null;
                  }),
                  selectedColor: AppTheme.accent.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Konkrétní řidič'),
                  selected: _targetType == 'specific',
                  onSelected: (_) => setState(() {
                    _targetType = 'specific';
                  }),
                  selectedColor: AppTheme.accent.withValues(alpha: 0.2),
                ),
              ],
            ),
            if (_targetType == 'specific') ...[
              const SizedBox(height: 12),
              if (connectedIds.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: AppTheme.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Žádní řidiči nejsou připojeni. Zpráva bude doručena při příštím spojení.',
                          style: TextStyle(fontSize: 12, color: AppTheme.warning),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedDriverId,
                  decoration: const InputDecoration(
                    hintText: 'Vyberte řidiče...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: connectedIds.map((id) {
                    final info = widget.state.getConnectedDriverInfo(id);
                    final name = info['driverName'] ?? id;
                    final line = info['lineNumber'] ?? '';
                    return DropdownMenuItem(
                      value: id,
                      child: Text(
                        line.isNotEmpty ? '$name (Linka $line)' : name,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedDriverId = val),
                ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Zpráva',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Napište zprávu pro řidiče...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Rychlé zprávy',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _QuickMsgChip(
                  label: 'Změna trasy',
                  onTap: () => _messageController.text = 'Pozor: změna trasy. Sledujte pokyny dispečinku.',
                ),
                _QuickMsgChip(
                  label: 'Bez zpoždění',
                  onTap: () => _messageController.text = 'Dodržujte prosím jízdní řád bez zpoždění.',
                ),
                _QuickMsgChip(
                  label: 'Přestávka',
                  onTap: () => _messageController.text = 'Na konečné máte povolenou přestávku 10 min.',
                ),
                _QuickMsgChip(
                  label: 'Rozjezd výlukové trasy',
                  onTap: () => _messageController.text = 'Přejděte na výlukovou trasu dle aktuálního plánu.',
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Zrušit'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final text = _messageController.text.trim();
            if (text.isEmpty) return;
            if (_targetType == 'broadcast') {
              widget.state.sendBroadcast(text);
            } else if (_selectedDriverId != null) {
              widget.state.sendMessage(_selectedDriverId!, text);
            } else {
              return;
            }
            Navigator.pop(context);
          },
          icon: const Icon(Icons.send, size: 16),
          label: Text(
            _targetType == 'broadcast' ? 'Odeslat všem' : 'Odeslat',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _QuickMsgChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickMsgChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor: AppTheme.surfaceWhite,
      side: BorderSide(color: AppTheme.border),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final DispatchMessage message;
  final VoidCallback? onReply;
  final VoidCallback? onMarkRead;

  const _MessageCard({
    required this.message,
    this.onReply,
    this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final isIncoming = message.direction == MessageDirection.incoming;
    final timeFormat = DateFormat('HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isIncoming
            ? (message.isRead
                ? AppTheme.surfaceWhite
                : AppTheme.infoLight.withValues(alpha: 0.3))
            : AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isIncoming && !message.isRead
              ? AppTheme.accent.withValues(alpha: 0.3)
              : AppTheme.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Direction icon
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isIncoming
                  ? AppTheme.accent.withValues(alpha: 0.1)
                  : AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isIncoming ? Icons.call_received : Icons.call_made,
              size: 18,
              color: isIncoming ? AppTheme.accent : AppTheme.success,
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      message.vehicleName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isIncoming
                            ? AppTheme.infoLight
                            : AppTheme.successLight,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        isIncoming ? 'PŘIJATO' : 'ODESLÁNO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isIncoming
                              ? AppTheme.info
                              : AppTheme.success,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      timeFormat.format(message.timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  message.content,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Actions
          Column(
            children: [
              if (onReply != null)
                IconButton(
                  onPressed: onReply,
                  icon: const Icon(Icons.reply, size: 18),
                  tooltip: 'Odpovědět',
                  color: AppTheme.textMuted,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              if (onMarkRead != null)
                IconButton(
                  onPressed: onMarkRead,
                  icon: const Icon(Icons.done, size: 18),
                  tooltip: 'Označit jako přečtené',
                  color: AppTheme.textMuted,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
