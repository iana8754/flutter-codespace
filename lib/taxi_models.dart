import 'package:latlong2/latlong.dart';
class TaxiRide {
 final String id, passengerId, pickupLabel, destinationLabel, status;
 final String? driverId;
 final LatLng pickup, destination;
 final double distanceKm, trafficFactor, price;
 final int durationMin;
 TaxiRide.fromMap(Map<String,dynamic> m)
 : id=m['id'], passengerId=m['passenger_id'], driverId=m['driver_id'],
 pickupLabel=m['pickup_label'], destinationLabel=m['destination_label'],
 pickup=LatLng((m['pickup_lat'] as num).toDouble(),(m['pickup_lng'] as num).toDouble()),
 destination=LatLng((m['destination_lat'] as num).toDouble(),(m['destination_lng'] as num).toDouble()),
 distanceKm=(m['distance_km'] as num).toDouble(), durationMin=(m['duration_min'] as num).toInt(),
 trafficFactor=(m['traffic_factor'] as num).toDouble(), price=(m['price'] as num).toDouble(), status=m['status'];
 String get statusText => switch(status) {
 'requested'=>'Ищем водителя','accepted'=>'Водитель принял заказ','arriving'=>'Водитель едет к вам',
 'in_progress'=>'Поездка началась','completed'=>'Поездка завершена','cancelled'=>'Заказ отменён',_=>status};
}
