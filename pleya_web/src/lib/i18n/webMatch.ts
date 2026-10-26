/**
 * Teksten van Match en overrides (scherm 36, S22.6), in een eigen bestand zodat
 * `web.ts` niet bij elk beheerscherm groeit. `web.ts` spreidt dit object; de
 * Nederlandse helft staat in `webMatch.nl.ts`.
 *
 * Alleen wat de server draagt: een kandidaat kiezen en een match afwijzen.
 * Velden overschrijven met herkomst per veld en artwork kiezen met pin komen
 * hier bewust niet in voor, want de server kent ze nog niet.
 */
export const webMatch = {
  'admin.match.title': 'Match and overrides',
  'admin.match.open': 'Review titles',
  'admin.match.refresh': 'Refresh',
  'admin.match.list.title': 'Waiting for a decision',
  'admin.match.list.truncated': 'The list shows the first {shown} of {total} titles.',
  'admin.match.col.title': 'Title',
  'admin.match.col.kind': 'Kind',
  'admin.match.col.outcome': 'Outcome',
  'admin.match.col.updated': 'Updated',
  'admin.match.kind.movie': 'Movie',
  'admin.match.kind.show': 'Series',
  'admin.match.outcome.candidates.one': '{count} candidate',
  'admin.match.outcome.candidates.other': '{count} candidates',
  'admin.match.outcome.none': 'nothing found',
  'admin.match.outcome.failed': 'fetch failed',
  'admin.match.outcome.rejected': 'rejected',
  'admin.match.hint.ambiguous': 'several hits, the server did not choose by itself',
  'admin.match.hint.unmatched': 'no sure hit on title and year',
  'admin.match.hint.failed': 'fetching from the provider failed',
  'admin.match.hint.rejected': 'rejected by an administrator, never comes back by itself',
  'admin.match.select': 'Review {title}',
  'admin.match.cand.hint': 'pick one candidate, or reject the match',
  'admin.match.cand.legend': 'Candidates from the provider',
  'admin.match.cand.detail': '{year} · number {id}',
  'admin.match.cand.detailNoYear': 'year unknown · number {id}',
  'admin.match.cand.number': 'number {id}',
  'admin.match.cand.none': 'The provider gave no candidates for this title. Enter the number of the right title yourself.',
  'admin.match.cand.pick': 'Pick this one',
  'admin.match.cand.reject': 'Reject the match',
  'admin.match.cand.rejected': 'This title is already rejected. Pick a candidate or enter a number to lift the rejection.',
  'admin.match.cand.foot': 'A pick goes before a number from a sidecar and before automatic search. Rejecting removes what the provider set; what a sidecar set stays.',
  'admin.match.manual.title': 'Enter a number yourself',
  'admin.match.manual.label': 'Number at the provider',
  'admin.match.manual.hint': 'The number of the title at the provider of this server, for example 438631.',
  'admin.match.manual.use': 'Use this number',
  'admin.match.manual.invalid': 'A title number is a positive whole number of at most ten digits.',
  'admin.match.gone': 'This title no longer needs attention. It may have been matched in the meantime.',
  'admin.match.confirm.pickTitle': 'Link this title?',
  'admin.match.confirm.pickBody': '{title} is linked to {candidate}. The server fetches the data of that title and replaces what the provider set for this item before. A rejection no longer applies. What a sidecar set stays.',
  'admin.match.confirm.pick': 'Link',
  'admin.match.confirm.rejectTitle': 'Reject the match?',
  'admin.match.confirm.rejectBody': 'For {title} the server removes what the provider set (summary, genres, age rating, cast and cached images) and never fetches this title by itself again. What a sidecar set stays. You can still pick a candidate later.',
  'admin.match.confirm.reject': 'Reject',
  'admin.match.done.pick': '{title} is linked to {candidate}. The server fetches the data in the background.',
  'admin.match.done.reject': '{title} is rejected.',
  'admin.match.err.invalid': 'That is not a valid title number. Use a positive whole number of at most ten digits, such as 438631.',
  'admin.match.err.notFound': '{name} is no longer on the server. Reload the list.',
  'admin.match.side.counts': 'By outcome',
  'admin.match.side.title': 'What the server carries here',
  'admin.match.side.body': 'Picking a candidate and rejecting a match. Overriding single fields with their source, and picking artwork with a pin, are not on the server yet, so they are not here.'
} as const;
