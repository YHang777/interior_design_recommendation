import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';

class OrderManagementScreen extends ConsumerStatefulWidget {
  const OrderManagementScreen({super.key});

  @override
  ConsumerState<OrderManagementScreen> createState() =>
      _OrderManagementScreenState();
}

class _OrderManagementScreenState extends ConsumerState<OrderManagementScreen> {
  final _orders = [
    _Order('2024-0012', 'Modern Sofa, Coffee Table', 2450, 'Shipped', '2024-06-15'),
    _Order('2024-0011', 'Oak Flooring', 850, 'Pending', '2024-06-14'),
    _Order('2024-0010', 'Dining Set, 4 Chairs, Rug', 4200, 'Delivered', '2024-06-10'),
    _Order('2024-0009', 'Floor Lamp x2', 700, 'Cancelled', '2024-06-05'),
  ];

  Color _statusColor(String status) => switch (status) {
        'Shipped' => Colors.blue,
        'Pending' => Colors.orange,
        'Delivered' => Colors.green,
        'Cancelled' => Colors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _orders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text('No orders yet',
                      style: GoogleFonts.poppins(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 16),
              itemCount: _orders.length,
              itemBuilder: (_, i) {
                final o = _orders[i];
                final color = _statusColor(o.status);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt, color: Colors.brown, size: 32),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order #${o.id}',
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(o.items,
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: Colors.brown.shade600)),
                            const SizedBox(height: 4),
                            Text('RM ${o.total} • ${o.date}',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(o.status,
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: color)),
                          ),
                          const SizedBox(height: 8),
                          if (o.status == 'Pending')
                            GestureDetector(
                              onTap: () => _updateStatus(i),
                              child: const Icon(Icons.edit, size: 18, color: Colors.brown),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _updateStatus(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Status'),
        content: DropdownButtonFormField<String>(
          value: _orders[index].status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: ['Pending', 'Shipped', 'Delivered', 'Cancelled']
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => _orders[index] = _Order(
                    _orders[index].id,
                    _orders[index].items,
                    _orders[index].total,
                    v,
                    _orders[index].date,
                  ));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Order #${_orders[index].id} updated to $v (mocked)')),
              );
            }
          },
        ),
      ),
    );
  }
}

class _Order {
  final String id, items, status, date;
  final int total;
  const _Order(this.id, this.items, this.total, this.status, this.date);
}
