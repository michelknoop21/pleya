import type { Art } from './BpPoster.svelte';

// The scripted demo. Seven questions are the app's own examples (assistant.idle.examples,
// mobile.examples and followUp in lib/i18n/en.i18n.json); the Mars and Anna questions and
// every answer are written for this page. Labels inside the answers ("Watch stats",
// "Scan started", "Requestable", ...) are the app's strings.
export type Match = { art: Art; title: string; year: number; kind?: string; status: string; tone?: 'ok' | 'requested' | 'plain'; facts?: string; plot: string };
export type Row = { title: string; sub?: string; pill?: string; tone?: 'ok' | 'requested' | 'plain' };
export type Ask = {
  id: string;
  q: string;
  /** what the working beat says he is doing */
  step: string;
  /** what Big P says, in the balloon and as the heading of the answer */
  line: string;
  body?: string;
  matches?: Match[];
  /** a card of rows: watch stats, a comparison, or what Pleya carried out */
  rows?: { label: string; note?: string; items: Row[] };
  tag?: string;
};

const inLibrary = { status: 'In your library · Home server', tone: 'ok' } as const;

export const groups: { name: string; asks: Ask[] }[] = [
  {
    name: 'Find something',
    asks: [
      {
        id: 'tonight',
        q: 'What can I watch tonight?',
        step: 'Checking what you watched',
        line: 'Three you have not seen yet.',
        matches: [
          { art: 'dune', title: 'Dune: Part Two', year: 2024, facts: '2h 46m · Sci-fi · Adventure', plot: 'Paul Atreides joins the Fremen and has to choose between the people he loves and the war that is coming.', ...inLibrary },
          { art: 'knives', title: 'Knives Out', year: 2019, facts: '2h 10m · Mystery · Comedy', plot: 'A crime writer dies after his birthday party and a private detective suspects the whole family.', ...inLibrary },
          { art: 'paddington', title: 'Paddington 2', year: 2017, facts: '1h 43m · Comedy · Family', plot: 'A bear in London saves up for a pop-up book, which is stolen before he can buy it.', ...inLibrary },
        ],
      },
      {
        id: 'plot',
        q: 'That movie where an astronaut is stranded on Mars and grows potatoes',
        step: 'Finding the title',
        line: 'That sounds like The Martian.',
        body: 'You never said the title. Big P matched what happens in the film.',
        matches: [
          { art: 'martian', title: 'The Martian', year: 2015, facts: '2h 24m · Sci-fi · Adventure', plot: 'Astronaut Mark Watney is left behind on Mars and has to survive until help arrives.', ...inLibrary },
          { art: 'mission', title: 'Mission to Mars', year: 2000, kind: 'Movie · possibly', status: 'Already requested', tone: 'requested', plot: 'A rescue mission looks for the first crew that vanished on Mars.' },
          { art: 'redplanet', title: 'Red Planet', year: 2000, kind: 'Movie · possibly', status: 'Requestable', plot: 'A crew is stranded on Mars and has to find its own way back.' },
        ],
      },
      {
        id: 'story',
        q: 'Who is Anna? No spoilers.',
        step: 'Checking what you watched',
        line: 'Anna is the harbour pilot.',
        body: 'She found the logbook in episode 1 and does not trust the captain yet. That is all I can say at S1 E3 of TIDE, where you are.',
        tag: 'Stops at what you have watched',
      },
      {
        id: 'popular',
        q: "Which popular new movies don't I have yet?",
        step: 'Checking what is trending',
        line: 'Three that are popular and not in your library.',
        matches: [
          { art: 'robot', title: 'The Wild Robot', year: 2024, facts: '1h 42m · Animation · Family', plot: 'A robot washes up on an island without people and ends up raising a gosling.', status: 'Requestable' },
          { art: 'conclave', title: 'Conclave', year: 2024, facts: '2h 0m · Thriller · Drama', plot: 'A cardinal has to run the election of a new pope and finds out what the candidates are hiding.', status: 'Requestable' },
          { art: 'sinners', title: 'Sinners', year: 2025, facts: '2h 17m · Horror · Thriller', plot: 'Twin brothers come home to open a juke joint and find that something else has arrived first.', status: 'Already requested', tone: 'requested' },
        ],
      },
    ],
  },
  {
    name: 'Who is watching',
    asks: [
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
    ],
  },
  {
    name: 'Run your servers',
    asks: [
      {
        id: 'missing',
        q: 'Which films are missing between my servers?',
        step: 'Comparing servers',
        line: 'Home server has three films that Cabin server does not.',
        rows: {
          label: '3 titles on Home server are missing on Cabin server',
          items: [{ title: 'Knives Out', sub: 'Movie · 2019' }, { title: 'The Martian', sub: 'Movie · 2015' }, { title: 'Dune: Part Two', sub: 'Movie · 2024' }],
        },
      },
      {
        id: 'failed',
        q: 'Which tasks failed on my servers today? Restart them.',
        step: 'Fetching jobs',
        line: 'Two tasks failed today. Both are running again.',
        rows: {
          label: 'Carried out by Pleya',
          items: [
            { title: 'Job restarted', sub: 'Scan Movies · Home server', pill: 'Job running', tone: 'ok' },
            { title: 'Job restarted', sub: 'Refresh metadata · Cabin server', pill: 'Job finished', tone: 'ok' },
          ],
        },
      },
      {
        id: 'scan',
        q: 'Scan all movie libraries on all my servers.',
        step: 'Fetching libraries',
        line: 'Scanning two movie libraries.',
        rows: {
          label: 'Carried out by Pleya',
          items: [
            { title: 'Scan started', sub: 'Movies · Home server', pill: 'Scan running', tone: 'ok' },
            { title: 'Scan started', sub: 'Movies · Cabin server', pill: 'Scan running', tone: 'ok' },
          ],
        },
      },
    ],
  },
];
