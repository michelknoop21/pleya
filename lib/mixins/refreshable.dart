mixin Refreshable {
  void refresh();
}

mixin FullRefreshable {
  void fullRefresh();
}

mixin FocusableTab {
  void focusActiveTabIfReady();
}

mixin SearchInputFocusable {
  void focusSearchInput();
  void setSearchQuery(String query);

  /// Set the query *and* run it immediately. Voice search and the Android
  /// Assistant hand over a finished phrase — waiting for a debounce that only
  /// fires on typed input would just leave it sitting in the field.
  void submitSearchQuery(String query);
}

mixin LibraryLoadable {
  void loadLibraryByKey(String libraryGlobalKey);
}
