import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../core/theme.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SemanticsService.announce('Help screen.', TextDirection.ltr);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                    0,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Help & Instructions',
                      style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textOnLight,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: AppSpacing.sm),
                    _HelpSection(
                      title: 'Getting Started',
                      items: const [
                        'Turn on your iCan Cane and iCan Eye camera.',
                        'Open the app — it will search for your devices automatically.',
                        'Once connected, the app describes your surroundings using audio.',
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _HelpSection(
                      title: 'Home Screen',
                      items: const [
                        'The home screen shows your device status and latest scene description.',
                        'Tap "Describe Surroundings Now" to get an immediate description.',
                        'Tap "Pause Descriptions" to stop automatic audio.',
                        'Tap "Repeat Last" to hear the last description again.',
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _HelpSection(
                      title: 'Hazard Alerts',
                      items: const [
                        'When the cane detects an obstacle, you will hear an alert and feel a vibration.',
                        'Alerts tell you the direction and distance of the obstacle.',
                        'You can adjust alert sensitivity in Settings.',
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _HelpSection(
                      title: 'Settings',
                      items: const [
                        'Change speech speed and volume.',
                        'Choose between brief and detailed descriptions.',
                        'Adjust text size and enable high contrast mode.',
                        'Manage connected devices.',
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _HelpSection(
                      title: 'Troubleshooting',
                      items: const [
                        'If a device disconnects, go to Settings and tap Reconnect.',
                        'Make sure Bluetooth is enabled in your phone settings.',
                        'Keep devices within 3 feet of your phone for best connection.',
                        'If the camera image is unclear, try wiping the lens.',
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Semantics(
                      label: 'Contact support. Email help at ican app dot com for assistance.',
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceCardLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Need More Help?',
                                style: TextStyle(
                                  fontSize: 20.sp,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textOnLight,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Contact our support team and we will assist you.',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  color: AppColors.textOnLight,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final List<String> items;

  const _HelpSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final allItemsText = items.join('. ');

    return Semantics(
      label: '$title. $allItemsText.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceCardLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textOnLight,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: TextStyle(
                            fontSize: 18.sp,
                            color: AppColors.textOnLight,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              fontSize: 18.sp,
                              color: AppColors.textOnLight,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
