import 'package:flutter_test/flutter_test.dart';

import 'package:video_splitview/frontend/widgets/common.dart';

void main() {
  testWidgets('formatTime produz m:ss e h:mm:ss', (tester) async {
    expect(formatTime(0), '0:00');
    expect(formatTime(65), '1:05');
    expect(formatTime(3725), '1:02:05');
    await tester.pump();
  });
}
