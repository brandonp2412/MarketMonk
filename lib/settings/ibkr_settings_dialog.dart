import 'dart:async';

import 'package:flutter/material.dart';
import 'package:market_monk/accounts/account_manager.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/l10n/app_localizations.dart';

class IbkrSettingsDialog extends StatefulWidget {
  final AccountManager accounts;
  final String account;
  final IbkrAccountConfig current;

  const IbkrSettingsDialog({
    super.key,
    required this.accounts,
    required this.account,
    required this.current,
  });

  @override
  State<IbkrSettingsDialog> createState() => _IbkrSettingsDialogState();
}

class _IbkrSettingsDialogState extends State<IbkrSettingsDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  late bool _enabled;
  var _checking = false;
  String? _status;
  var _statusOk = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.current.baseUrl);
    _tokenController = TextEditingController(text: widget.current.token);
    _enabled = widget.current.enabled;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  IbkrAccountConfig _config({required bool enabled}) => IbkrAccountConfig(
        enabled: enabled,
        baseUrl: _urlController.text.trim(),
        token: _tokenController.text.trim(),
      );

  Future<bool> _checkConnection() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      await IbkrApiClient(_config(enabled: true)).testConnection();
      if (!mounted) return false;
      setState(() {
        _checking = false;
        _statusOk = true;
        _status = context.l10n.text('Connected to IBKR');
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _checking = false;
        _statusOk = false;
        _status = error.toString().replaceFirst('Bad state: ', '');
      });
      return false;
    }
  }

  Future<void> _save() async {
    final config = _config(enabled: _enabled);
    if (_enabled && !await _checkConnection()) return;
    await widget.accounts.setIbkrConfig(widget.account, config);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          context.l10n.text('Interactive Brokers — {account}', {
            'account': widget.account,
          }),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.text('Use IBKR portfolio data')),
                  value: _enabled,
                  onChanged: _checking
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                TextField(
                  controller: _urlController,
                  enabled: !_checking,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('API URL'),
                    hintText: 'https://ibkr.example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenController,
                  enabled: !_checking,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('Bearer token'),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        _statusOk ? Icons.check_circle : Icons.error_outline,
                        color: _statusOk
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_status!)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _checking ? null : () => Navigator.pop(context),
            child: Text(context.l10n.text('Cancel')),
          ),
          TextButton(
            onPressed: _checking ? null : _checkConnection,
            child: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.l10n.text('Test')),
          ),
          FilledButton(
            onPressed: _checking ? null : _save,
            child: Text(context.l10n.text('Save')),
          ),
        ],
      );
}
