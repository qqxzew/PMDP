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
