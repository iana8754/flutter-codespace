import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'taxi_config.dart'; import 'taxi_auth.dart'; import 'taxi_services.dart'; import 'taxi_models.dart'; import 'taxi_map.dart'; import 'taxi_gps.dart';

Future<void> main() async { WidgetsFlutterBinding.ensureInitialized(); await Supabase.initialize(url:supabaseUrl,publishableKey:supabaseKey); runApp(const PassengerApp()); }
class PassengerApp extends StatelessWidget { const PassengerApp({super.key}); @override Widget build(BuildContext c)=>MaterialApp(title:'Taxi Passenger',debugShowCheckedModeBanner:false,theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.amber),home:StreamBuilder<AuthState>(stream:sb.auth.onAuthStateChange,builder:(c,s)=>sb.auth.currentSession==null?const TaxiAuthPage(role:'passenger'):const PassengerHome())); }
class PassengerHome extends StatefulWidget { const PassengerHome({super.key}); @override State<PassengerHome> createState()=>_PassengerHomeState(); }
class _PassengerHomeState extends State<PassengerHome> {
 final from=TextEditingController(text:'Моё местоположение'); final to=TextEditingController();
 final fallback=LatLng(56.9496,24.1052), destination=LatLng(56.9236,23.9711);
 LatLng? pickupPosition; RouteInfo? info; String? rideId; bool busy=false, locating=true;
 LatLng get pickup => pickupPosition ?? fallback;
 void msg(String t){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t)));}
 Future<void> locate() async {try {final p=await TaxiGps.currentPosition(); if(mounted)setState(()=>pickupPosition=p);} catch(e){msg('Не удалось определить GPS: $e');} finally {if(mounted)setState(()=>locating=false);}}
 Future<void> calculate() async {setState(()=>busy=true);try{info=await TaxiService.route(pickup,destination);}catch(e){msg('$e');}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> order() async {if(info==null)await calculate();if(info==null)return;setState(()=>busy=true);try{rideId=await TaxiService.createRide(from.text,to.text.isEmpty?'Указанная точка':to.text,pickup,destination,info!);msg('Заказ отправлен водителям');}catch(e){msg('Не удалось создать заказ: $e');}finally{if(mounted)setState(()=>busy=false);}}
 @override void initState(){super.initState();locate();}
 @override void dispose(){from.dispose();to.dispose();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Такси • Пассажир'),actions:[IconButton(onPressed:locate,tooltip:'Обновить GPS',icon:const Icon(Icons.my_location)),IconButton(onPressed:()=>sb.auth.signOut(),icon:const Icon(Icons.logout))]),body:Column(children:[
 Expanded(flex:6,child:StreamBuilder<List<Map<String,dynamic>>>(stream:rideId==null?null:sb.from('rides').stream(primaryKey:['id']).eq('id',rideId!),builder:(c,rideSnap){
  String? driverId;
  if(rideSnap.hasData&&rideSnap.data!.isNotEmpty){driverId=rideSnap.data!.first['driver_id'] as String?;}
  if(driverId==null)return TaxiMap(from:pickup,to:destination,route:info?.points??const []);
  return StreamBuilder<List<Map<String,dynamic>>>(stream:sb.from('driver_locations').stream(primaryKey:['driver_id']).eq('driver_id',driverId!),builder:(c,loc){
   LatLng? car;
   if(loc.hasData&&loc.data!.isNotEmpty){final row=loc.data!.first;car=LatLng((row['lat'] as num).toDouble(),(row['lng'] as num).toDouble());}
   return TaxiMap(from:pickup,to:destination,route:info?.points??const [],car:car);
  });
 })),
 Expanded(flex:5,child:SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
 TextField(controller:from,decoration:InputDecoration(labelText:locating?'Определяем GPS…':'Точка подачи (текущие координаты)',prefixIcon:const Icon(Icons.my_location))),
 TextField(controller:to,decoration:const InputDecoration(labelText:'Куда (пока тестовая точка)',prefixIcon:Icon(Icons.location_on))),
 const SizedBox(height:12),
 if(info!=null)Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
 Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${info!.distanceKm.toStringAsFixed(1)} км'),Text('${info!.durationMin} мин'),Text('${info!.price.toStringAsFixed(2)} €',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:20))]),
 Text('Маршрут и время предварительные; реальные пробки пока не подключены.',style:Theme.of(c).textTheme.bodySmall)
 ]))),
 FilledButton.icon(onPressed:busy||locating?null:order,icon:const Icon(Icons.local_taxi),label:Text(busy?'Подождите…':'Заказать такси')),
 if(rideId!=null)StreamBuilder<List<Map<String,dynamic>>>(stream:sb.from('rides').stream(primaryKey:['id']).eq('id',rideId!),builder:(c,s){
  if(s.hasData&&s.data!.isNotEmpty){final r=TaxiRide.fromMap(s.data!.first);
   return Column(children:[
    Card(child:ListTile(leading:const Icon(Icons.info),title:Text(r.statusText),subtitle:Text('Стоимость: ${r.price.toStringAsFixed(2)} €'),trailing:r.status=='requested'?TextButton(onPressed:()=>TaxiService.updateRide(r.id,{'status':'cancelled'}),child:const Text('Отменить')):null)),
    if(r.driverId!=null&&['accepted','arriving','in_progress'].contains(r.status))
      const ListTile(leading:Icon(Icons.local_taxi),title:Text('Местоположение водителя отображается на карте выше'))
   ]);
  }
  return const Padding(padding:EdgeInsets.all(8),child:Text('Ожидание подтверждения заказа…'));
 }),
 const SizedBox(height:8),const Text('GPS пассажира используется для точки подачи. Адресный поиск и навигация будут подключены через 2ГИС.',style:TextStyle(fontSize:11,color:Colors.grey))
 ])))
 ]));
}