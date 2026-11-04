/// The sort pill names the sort in force, also when nothing was chosen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_sort.dart';
import 'package:pleya/screens/libraries/tabs/library_browse_tab.dart';

const _title = MediaSort(key: 'titleSort', title: 'Titel');
const _added = MediaSort(key: 'addedAt', title: 'Toegevoegd', defaultDirection: 'desc');

void main() {
  test('nothing chosen shows the first sort of the server, not a blank', () {
    expect(effectiveLibrarySort(null, const [_title, _added])?.title, 'Titel');
  });

  test('a chosen sort wins over the default', () {
    expect(effectiveLibrarySort(_added, const [_title, _added])?.title, 'Toegevoegd');
  });

  test('a server without sorts has none to show', () {
    expect(effectiveLibrarySort(null, const []), isNull);
  });
}
