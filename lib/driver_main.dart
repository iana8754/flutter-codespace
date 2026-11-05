import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'taxi_config.dart'; import 'taxi_auth.dart'; import 'taxi_services.dart'; import 'taxi_models.dart'; import 'taxi_map.dart'; import 'taxi_gps.dart';

Future<void> main() async { WidgetsFlutterBinding.ensureInitialized(); await Supabase.initialize(url:supabaseUrl,publishableKey:supabaseKey); runApp(const DriverApp()); }
class DriverApp extends StatelessWidget { const DriverApp({super.key}); @override Widget build(BuildContext c)=>MaterialApp(title:'Taxi Driver',debugShowCheckedModeBanner:false,theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.amber),home:StreamBuilder<AuthState>(stream:sb.auth.onAuthStateChange,builder:(c,s)=>sb.auth.currentSession==null?const TaxiAuthPage(role:'driver'):const DriverHome())); }
class DriverHome extends StatefulWidget { const DriverHome({super.key}); @override State<DriverHome> createState()=>_DriverHomeState(); }
class _DriverHomeState extends State<DriverHome> {
 final fallback=LatLng(56.9496,24.1052); LatLng? currentPosition; StreamSubscription<Position>? gpsSubscription; bool online=false;
 void msg(String t){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t)));}
 Future<void> setOnline(bool value) async {
  if(value){try{
   final first=await TaxiGps.currentPosition(); if(!mounted)return; setState(()=>currentPosition=first);
   await TaxiService.publishLocation(first);
   await gpsSubscription?.cancel();
   gpsSubscription=TaxiGps.watch().listen((p) async {
    final point=LatLng(p.latitude,p.longitude);
    if(mounted)setState(()=>currentPosition=point);
    try{await TaxiService.publishLocation(point);}catch(e){msg('Не удалось передать GPS: $e');}
   },onError:(e)=>msg('Ошибка GPS: $e'));
   if(mounted)setState(()=>online=true);
   msg('Вы в сети. Передача GPS включена.');
  }catch(e){msg('Не удалось включить GPS: $e');}}
  else {await gpsSubscription?.cancel();gpsSubscription=null; if(mounted)setState(()=>online=false); msg('Вы не в сети. Передача GPS остановлена.');}
 }
 @override void dispose(){gpsSubscription?.cancel();super.dispose();}
 Future<void> accept(TaxiRide r) async {try{await TaxiService.updateRide(r.id,{'driver_id':sb.auth.currentUser!.id,'status':'accepted'});msg('Заказ принят');}catch(e){msg('Не удалось принять заказ: $e');}}
 Future<void> status(TaxiRide r,String s) async {try{await TaxiService.updateRide(r.id,{'status':s});}catch(e){msg('$e');}}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Такси • Водитель'),actions:[IconButton(onPressed:()=>sb.auth.signOut(),icon:const Icon(Icons.logout))]),body:Column(children:[
 Expanded(flex:4,child:TaxiMap(from:currentPosition??fallback,to:currentPosition??fallback,car:currentPosition)),
 Padding(padding:const EdgeInsets.all(12),child:Row(children:[const Expanded(child:Text('Приём заказов и передача GPS',style:TextStyle(fontWeight:FontWeight.bold))),Switch(value:online,onChanged:setOnline),Text(online?'В сети':'Не в сети')])),
 if(online&&currentPosition!=null)Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Text('GPS: ${currentPosition!.latitude.toStringAsFixed(5)}, ${currentPosition!.longitude.toStringAsFixed(5)}')),
 Expanded(flex:6,child:StreamBuilder<List<Map<String,dynamic>>>(stream:sb.from('rides').stream(primaryKey:['id']).order('created_at'),builder:(c,s){
 if(s.hasError)return Center(child:Text('Ошибка: ${s.error}')); if(!s.hasData)return const Center(child:CircularProgressIndicator());
 final rides=s.data!.map((e)=>TaxiRide.fromMap(e)).toList();
 final visible=rides.where((r)=>(r.status=='requested'&&online)||(r.driverId==sb.auth.currentUser!.id&&r.status!='completed'&&r.status!='cancelled')).toList();
 if(visible.isEmpty)return const Center(child:Text('Пока нет заказов'));
 return ListView.builder(itemCount:visible.length,itemBuilder:(c,i){final r=visible[i],mine=r.driverId==sb.auth.currentUser!.id;
 return Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 Text('${r.pickupLabel} → ${r.destinationLabel}',style:const TextStyle(fontWeight:FontWeight.bold)),
 Text('${r.distanceKm.toStringAsFixed(1)} км • ${r.durationMin} мин • ${r.price.toStringAsFixed(2)} €'),Text(r.statusText),const SizedBox(height:8),SizedBox(height:170,child:TaxiMap(from:r.pickup,to:r.destination,route:[r.pickup,r.destination],car:currentPosition)),const SizedBox(height:8),
 if(!mine)FilledButton(onPressed:online?()=>accept(r):null,child:const Text('Принять заказ'))
 else Wrap(spacing:8,children:[
 if(r.status=='accepted')FilledButton(onPressed:()=>status(r,'arriving'),child:const Text('Еду к пассажиру')),
 if(r.status=='arriving')FilledButton(onPressed:()=>status(r,'in_progress'),child:const Text('Пассажир в машине')),
 if(r.status=='in_progress')FilledButton(onPressed:()=>status(r,'completed'),child:const Text('Завершить поездку'))
 ])
 ])));
 });
 })),
 const Padding(padding:EdgeInsets.all(8),child:Text('GPS передаётся в Supabase, пока приложение водителя открыто и включён режим «В сети».',style:TextStyle(fontSize:11,color:Colors.grey)))
 ]));
}
