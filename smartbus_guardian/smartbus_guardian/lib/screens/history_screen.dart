import 'package:flutter/material.dart';
import '../models/journey_record.dart';
import '../services/journey_service.dart';
import '../services/theme_service.dart';
import 'map_screen.dart';

const Color kPrimaryPurple = Color(0xFF6C4DF6);
Color get kBackground => AppThemeService.instance.pageBackground;
Color get kCardWhite => AppThemeService.instance.surface;
const Color kSuccessGreen = Color(0xFF2E7D32);
const Color kWarningOrange = Color(0xFFE65100);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final JourneyService _journeyService = JourneyService.instance;
  List<JourneyRecord> _allJourneys = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL'; // 'ALL', 'COMPLETED', 'CANCELLED'

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final list = await _journeyService.getJourneyHistory();
    if (mounted) {
      setState(() {
        _allJourneys = list;
        _isLoading = false;
      });
    }
  }

  List<JourneyRecord> get _filteredJourneys {
    if (_selectedFilter == 'COMPLETED') {
      return _allJourneys.where((j) => j.status == 'COMPLETED').toList();
    } else if (_selectedFilter == 'CANCELLED') {
      return _allJourneys.where((j) => j.status != 'COMPLETED').toList();
    }
    return _allJourneys;
  }

  double get _totalDistanceKm {
    return _allJourneys.fold(0.0, (sum, j) => sum + (j.distanceKm ?? 0.0));
  }

  int get _completedCount {
    return _allJourneys.where((j) => j.status == 'COMPLETED').length;
  }

  Future<void> _deleteJourney(JourneyRecord journey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Journey Record?'),
        content: Text(
          'Remove "${journey.destinationName}" from your journey history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _journeyService.deleteJourney(journey.id);
      await _loadHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Journey removed from history.'),
          backgroundColor: AppThemeService.instance.primaryText,
        ),
      );
    }
  }

  Future<void> _clearAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All History?'),
        content: const Text(
          'Are you sure you want to delete all saved journey history records?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _journeyService.clearAllHistory();
      await _loadHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('All journey records cleared.'),
          backgroundColor: AppThemeService.instance.primaryText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: AppThemeService.instance.primaryText,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Journey History',
          style: TextStyle(
            color: AppThemeService.instance.primaryText,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_allJourneys.isNotEmpty)
            IconButton(
              icon: Icon(
                Icons.delete_sweep_outlined,
                color: AppThemeService.instance.primaryText,
              ),
              tooltip: 'Clear All History',
              onPressed: _clearAllHistory,
            ),
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: AppThemeService.instance.primaryText,
            ),
            tooltip: 'Refresh',
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: kPrimaryPurple),
              )
            : RefreshIndicator(
                onRefresh: _loadHistory,
                color: kPrimaryPurple,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. STATS OVERVIEW CARDS
                      _buildStatsOverview(),

                      const SizedBox(height: 18),

                      // 2. SEGMENTED FILTER CHIPS
                      _buildFilterRow(),

                      const SizedBox(height: 16),

                      // 3. JOURNEYS LIST OR EMPTY STATE
                      if (_filteredJourneys.isEmpty)
                        _buildEmptyState()
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredJourneys.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final journey = _filteredJourneys[index];
                            return _buildJourneyCard(journey);
                          },
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ============================================================
  // STATS SUMMARY CARD
  // ============================================================
  Widget _buildStatsOverview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C4DF6), Color(0xFF8E7CF3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimaryPurple.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Travel Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Icon(Icons.directions_bus, color: Colors.white70, size: 22),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildStatItem(
                title: '${_allJourneys.length}',
                subtitle: 'Total Trips',
                icon: Icons.alt_route,
              ),
              _buildStatDivider(),
              _buildStatItem(
                title: '$_completedCount',
                subtitle: 'Completed',
                icon: Icons.check_circle_outline,
              ),
              _buildStatDivider(),
              _buildStatItem(
                title: '${_totalDistanceKm.toStringAsFixed(1)} km',
                subtitle: 'Distance',
                icon: Icons.speed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 36,
      width: 1,
      color: Colors.white.withValues(alpha: 0.25),
    );
  }

  // ============================================================
  // FILTER CHIPS
  // ============================================================
  Widget _buildFilterRow() {
    final filters = [
      {'id': 'ALL', 'label': 'All Trips (${_allJourneys.length})'},
      {'id': 'COMPLETED', 'label': 'Completed ($_completedCount)'},
      {
        'id': 'CANCELLED',
        'label': 'Ended Early (${_allJourneys.length - _completedCount})',
      },
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f['id'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                f['label']!,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : AppThemeService.instance.primaryText,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
              selected: isSelected,
              selectedColor: kPrimaryPurple,
              backgroundColor: kCardWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? kPrimaryPurple
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() => _selectedFilter = f['id']!);
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================
  // JOURNEY CARD
  // ============================================================
  Widget _buildJourneyCard(JourneyRecord journey) {
    final bool isCompleted = journey.status == 'COMPLETED';
    final dateFormatted = _formatDateTime(journey.startTime);

    return Container(
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Status & Date Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      dateFormatted,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? kSuccessGreen.withValues(alpha: 0.12)
                        : kWarningOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCompleted ? Icons.check_circle : Icons.stop_circle,
                        size: 13,
                        color: isCompleted ? kSuccessGreen : kWarningOrange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCompleted ? 'COMPLETED' : 'ENDED EARLY',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isCompleted ? kSuccessGreen : kWarningOrange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Route representation (Source -> Destination)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const Icon(
                      Icons.radio_button_checked,
                      size: 16,
                      color: Colors.blueAccent,
                    ),
                    Container(
                      width: 2,
                      height: 28,
                      color: Colors.grey.shade300,
                    ),
                    const Icon(
                      Icons.location_on,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        journey.sourceLocation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppThemeService.instance.primaryText,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        journey.destinationName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppThemeService.instance.primaryText,
                        ),
                      ),
                      if (journey.destinationAddress != null &&
                          journey.destinationAddress!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          journey.destinationAddress!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppThemeService.instance.secondaryText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Metrics footer: Distance, Duration, Sleep mode, Action buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.straighten,
                        size: 15,
                        color: kPrimaryPurple,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        journey.distanceKm != null
                            ? '${journey.distanceKm!.toStringAsFixed(1)} km'
                            : '-- km',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.timer_outlined,
                        size: 15,
                        color: kPrimaryPurple,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${journey.durationMinutes} min',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (journey.sleepModeEnabled) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.bedtime,
                                size: 11,
                                color: kPrimaryPurple,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'Sleep Mode',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: kPrimaryPurple,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.navigation_outlined,
                          size: 18,
                          color: kPrimaryPurple,
                        ),
                        tooltip: 'Start this trip again',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MapScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Delete',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _deleteJourney(journey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================
  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: kPrimaryPurple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.history_toggle_off,
              size: 48,
              color: kPrimaryPurple,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Journey Records Found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppThemeService.instance.primaryText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'When you take bus journeys with SmartBus Guardian, completed trip details and arrival alerts will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: AppThemeService.instance.secondaryText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              );
            },
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Start New Journey'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isYesterday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day - 1;

    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $ampm';

    if (isToday) return 'Today, $timeStr';
    if (isYesterday) return 'Yesterday, $timeStr';
    return '${dt.day}/${dt.month}/${dt.year}, $timeStr';
  }
}
