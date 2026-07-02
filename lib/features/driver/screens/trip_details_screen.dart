import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/localization/app_localizations.dart';


/// Detailed view of a single completed trip
class TripDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final card = isDark ? AppColors.darkSurface : AppColors.surface;
    final cardSoft = isDark ? AppColors.darkSurfaceSoft : AppColors.surfaceSoft;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final text = isDark ? AppColors.darkOnSurface : AppColors.textDark;
    final sub = isDark
        ? AppColors.darkOnSurface.withValues(alpha: 0.6)
        : AppColors.textGrey;
    final green = AppColors.secondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        title: Text(
          context.tr('tripDetails'),
          style: TextStyle(color: text, fontWeight: FontWeight.bold),
        ),
        foregroundColor: text,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Route Summary ──────────────────────────────────────────────────
            GlassCard(
              borderRadius: BorderRadius.circular(18),
              color: card,
              border: Border.all(color: border),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('route'),
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 14,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Pickup
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on,
                        color: AppColors.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('pickupLocation'),
                              style: TextStyle(fontSize: 11, color: sub),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              trip['pickup'] as String? ?? '—',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: text,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 1,
                    color: border.withValues(alpha: 0.3),
                    margin: const EdgeInsets.symmetric(horizontal: 26),
                  ),
                  const SizedBox(height: 12),
                  // Destination
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on,
                        color: AppColors.accentRed,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('destination'),
                              style: TextStyle(fontSize: 11, color: sub),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              trip['destination'] as String? ?? '—',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 13,
                                color: text,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Trip Metrics ───────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    Icons.straighten,
                    context.tr('distance'),
                    trip['distance'] as String? ?? '—',
                    card,
                    border,
                    text,
                    sub,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    Icons.directions_car,
                    context.tr('vehicleType'),
                    trip['rideType'] as String? ?? '—',
                    card,
                    border,
                    text,
                    sub,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Passenger Info ─────────────────────────────────────────────────
            GlassCard(
              borderRadius: BorderRadius.circular(18),
              color: card,
              border: Border.all(color: border),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('passengerInformation'),
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 14,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: green.withValues(alpha: 0.2),
                        child: Icon(Icons.person, color: green, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              trip['passengerName'] as String? ??
                                  trip['riderName'] as String? ??
                                  'Unknown',
                              style: AppTextStyles.heading.copyWith(
                                fontSize: 14,
                                color: text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if ((trip['passengerPhone'] as String?)
                                    ?.isNotEmpty ==
                                true) ...[
                              Text(
                                trip['passengerPhone'] as String,
                                style: TextStyle(fontSize: 12, color: sub),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Time Information ───────────────────────────────────────────────
            GlassCard(
              borderRadius: BorderRadius.circular(18),
              color: card,
              border: Border.all(color: border),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('timeline'),
                    style: AppTextStyles.heading.copyWith(
                      fontSize: 14,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTimelineItem(
                    Icons.calendar_today,
                    context.tr('date'),
                    trip['date'] as String? ?? '—',
                    text,
                    sub,
                  ),
                  const SizedBox(height: 10),
                  _buildTimelineItem(
                    Icons.schedule,
                    context.tr('startTime'),
                    trip['startTime'] as String? ?? '—',
                    text,
                    sub,
                  ),
                  const SizedBox(height: 10),
                  _buildTimelineItem(
                    Icons.access_time,
                    context.tr('endTime'),
                    trip['endTime'] as String? ?? '—',
                    text,
                    sub,
                  ),
                  if ((trip['completedAt'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    _buildTimelineItem(
                      Icons.check_circle,
                      context.tr('completedAt'),
                      trip['completedAt'] as String,
                      text,
                      sub,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Fare and Payment ───────────────────────────────────────────────
            if ((trip['fare'] as String?)?.isNotEmpty == true)
              GlassCard(
                borderRadius: BorderRadius.circular(18),
                color: green.withValues(alpha: 0.1),
                border: Border.all(color: green.withValues(alpha: 0.3)),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('fareDetails'),
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          context.tr('totalFare'),
                          style: TextStyle(fontSize: 13, color: sub),
                        ),
                        Text(
                          '₹${(trip['fare'] as String).replaceAll(RegExp(r'[^0-9.]'), '')}',
                          style: AppTextStyles.heading.copyWith(
                            fontSize: 16,
                            color: green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // ── Comments/Notes ────────────────────────────────────────────────
            if ((trip['notes'] as String?)?.isNotEmpty == true) ...[
              GlassCard(
                borderRadius: BorderRadius.circular(18),
                color: card,
                border: Border.all(color: border),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('notes'),
                      style: AppTextStyles.heading.copyWith(
                        fontSize: 14,
                        color: text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      trip['notes'] as String,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 12,
                        color: sub,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Ride ID ────────────────────────────────────────────────────────
            if ((trip['rideId'] as String?)?.isNotEmpty == true)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: sub),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                              context.tr('rideId'),
                              style: TextStyle(fontSize: 10, color: sub),
                            ),
                          Text(
                            trip['rideId'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              color: text,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    IconData icon,
    String label,
    String value,
    Color card,
    Color border,
    Color text,
    Color sub,
  ) {
    return GlassCard(
      borderRadius: BorderRadius.circular(14),
      color: card,
      border: Border.all(color: border),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.secondary),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: text,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: sub)),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    IconData icon,
    String label,
    String value,
    Color text,
    Color sub,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: sub)),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.body.copyWith(
                  fontSize: 12,
                  color: text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
