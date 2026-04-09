---
paths:
  - "lib/database/**"
  - "**/tables.dart"
  - "**/database.dart"
---
# Drift Database Rules
- ALWAYS read the Drift documentation at https://drift.simonbinder.eu/docs/ before modifying schemas or queries.
- **Migration Protocol**: After any change to a table or database file:
  1. Increment the `schemaVersion` in the database class.
  2. dart run build_runner build -d
  3. dart run drift_dev make-migrations