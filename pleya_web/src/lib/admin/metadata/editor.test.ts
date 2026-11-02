import { describe, expect, it } from 'vitest';
import { metadataDraft, metadataPatch } from './editor';
import { metadataFixture } from './metadataFake';

describe('typed metadata edits', () => {
  it('does not lock untouched fields and preserves an explicit empty year', () => {
    const draft = metadataDraft(metadataFixture());
    expect(metadataPatch(draft, {}).body).toEqual({});
    draft.summary = ''; draft.year = '';
    expect(metadataPatch(draft, { summary: true, year: true }).body).toEqual({ summary: '', year: null });
  });
  it('writes genres and people as typed arrays, never JSON editor strings', () => {
    const draft = metadataDraft(metadataFixture()); draft.genres = 'Drama\nAdventure\n'; draft.people = [{ name: 'A', role: 'actor', character: 'B' }];
    expect(metadataPatch(draft, { genres: true, people: true }).body).toEqual({ genres: ['Drama', 'Adventure'], people: [{ name: 'A', role: 'actor', character: 'B' }] });
  });
  it.each(['', ' ', 'a'.repeat(501)])('rejects invalid titles', value => {
    const draft = metadataDraft(metadataFixture()); draft.title = value;
    expect(metadataPatch(draft, { title: true }).invalid).toContain('title');
  });
  it.each(['0', '-1', '10000', '2020.1', 'year', '0201'])('rejects invalid years', value => {
    const draft = metadataDraft(metadataFixture()); draft.year = value;
    expect(metadataPatch(draft, { year: true }).invalid).toContain('year');
  });
  it('checks people roles and names and the full body byte limit', () => {
    const draft = metadataDraft(metadataFixture()); draft.people = [{ name: '', role: 'producer', character: '' }];
    expect(metadataPatch(draft, { people: true }).invalid).toContain('people');
    draft.summary = 'é'.repeat(5000);
    expect(metadataPatch(draft, { summary: true }).tooLarge).toBe(true);
  });
});

it('keeps unknown source people intact when an unrelated field is edited', () => {
  const fields = metadataFixture(); fields.fields.people.value = [{name:'Future role',role:'future' as 'actor'}];
  const draft = metadataDraft(fields); draft.summary = 'Only summary';
  expect(metadataPatch(draft,{summary:true})).toMatchObject({body:{summary:'Only summary'},invalid:[]});
});
