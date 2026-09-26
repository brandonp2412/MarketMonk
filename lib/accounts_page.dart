import 'package:flutter/material.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/main.dart';
import 'package:provider/provider.dart';

/// Lets the user create, switch between, and delete named portfolio accounts.
/// Each account is backed by a separate SQLite file — switching is instant
/// with no per-query overhead.
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountManager>();

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('Accounts'))),
      body: ListView.builder(
        itemCount: accounts.accounts.length,
        itemBuilder: (context, i) {
          final name = accounts.accounts[i];
          final isActive = name == accounts.activeAccount;
          return ListTile(
            leading: isActive
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : const Icon(Icons.account_circle_outlined),
            title: Text(name),
            subtitle: isActive ? Text(context.l10n.text('Active')) : null,
            onTap: isActive
                ? null
                : () async {
                    await context.read<AccountManager>().switchAccount(name);
                    if (context.mounted) Navigator.pop(context);
                  },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name != 'Default') ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: context.l10n.text('Rename account'),
                    onPressed: () => _renameAccount(context, accounts, name),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: context.l10n.text('Delete account'),
                    onPressed: () => _confirmDelete(context, accounts, name),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addAccount(context, accounts),
        label: Text(context.l10n.text('New account')),
        icon: const Icon(Icons.add),
        tooltip: context.l10n.text('Add account'),
      ),
    );
  }

  Future<void> _renameAccount(
    BuildContext context,
    AccountManager accounts,
    String name,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameAccountDialog(currentName: name),
    );
    if (newName != null &&
        newName.isNotEmpty &&
        newName != name &&
        context.mounted) {
      await context.read<AccountManager>().renameAccount(name, newName);
    }
  }

  Future<void> _addAccount(
    BuildContext context,
    AccountManager accounts,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddAccountDialog(),
    );
    if (name != null && name.isNotEmpty && !accounts.accounts.contains(name)) {
      accounts.addAccount(name);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AccountManager accounts,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.text('Delete "{name}"?', {'name': name})),
        content: Text(
          context.l10n.text(
            'All trades and data for this account will be permanently deleted. This cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.text('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.l10n.text('Delete'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AccountManager>().deleteAccount(name);
    }
  }
}

class _RenameAccountDialog extends StatefulWidget {
  const _RenameAccountDialog({required this.currentName});

  final String currentName;

  @override
  State<_RenameAccountDialog> createState() => _RenameAccountDialogState();
}

class _RenameAccountDialogState extends State<_RenameAccountDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.text('Rename account')),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: context.l10n.text('Account name'),
        ),
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(context.l10n.text('Rename')),
        ),
      ],
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog();

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.text('New account')),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: context.l10n.text('Account name'),
          hintText: context.l10n.text('e.g. Retirement, ISA, Trading'),
        ),
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(context.l10n.text('Add')),
        ),
      ],
    );
  }
}
