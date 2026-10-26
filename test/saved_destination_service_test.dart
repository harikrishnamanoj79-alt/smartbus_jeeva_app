import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbus_guardian/services/saved_destination_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'saved destinations persist locally per account and can be removed',
    () async {
      final service = SavedDestinationService.instance;
      const userId = 42;
      final destination = await service.add(
        userId: userId,
        name: 'Central Station',
        latitude: 12.9716,
        longitude: 77.5946,
      );

      expect(await service.load(userId: userId), [destination]);
      expect(await service.load(userId: userId + 1), isEmpty);

      await service.remove(userId: userId, destination: destination);

      expect(await service.load(userId: userId), isEmpty);
    },
  );

  test('duplicate saved destinations are rejected', () async {
    final service = SavedDestinationService.instance;
    await service.add(
      userId: 42,
      name: 'Central Station',
      latitude: 12.9716,
      longitude: 77.5946,
    );

    await expectLater(
      service.add(
        userId: 42,
        name: 'central station',
        latitude: 12.9716,
        longitude: 77.5946,
      ),
      throwsArgumentError,
    );
  });
}
