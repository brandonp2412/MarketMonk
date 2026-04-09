# Git & Version Control
- **Completion Protocol**: When a task is successful and all quality checks (tests/analyze) pass, you MUST commit the work.
- **Commit Format**: Use the [Conventional Commits](https://www.conventionalcommits.org/) standard (e.g., `feat:`, `fix:`, `chore:`).
- **Commit Message**: Write a concise title (50-72 chars) and a bulleted list in the body if the changes are complex.
- **The "Give Up" Rule**: If the task fails, or you are unable to resolve the errors after reasonable attempts:
  - DO NOT stage or commit any changes.
  - Leave the files as-is in the working directory for the user to review.
  - Inform the user exactly where you got stuck and why you are stopping.
- **Pre-Commit Check**: Never commit code that breaks `flutter analyze` or `flutter test` unless explicitly told the task is a "work in progress."