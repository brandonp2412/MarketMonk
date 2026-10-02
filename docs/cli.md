# Market Monk CLI

Run the project-local Dart CLI from the repository root:

\`\`\`sh
dart run tool/market_monk.dart --help
\`\`\`

It operates directly on Market Monk's SQLite databases. On Linux it discovers the same application-support directory used by the desktop app (\`~/.local/share/com.codesail.market_monk\`). Use \`--account NAME\` to select a named account, \`--db PATH\` for an explicit database, or \`--data-dir PATH\` to override discovery.

Useful commands include \`accounts list\`, \`info\`, trade CRUD (\`trades list|get|add|update|delete\`), \`holdings\`, candle-cache inspection/clearing, consistent SQLite backups, and read-only SQL via \`query\`. Destructive trade and candle-cache deletion commands require \`--yes\`. Add \`--json\` for machine-readable output.
