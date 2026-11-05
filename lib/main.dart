import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'taxi_config.dart'; import 'taxi_auth.dart'; import 'taxi_services.dart'; import 'taxi_models.dart'; import 'taxi_map.dart';
Future<void> main() async { WidgetsFlutterBinding.ensureInitialized(); await Supabase.initialize(url:supabaseUrl,publishableKey:supabaseKey); runApp(const PassengerApp()); }
class PassengerApp extends StatelessWidget { const PassengerApp({super.key}); @override Widget build(BuildContext c)=>MaterialApp(title:'Taxi Passenger',debugShowCheckedModeBanner:false,theme:ThemeData(useMaterial3:true,colorSchemeSeed:Colors.amber),home:StreamBuilder<AuthState>(stream:sb.auth.onAuthStateChange,builder:(c,s)=>sb.auth.currentSession==null?const TaxiAuthPage(role:'passenger'):const PassengerHome())); }
class PassengerHome extends StatefulWidget { const PassengerHome({super.key}); @override State<PassengerHome> createState()=>_PassengerHomeState(); }
class _PassengerHomeState extends State<PassengerHome> {
 final from=TextEditingController(text:'Центр города'); final to=TextEditingController(text:'Аэропорт');
 final a=LatLng(56.9496,24.1052); final b=LatLng(56.9236,23.9711);
 RouteInfo? info; String? rideId; bool busy=false;
 void msg(String t){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t)));}
 Future<void> calculate() async {setState(()=>busy=true);try{info=await TaxiService.route(a,b);}catch(e){msg('$e');}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> order() async {if(info==null)await calculate();if(info==null)return;setState(()=>busy=true);try{rideId=await TaxiService.createRide(from.text,to.text,a,b,info!);msg('Заказ отправлен водителям');}catch(e){msg('Не удалось создать заказ: $e');}finally{if(mounted)setState(()=>busy=false);}}
 @override void initState(){super.initState();calculate();}
 @override void dispose(){from.dispose();to.dispose();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Такси • Пассажир'),actions:[IconButton(onPressed:()=>sb.auth.signOut(),icon:const Icon(Icons.logout))]),body:Column(children:[
 Expanded(flex:6,child:TaxiMap(from:a,to:b,route:info?.points??const [])),
 Expanded(flex:5,child:SingleChildScrollView(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
 TextField(controller:from,decoration:const InputDecoration(labelText:'Откуда',prefixIcon:Icon(Icons.trip_origin))),
 TextField(controller:to,decoration:const InputDecoration(labelText:'Куда',prefixIcon:Icon(Icons.location_on))),
 const SizedBox(height:12),
 if(info!=null)Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
 Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text('${info!.distanceKm.toStringAsFixed(1)} км'),Text('${info!.durationMin} мин'),Text('${info!.price.toStringAsFixed(2)} €',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:20))]),
 Text(info!.trafficFactor>1.2?'Повышенная загруженность (расчётная модель)':info!.trafficFactor>1?'Умеренная загруженность (расчётная модель)':'Низкая загруженность (расчётная модель)',style:Theme.of(c).textTheme.bodySmall)
 ]))),
 FilledButton.icon(onPressed:busy?null:order,icon:const Icon(Icons.local_taxi),label:Text(busy?'Подождите…':'Заказать такси')),
 if(rideId!=null)StreamBuilder<List<Map<String,dynamic>>>(stream:sb.from('rides').stream(primaryKey:['id']).eq('id',rideId!),builder:(c,s){
  if(s.hasData&&s.data!.isNotEmpty){final r=TaxiRide.fromMap(s.data!.first);return Card(child:ListTile(leading:const Icon(Icons.info),title:Text(r.statusText),subtitle:Text('Стоимость: ${r.price.toStringAsFixed(2)} €'),trailing:r.status=='requested'?TextButton(onPressed:()=>TaxiService.updateRide(r.id,{'status':'cancelled'}),child:const Text('Отменить')):null));}
  return const Padding(padding:EdgeInsets.all(8),child:Text('Ожидание подтверждения заказа…'));
 }),
 const SizedBox(height:8),const Text('OpenStreetMap. Время и цена предварительные; реальные пробки пока не подключены.',style:TextStyle(fontSize:11,color:Colors.grey))
 ])))
 ]));
}
