// Gegenereerd uit lib/i18n/en.i18n.json, de i18n-bron van de app.
// Niet met de hand wijzigen; draai: bun run scripts/gen-i18n.ts
export const shared = {
  "states.emptyTitle": "Nothing here yet",
  "states.errorTitle": "Something went wrong",
  "states.offlineTitle": "You're offline",
  "states.offlineMessage": "Reconnect to load this content.",
  "common.retry": "Retry",
  "common.cancel": "Cancel",
  "common.close": "Close",
  "common.clear": "Clear",
  "common.search": "Search",
  "common.home": "Home",
  "common.settings": "Settings",
  "common.back": "Back",
  "common.error": "Error",
  "common.unknown": "Unknown",
  "common.logout": "Logout",
  "common.viewAll": "View All",
  "navigation.libraries": "Libraries",
  "search.tryDifferentTerm": "Try a different search term",
  "search.searchYourMedia": "Search your media",
  "search.enterTitleActorOrKeyword": "Enter a title, actor, or keyword",
  "search.filters.all": "All",
  "search.filters.movies": "Movies",
  "search.filters.shows": "Shows",
  "search.filters.episodes": "Episodes",
  "auth.signIn": "Sign in",
  "settings.theme": "Theme",
  "settings.language": "Language"
} as const;

export type SharedKey = keyof typeof shared;
