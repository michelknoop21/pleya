import type { Art } from './BpPoster.svelte';

// The scripted demo: questions people actually ask about a film library, each with the answer
// drawn as the app draws it. Three questions are example questions from the app's strings in
// lib/i18n/en.i18n.json (tonight, most watched, watching now); the rest and every
// answer are written for this page. Labels inside the answers ("In your library", "Requestable",
// "Watch stats", "Scan started", ...) are the app's strings.
export type Match = { art: Art; title: string; year: number; kind?: string; status: string; tone?: 'ok' | 'plain'; facts?: string; plot: string };
export type Row = { title: string; sub?: string; pill?: string; tone?: 'ok' | 'requested' | 'plain' };
export type Ask = {
  id: string;
  q: string;
  /** what the working beat says he is doing */
  step: string;
  /** what Big P answers, as the heading of his balloon */
  line: string;
  body?: string;
  matches?: Match[];
  /** a card of rows: watch stats, or what Pleya carried out */
  rows?: { label: string; note?: string; items: Row[] };
  tag?: string;
};

const inLibrary = { status: 'In your library · Home server', tone: 'ok' } as const;

export const asks: Ask[] = [
  {
    id: 'hanks',
    q: 'What was that film again, with Tom Hanks on death row?',
    step: 'Finding the title',
    line: 'That is The Green Mile.',
    matches: [{ art: 'greenmile', title: 'The Green Mile', year: 1999, facts: '3h 9m · Drama', plot: 'A death row guard meets a prisoner who seems to have a gift for healing.', ...inLibrary }],
  },
  {
    id: 'tonight',
    q: 'What can I watch tonight?',
    step: 'Checking what you watched',
    line: 'Three you have not seen yet.',
    matches: [
      { art: 'dune', title: 'Dune: Part Two', year: 2024, facts: '2h 46m · Sci-fi', plot: 'Paul Atreides joins the Fremen and has to choose between the people he loves and the war that is coming.', ...inLibrary },
      { art: 'knives', title: 'Knives Out', year: 2019, facts: '2h 10m · Mystery', plot: 'A crime writer dies after his birthday party and a private detective suspects the whole family.', ...inLibrary },
      { art: 'conclave', title: 'Conclave', year: 2024, facts: '2h 0m · Thriller', plot: 'A cardinal has to run the election of a new pope and finds out what the candidates are hiding.', ...inLibrary },
    ],
  },
  {
    id: 'family',
    q: 'Something for the whole family, under two hours?',
    step: 'Searching the catalog',
    line: 'Two that fit, both under two hours.',
    matches: [
      { art: 'paddington', title: 'Paddington 2', year: 2017, facts: '1h 43m · Comedy · Family', plot: 'A bear in London saves up for a pop-up book, which is stolen before he can buy it.', ...inLibrary },
      { art: 'robot', title: 'The Wild Robot', year: 2024, facts: '1h 42m · Animation · Family', plot: 'A robot washes up on an island without people and ends up raising a gosling.', ...inLibrary },
    ],
  },
  {
    id: 'mars',
    q: 'That film about an astronaut stranded on Mars?',
    step: 'Finding the title',
    line: 'That sounds like The Martian.',
    body: 'You never said the title. Big P matched what happens in the film.',
    matches: [
      { art: 'martian', title: 'The Martian', year: 2015, facts: '2h 24m · Sci-fi', plot: 'Astronaut Mark Watney is left behind on Mars and has to survive until help arrives.', ...inLibrary },
      { art: 'mission', title: 'Mission to Mars', year: 2000, kind: 'Movie · possibly', status: 'Requestable', plot: 'A rescue mission looks for the first crew that vanished on Mars.' },
    ],
  },
  {
    id: 'have',
    q: 'Do I have Sinners?',
    step: 'Searching the catalog',
    line: 'Not yet. I can request it for you.',
    matches: [{ art: 'sinners', title: 'Sinners', year: 2025, facts: '2h 17m · Horror', plot: 'Twin brothers come home to open a juke joint and find that something else has arrived first.', status: 'Requestable' }],
  },
  {
    id: 'story',
    q: 'Who is Anna again? No spoilers.',
    step: 'Checking what you watched',
    line: 'Anna is the harbour pilot.',
    body: 'She found the logbook in episode 1 and does not trust the captain yet. That is all I can say at S1 E3 of TIDE, where you are.',
    tag: 'Stops at what you have watched',
  },
  {
    id: 'most',
    q: 'Who watched the most this week?',
    step: 'Fetching watch statistics',
    line: 'Sam watched the most this week.',
    rows: {
      label: 'Watch stats · Home server · Last 7 days',
      note: '27 plays',
      items: [
        { title: 'Sam', pill: '14×', tone: 'ok' },
        { title: 'Noor', pill: '9×' },
        { title: 'Daan', pill: '4×' },
      ],
    },
  },
  {
    id: 'now',
    q: 'Who is watching right now?',
    step: 'Fetching watch statistics',
    line: 'Two people are watching.',
    rows: {
      label: 'Watch stats · Home server · Right now',
      items: [
        { title: 'Noor', sub: 'TIDE · S1 E4' },
        { title: 'Daan', sub: 'Paddington 2' },
      ],
    },
  },
  {
    id: 'scan',
    q: 'I just added new films. Scan my movie library.',
    step: 'Scanning library',
    line: 'Scanning Movies now.',
    rows: { label: 'Carried out by Pleya', items: [{ title: 'Scan started', sub: 'Movies · Home server', pill: 'Scan running', tone: 'ok' }] },
  },
];

/** The three questions the greeting offers, as the app does when Big P is called. */
export const starters = ['hanks', 'tonight', 'most'].map((id) => asks.find((a) => a.id === id)!);

/** Follow-ups under an answer: the next three questions in the list. */
export const followUps = (a: Ask): Ask[] => [1, 2, 3].map((n) => asks[(indexOf(a) + n) % asks.length]);

/** Position by id: the component holds a reactive copy, which is not the same object. */
export const indexOf = (a: Ask) => asks.findIndex((x) => x.id === a.id);
