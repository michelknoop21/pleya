import type { MetadataFields, MetadataOverrideField, MetadataOverridesRequest } from '../../api/types';

export const EDITABLE_FIELDS = ['title', 'year', 'summary', 'genres', 'content_rating', 'people'] as const satisfies readonly MetadataOverrideField[];
export type PersonDraft = { name: string; role: string; character: string };
export type MetadataDraft = { title: string; year: string; summary: string; genres: string; content_rating: string; people: PersonDraft[] };
export type DirtyFields = Partial<Record<MetadataOverrideField, boolean>>;

export function metadataDraft(data: MetadataFields): MetadataDraft {
  return {
    title: data.fields.title.value,
    year: data.fields.year.value === null ? '' : String(data.fields.year.value),
    summary: data.fields.summary.value ?? '',
    genres: (data.fields.genres.value ?? []).join('\n'),
    content_rating: data.fields.content_rating.value ?? '',
    people: (data.fields.people.value ?? []).map(person => ({ name: person.name, role: person.role, character: person.character ?? '' }))
  };
}

/** Alleen bewuste edits worden locks; onbekende/lege bronvelden blijven anders ongemoeid. */
export function metadataPatch(draft: MetadataDraft, dirty: DirtyFields): { body: MetadataOverridesRequest; invalid: MetadataOverrideField[]; tooLarge: boolean } {
  const body: MetadataOverridesRequest = {};
  const invalid: MetadataOverrideField[] = [];
  const length = (value: string) => [...value].length;
  if (dirty.title) { body.title = draft.title; if (!draft.title.trim() || length(draft.title) > 500) invalid.push('title'); }
  if (dirty.year) {
    body.year = draft.year.trim() === '' ? null : Number(draft.year);
    if (body.year !== null && (!/^[1-9][0-9]{0,3}$/.test(draft.year) || !Number.isInteger(body.year))) invalid.push('year');
  }
  if (dirty.summary) { body.summary = draft.summary; if (length(draft.summary) > 20000) invalid.push('summary'); }
  if (dirty.content_rating) { body.content_rating = draft.content_rating; if (length(draft.content_rating) > 100) invalid.push('content_rating'); }
  if (dirty.genres) {
    body.genres = draft.genres.split('\n').map(value => value.trim()).filter(Boolean);
    if (body.genres.length > 50 || body.genres.some(value => length(value) > 100)) invalid.push('genres');
  }
  if (dirty.people) {
    if (draft.people.length > 100 || draft.people.some(person => !person.name.trim() || length(person.name) > 200 || length(person.character) > 200 || !['actor', 'director', 'writer'].includes(person.role))) invalid.push('people');
    body.people = draft.people.map(person => ({ name: person.name, role: person.role as 'actor' | 'director' | 'writer', ...(person.character ? { character: person.character } : {}) }));
  }
  return { body, invalid, tooLarge: new TextEncoder().encode(JSON.stringify(body)).length > 8192 };
}
