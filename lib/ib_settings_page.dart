import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/ib_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/utils.dart';

/// Settings page for Interactive Brokers Client Portal API integration.
///
/// Requires IB Gateway or Trader Workstation running with the Client Portal
/// API enabled. The gateway must be reachable from this device on the network.
class IbSettingsPage extends StatefulWidget {
  const IbSettingsPage({super.key});

  @override
  State<IbSettingsPage> createState() => _IbSettingsPageState();
}

class _IbSettingsPageState extends State<IbSettingsPage> {
  final _hostController = TextEditingController(text: 'localhost');
  final _portController = TextEditingController(text: '5000');
  bool _checking = false;
  bool? _connected;
  List<String> _ibAccounts = [];
  String? _selectedAccount;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  IbApi _buildApi() => IbApi(
        host: _hostController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 5000,
      );

  Future<void> _connect() async {
    setState(() {
      _checking = true;
      _connected = null;
      _ibAccounts = [];
      _selectedAccount = null;
    });
    final api = _buildApi();
    try {
      final authed = await api.checkAuth();
      if (!authed) await api.reauthenticate();
      final accounts = await api.getAccounts();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _ibAccounts = accounts;
        _selectedAccount = accounts.isNotEmpty ? accounts.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _connected = false);
      toast(context, 'Connection failed: $e');
    } finally {
      api.dispose();
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _importPositions() async {
    if (_selectedAccount == null) return;
    final api = _buildApi();
    setState(() => _checking = true);
    try {
      final positions = await api.getPositions(_selectedAccount!);
      if (!mounted) return;
      int imported = 0;
      for (final pos in positions) {
        if (pos.symbol.isEmpty || pos.shares <= 0) continue;
        await db.into(db.trades).insertOnConflictUpdate(
              TradesCompanion.insert(
                symbol: pos.symbol,
                name: pos.symbol,
                quantity: pos.shares,
                price: pos.avgCost > 0 ? pos.avgCost : pos.marketPrice,
                tradeType: 'open',
                tradeDate: DateTime.now(),
                realizedPL: const Value(0.0),
                commission: const Value(0.0),
              ),
            );
        imported++;
      }
      if (!mounted) return;
      toast(context, 'Imported $imported position(s) from IB');
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Import failed: $e');
    } finally {
      api.dispose();
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _importTrades() async {
    final api = _buildApi();
    setState(() => _checking = true);
    try {
      final trades = await api.getTrades();
      if (!mounted) return;
      int imported = 0;
      for (final t in trades) {
        if (t.symbol.isEmpty) continue;
        final isBuy = t.side == 'B';
        await db.into(db.trades).insertOnConflictUpdate(
              TradesCompanion.insert(
                symbol: t.symbol,
                name: t.symbol,
                quantity: isBuy ? t.size : -t.size,
                price: t.price,
                tradeType: isBuy ? 'open' : 'close',
                tradeDate: t.tradeTime,
                realizedPL: const Value(0.0),
                commission: const Value(0.0),
              ),
            );
        imported++;
      }
      if (!mounted) return;
      toast(context, 'Imported $imported trade(s) from IB');
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Import failed: $e');
    } finally {
      api.dispose();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Interactive Brokers')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Connection',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Run IB Gateway or Trader Workstation with the Client Portal API '
            'enabled, then enter its address below.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Gateway host',
                    hintText: 'localhost',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '5000',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _checking ? null : _connect,
            icon: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _connected == true ? Icons.check_circle : Icons.link,
                  ),
            label: Text(
              _checking
                  ? 'Connecting…'
                  : _connected == true
                      ? 'Connected'
                      : 'Connect',
            ),
          ),
          if (_connected == true && _ibAccounts.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Import',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'IB Account',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
              ),
              child: DropdownButton<String>(
                value: _selectedAccount,
                isExpanded: true,
                underline: const SizedBox(),
                items: _ibAccounts
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedAccount = v),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Import portfolio positions'),
              subtitle: const Text(
                'Creates a buy trade for each open position',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _checking ? null : _importPositions,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long),
              title: const Text('Import recent trades'),
              subtitle: const Text(
                'Imports today\'s executed orders',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _checking ? null : _importTrades,
            ),
          ],
          if (_connected == false) ...[
            const SizedBox(height: 12),
            Text(
              'Could not connect. Make sure IB Gateway is running and the '
              'Client Portal API is enabled on the correct port.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
