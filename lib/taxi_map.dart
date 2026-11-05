import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
class TaxiMap extends StatelessWidget {
 final LatLng from,to; final List<LatLng> route; final LatLng? car;
 const TaxiMap({super.key,required this.from,required this.to,this.route=const [],this.car});
 @override Widget build(BuildContext c){
  final center=LatLng((from.latitude+to.latitude)/2,(from.longitude+to.longitude)/2);
  return FlutterMap(options:MapOptions(initialCenter:center,initialZoom:12),children:[
   TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.example.taxi_app'),
   if(route.length>1) PolylineLayer(polylines:[Polyline(points:route,color:Colors.blue,width:5)]),
   MarkerLayer(markers:[
    Marker(point:from,width:42,height:42,child:const Icon(Icons.trip_origin,color:Colors.green,size:34)),
    Marker(point:to,width:42,height:42,child:const Icon(Icons.location_on,color:Colors.red,size:40)),
    if(car!=null) Marker(point:car!,width:48,height:48,child:const Icon(Icons.local_taxi,color:Colors.black,size:42)),
   ])
  ]);
 }
}
