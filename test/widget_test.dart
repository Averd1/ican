import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ican/core/theme.dart';
import 'package:ican/services/ble_service.dart';
import 'package:ican/widgets/device_status_card.dart';

void main() {
  Widget buildTestApp(Widget child) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        theme: ICanTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('device status card renders connected state and battery', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestApp(
        DeviceStatusCard(
          deviceName: 'iCan Cane',
          connectionState: BleConnectionState.connected,
          batteryPercent: 84,
          onTap: () {},
          tapHint: 'Scans for iCan Cane',
        ),
      ),
    );

    expect(find.text('iCan Cane'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Battery: 84%'), findsOneWidget);
  });
}
