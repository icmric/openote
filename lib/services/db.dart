import 'dart:developer';

import 'package:mosapad/models/canvas_page_data.dart';
import 'package:sqlite3/sqlite3.dart';

void initialiseDB({required String path}) {
  final db = sqlite3.open(path);
  db.execute('''
   DROP TABLE IF EXISTS page;
   DROP TABLE IF EXISTS text_field;
  ''');
  db.execute('''
    CREATE TABLE page(
      "id" char(36) default (lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6)))) PRIMARY KEY, 
      title TEXT,
      width DOUBLE,
      height DOUBLE
    )
  ''');
  db.execute('''
    CREATE TABLE text_field(
      field_id char(36) default (lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) || '-' || substr('89ab',abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6)))) PRIMARY KEY,
      page_id char(36) NOT NULL,
      position_x DOUBLE,
      position_y DOUBLE,
      width DOUBLE,
      content TEXT
      --CONSTRAINT fk_page
      --  FOREIGN KEY (page_id)
      --  REFERENCES page(id)
    )
  ''');
  db.dispose();
}

void wipeDB() {
  final db = sqlite3.open(r'C:\src\temp\example.sql');
  db.execute('''
   DROP TABLE IF EXISTS page;
   DROP TABLE IF EXISTS text_field;
  ''');
  initialiseDB(path: r'C:\src\temp\example.sql');
  db.dispose();
}

void saveContentToDB({required CanvasPageData data, required String title}) {
  final db = sqlite3.open(r'C:\src\temp\example.sql');
  
  try {
    // Begin transaction to ensure atomicity
    db.execute('BEGIN TRANSACTION;');

    // Insert the page and get its ID
    db.prepare('''
      INSERT INTO page (title, width, height) 
      VALUES (?, ?, ?);
    ''').execute([title, data.canvasSize.height, data.canvasSize.width]);

    // Get the ID of the page we just inserted
    final ResultSet pageResult = db.select('SELECT id FROM page WHERE title = ? ORDER BY rowid DESC LIMIT 1;', [title]);
    final String pageId = pageResult.first['id'] as String;

    // Insert text fields with the page ID
    for (var textField in data.textFields) {
      final text = textField.toJson();
      db.prepare('''
        INSERT INTO text_field (page_id, position_x, position_y, width, content) 
        VALUES (?, ?, ?, ?, ?);
      ''').execute([
        pageId,
        textField.position.dx,
        textField.position.dy,
        textField.width,
        text['document'].toString()
      ]);
    }

    print('Page saved with ID: $pageId');
    print(db.select('SELECT * FROM page'));
    print(db.select('SELECT * FROM text_field'));

  } catch (e) {
    // If anything goes wrong, roll back the transaction
    db.execute('ROLLBACK;');
    print('Error saving to database: $e');
    rethrow;
  } finally {
    db.dispose();
  }
}

void loadContentFromDB({required String title}) {
  final db = sqlite3.open(r'C:\src\temp\example.sql');
  try {
    final page = db.select('SELECT * FROM page WHERE title = ?', [title]);
    if (page.isEmpty) {
      print('No page found with title: $title');
      return;
    }
    final String pageId = page.first['id'] as String;
    final textFields = db.select('SELECT * FROM text_field WHERE page_id = ?', [pageId]);
    print(page);
    print(textFields);
  } finally {
    db.dispose();
  }
}
