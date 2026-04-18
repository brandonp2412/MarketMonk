import 'package:flutter/material.dart';
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
      appBar: AppBar(title: const Text('Accounts')),
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
            subtitle: isActive ? const Text('Active') : null,
            onTap: isActive
                ? null
                : () async {
                    await context.read<AccountManager>().switchAccount(name);
                    if (context.mounted) Navigator.pop(context);
                  },
            trailing: name != 'Default'
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete account',
                    onPressed: () => _confirmDelete(context, accounts, name),
                  )
                : null,
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addAccount(context, accounts),
        label: const Text('New account'),
        icon: const Icon(Icons.add),
        tooltip: 'Add account',
      ),
    );
  }

  Future<void> _addAccount(
    BuildContext context,
    AccountManager accounts,
  ) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New account'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Account name',
            hintText: 'e.g. Retirement, ISA, Trading',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => Navigator.pop(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.pop(ctx);
              if (name.isNotEmpty && !accounts.accounts.contains(name)) {
                accounts.addAccount(name);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AccountManager accounts,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'All trades and data for this account will be permanently deleted. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
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
