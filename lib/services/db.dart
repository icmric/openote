import 'package:sqlite3/sqlite3.dart';

void createDBInMemory() {
  final db = sqlite3.openInMemory();
  db.execute('''
    CREATE TABLE page(
      id INTEGER PRIMARY KEY,
      title TEXT,
      INTEGER
    )
  ''');
  // break it down this much or just store the whole thing as a string and later process as a JSON?
  // Would make it easier to implement but probably more difficult to search
  // Will need another table for text attributes too probably, and have m2m relation between this and that
  db.execute('''
    CREATE TABLE text_field(
      field_id INTEGER PRIMARY KEY,
      page_id INTEGER,
      position_x DOUBLE,
      position_y DOUBLE,
      width DOUBLE,
      text TEXT
    )
  ''');
  //print(db.select('SELECT * FROM users'));
  db.dispose();
}
