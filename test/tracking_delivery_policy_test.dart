import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/services/tracking_delivery_policy.dart';

void main() {
  test('only successful HTTP responses are acknowledged', () {
    expect(classifyTrackingResponse(200), TrackingDelivery.acknowledge);
    expect(classifyTrackingResponse(204), TrackingDelivery.acknowledge);
    expect(classifyTrackingResponse(400), TrackingDelivery.dropInvalid);
    expect(classifyTrackingResponse(404), TrackingDelivery.dropInvalid);
    expect(classifyTrackingResponse(401), TrackingDelivery.retry);
    expect(classifyTrackingResponse(426), TrackingDelivery.retry);
    expect(classifyTrackingResponse(500), TrackingDelivery.retry);
  });
}
