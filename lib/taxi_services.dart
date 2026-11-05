import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'taxi_config.dart';
import 'taxi_models.dart';

class RouteInfo {
 final List<LatLng> points; final double distanceKm, trafficFactor, price; final int durationMin;
 const RouteInfo(this.points,this.distanceKm,this.durationMin,this.trafficFactor,this.price);
}
class TaxiService {
 static final Dio dio=Dio(BaseOptions(connectTimeout: const Duration(seconds:8),receiveTimeout: const Duration(seconds:12)));
 static double _traffic() {
  final h=DateTime.now().hour;
  if ((h>=7&&h<=10)||(h>=16&&h<=19)) return 1.35;
  if(h>=11&&h<=15) return 1.15;
  return 1.0;
 }
 static double _distance(LatLng a,LatLng b) {
  const r=6371.0; final d1=(b.latitude-a.latitude)*math.pi/180, d2=(b.longitude-a.longitude)*math.pi/180;
  final x=math.sin(d1/2)*math.sin(d1/2)+math.cos(a.latitude*math.pi/180)*math.cos(b.latitude*math.pi/180)*math.sin(d2/2)*math.sin(d2/2);
  return 2*r*math.asin(math.sqrt(x));
 }
 static Future<RouteInfo> route(LatLng a,LatLng b) async {
  var km=_distance(a,b)*1.25; var minutes=(km/30*60).round().clamp(3,240); var pts=<LatLng>[a,b];
  try {
   final res=await dio.get('https://router.project-osrm.org/route/v1/driving/${a.longitude},${a.latitude};${b.longitude},${b.latitude}',queryParameters:{'overview':'full','geometries':'geojson'});
   final routes=res.data['routes'] as List;
   if(routes.isNotEmpty) { final r=routes.first; km=(r['distance'] as num).toDouble()/1000; minutes=((r['duration'] as num).toDouble()/60).round();
    pts=(r['geometry']['coordinates'] as List).map((p)=>LatLng((p[1] as num).toDouble(),(p[0] as num).toDouble())).toList(); }
  } catch (_) {}
  final factor=_traffic(), adjusted=(minutes*factor).ceil().clamp(1,300);
  return RouteInfo(pts,km,adjusted,factor,double.parse((2.50+km*.85+adjusted*.12).toStringAsFixed(2)));
 }
 static Future<void> saveProfile(String role,String name,String phone) async {
  final u=sb.auth.currentUser!;
  await sb.from('profiles').upsert({'id':u.id,'role':role,'full_name':name,'phone':phone});
 }
 static Future<String> createRide(String from,String to,LatLng a,LatLng b,RouteInfo r) async {
  final row=await sb.from('rides').insert({'passenger_id':sb.auth.currentUser!.id,'pickup_label':from,'destination_label':to,
   'pickup_lat':a.latitude,'pickup_lng':a.longitude,'destination_lat':b.latitude,'destination_lng':b.longitude,
   'distance_km':r.distanceKm,'duration_min':r.durationMin,'traffic_factor':r.trafficFactor,'price':r.price,'status':'requested'}).select('id').single();
  return row['id'];
 }
 static Future<List<TaxiRide>> available() async {
  final rows=await sb.from('rides').select().eq('status','requested').order('created_at');
  return (rows as List).map((e)=>TaxiRide.fromMap(e)).toList();
 }
 static Future<List<TaxiRide>> mine(String role) async {
  final id=sb.auth.currentUser!.id;
  final rows=role=='driver'?await sb.from('rides').select().eq('driver_id',id).order('created_at',ascending:false).limit(20):
   await sb.from('rides').select().eq('passenger_id',id).order('created_at',ascending:false).limit(20);
  return (rows as List).map((e)=>TaxiRide.fromMap(e)).toList();
 }
 static Future<void> updateRide(String id,Map<String,dynamic> data) async { await sb.from('rides').update(data).eq('id',id); }
 static Future<void> publishLocation(LatLng p) async {
  final id=sb.auth.currentUser!.id;
  await sb.from('driver_locations').upsert({'driver_id':id,'lat':p.latitude,'lng':p.longitude,'updated_at':DateTime.now().toUtc().toIso8601String()});
 }
 static Future<LatLng?> driverLocation(String id) async {
  final r=await sb.from('driver_locations').select().eq('driver_id',id).maybeSingle();
  return r==null?null:LatLng((r['lat'] as num).toDouble(),(r['lng'] as num).toDouble());
 }
}
