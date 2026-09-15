enum TrackingDelivery { acknowledge, retry, dropInvalid }

TrackingDelivery classifyTrackingResponse(int statusCode) {
  if (statusCode >= 200 && statusCode < 300) {
    return TrackingDelivery.acknowledge;
  }
  if (statusCode == 400 || statusCode == 404 || statusCode == 422) {
    return TrackingDelivery.dropInvalid;
  }
  return TrackingDelivery.retry;
}
