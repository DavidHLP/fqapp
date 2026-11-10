import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/desktop_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'throwing close hook retains ownership and permits a close retry',
    () async {
      final desktop = DesktopPlatform.instance;
      var stopped = 0;
      var released = 0;
      desktop.beforeClose = () async {
        stopped++;
        throw StateError('progress not saved');
      };
      desktop.afterClose = () async {
        released++;
      };
      desktop.onWindowClose();
      await Future<void>.delayed(Duration.zero);
      expect(stopped, 1);
      expect(released, 0);
      desktop.onWindowClose();
      await Future<void>.delayed(Duration.zero);
      expect(stopped, 2);
      expect(released, 0);
      desktop.beforeClose = null;
      desktop.afterClose = null;
    },
  );
}
