import 'package:flutter/material.dart';
import '../services/alert_service.dart';
import '../services/theme_service.dart';

const Color _notificationPrimary = Color(0xFF6C4DF6);
Color get _notificationBackground => AppThemeService.instance.pageBackground;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final notifications = await AlertService.instance.getNotificationHistory();
    if (!mounted) return;
    setState(() {
      _notifications = notifications;
      _isLoading = false;
    });
  }

  Future<void> _markAllRead() async {
    await AlertService.instance.markAllNotificationsRead();
    await _loadNotifications();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear notifications?'),
        content: const Text('This removes saved in-app notification history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AlertService.instance.clearNotificationHistory();
    if (!mounted) return;
    setState(() => _notifications = []);
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final sameDay =
        now.year == dateTime.year &&
        now.month == dateTime.month &&
        now.day == dateTime.day;
    final time = TimeOfDay.fromDateTime(dateTime).format(context);
    if (sameDay) return 'Today · $time';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} · $time';
  }

  IconData _iconFor(AppNotification notification) {
    final title = notification.title.toLowerCase();
    if (title.contains('wake')) return Icons.bedtime_outlined;
    if (title.contains('route')) return Icons.alt_route;
    if (title.contains('destination')) return Icons.location_on_outlined;
    return Icons.notifications_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any(
      (notification) => !notification.isRead,
    );

    return Scaffold(
      backgroundColor: _notificationBackground,
      appBar: AppBar(
        backgroundColor: _notificationBackground,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back,
            color: AppThemeService.instance.primaryText,
          ),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(
            color: AppThemeService.instance.primaryText,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (hasUnread)
            IconButton(
              tooltip: 'Mark all as read',
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all, color: _notificationPrimary),
            ),
          if (_notifications.isNotEmpty)
            IconButton(
              tooltip: 'Clear notification history',
              onPressed: _clearHistory,
              icon: Icon(
                Icons.delete_outline,
                color: AppThemeService.instance.secondaryText,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _notificationPrimary),
            )
          : _notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 54,
                    color: AppThemeService.instance.mutedText,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No notifications yet',
                    style: TextStyle(
                      color: AppThemeService.instance.primaryText,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _notifications.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                return Material(
                  color: notification.isRead
                      ? AppThemeService.instance.surface
                      : AppThemeService.instance.isDark
                      ? const Color(0xFF302A46)
                      : const Color(0xFFF1EDFF),
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: _notificationPrimary.withValues(
                        alpha: 0.12,
                      ),
                      child: Icon(
                        _iconFor(notification),
                        color: _notificationPrimary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: notification.isRead
                            ? FontWeight.w600
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(notification.body),
                          const SizedBox(height: 5),
                          Text(
                            _formatTime(notification.createdAt),
                            style: TextStyle(
                              color: AppThemeService.instance.mutedText,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: notification.isRead
                        ? null
                        : const Icon(
                            Icons.circle,
                            size: 9,
                            color: _notificationPrimary,
                          ),
                  ),
                );
              },
            ),
    );
  }
}
