import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/client.dart';
import '../services/database_service.dart';

class AddClientScreen extends StatefulWidget {
  const AddClientScreen({super.key});

  @override
  State<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends State<AddClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final taxCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final advanceCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة عميل جديد'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم الشركة / العميل *', border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال اسم العميل' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: taxCtrl,
                decoration: const InputDecoration(labelText: 'الرقم الضريبي / السجل', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'العنوان / المدينة', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: advanceCtrl,
                decoration: const InputDecoration(labelText: 'رصيد المقاديم المسبق (جنيه)', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003366),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('حفظ العميل', style: TextStyle(color: Colors.white, fontSize: 16)),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final client = Client(
                      id: const Uuid().v4(),
                      name: nameCtrl.text,
                      phone: phoneCtrl.text,
                      taxNumber: taxCtrl.text,
                      address: addressCtrl.text,
                      advanceBalance: double.tryParse(advanceCtrl.text) ?? 0.0,
                    );
                    await DatabaseService.instance.insertClient(client);
                    Navigator.pop(context, true);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
