part of '../portfolio_page.dart';

extension _PortfolioCsvExport on PortfolioPageState {
  Future<void> _exportCsv(
    BuildContext context,
    List<Position> positions,
  ) async {
    final accountName = context.read<AccountManager>().activeAccount;
    final csv = _portfolioCsv(accountName, positions);
    final path = await FilePicker.saveFile(
      fileName: csv.fileName,
      bytes: csv.bytes,
    );
    if (path == null) return;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await File(path.toFilePath()).writeAsBytes(csv.bytes);
    }
    talker.info('Exported portfolio CSV with ${positions.length} positions');
  }

  Future<void> _shareCsv(BuildContext context, List<Position> positions) async {
    if (!_supportsFileSharing) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failureMessage = context.l10n.text('Couldn’t share CSV');
    final shareTitle = context.l10n.text('Share CSV');
    try {
      final accountName = context.read<AccountManager>().activeAccount;
      final csv = _portfolioCsv(accountName, positions);
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${csv.fileName}');
      if (widget._writeShareFile case final writer?) {
        await writer(file, csv.bytes);
      } else {
        await file.writeAsBytes(csv.bytes, flush: true);
      }
      await (widget._shareFile ?? SharePlus.instance.share)(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Portfolio Positions',
          title: shareTitle,
        ),
      );
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Failed to share portfolio CSV');
      if (messenger?.mounted ?? false) {
        messenger!.showSnackBar(SnackBar(content: Text(failureMessage)));
      }
    }
  }
}
