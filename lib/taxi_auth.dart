import 'package:flutter/material.dart';
import 'taxi_config.dart';
import 'taxi_services.dart';
class TaxiAuthPage extends StatefulWidget {
 final String role; const TaxiAuthPage({super.key,required this.role});
 @override State<TaxiAuthPage> createState()=>_TaxiAuthPageState();
}
class _TaxiAuthPageState extends State<TaxiAuthPage> {
 final email=TextEditingController(), pass=TextEditingController(), name=TextEditingController(), phone=TextEditingController();
 bool register=true,busy=false;
 Future<void> submit() async {
  setState(()=>busy=true);
  try {
   if(register) {
    final r=await sb.auth.signUp(email:email.text.trim(),password:pass.text);
    if(r.session==null) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Подтвердите email, затем войдите.'))); return; }
    await TaxiService.saveProfile(widget.role,name.text.trim(),phone.text.trim());
   } else {
    await sb.auth.signInWithPassword(email:email.text.trim(),password:pass.text);
    final p=await sb.from('profiles').select('role').eq('id',sb.auth.currentUser!.id).maybeSingle();
    if(p==null) { await TaxiService.saveProfile(widget.role,name.text.trim().isEmpty?'Пользователь':name.text.trim(),''); }
    else if(p['role']!=widget.role) throw Exception('Аккаунт зарегистрирован в другом режиме.');
   }
  } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); }
  finally { if(mounted)setState(()=>busy=false); }
 }
 @override void dispose(){email.dispose();pass.dispose();name.dispose();phone.dispose();super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:440),child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
 const Icon(Icons.local_taxi,size:72),const SizedBox(height:12),Text(widget.role=='driver'?'Такси • Водитель':'Такси • Пассажир',style:const TextStyle(fontSize:28,fontWeight:FontWeight.bold)),
 if(register)...[TextField(controller:name,decoration:const InputDecoration(labelText:'Имя')),TextField(controller:phone,decoration:const InputDecoration(labelText:'Телефон'))],
 TextField(controller:email,decoration:const InputDecoration(labelText:'Email')),TextField(controller:pass,obscureText:true,decoration:const InputDecoration(labelText:'Пароль')),
 const SizedBox(height:16),FilledButton(onPressed:busy?null:submit,child:Text(register?'Зарегистрироваться':'Войти')),
 TextButton(onPressed:()=>setState(()=>register=!register),child:Text(register?'Уже есть аккаунт? Войти':'Создать аккаунт'))
 ])))));
}
