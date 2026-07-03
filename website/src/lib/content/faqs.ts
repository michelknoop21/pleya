export type Faq = {
  id: string;
  question: string;
  answer: string;
  schemaAnswer?: string;
};

export const faqs: Faq[] = [
  {
    id: "what-is-pleya",
    question: "What is Pleya?",
    answer:
      "Pleya is a beautiful, cinematic client for your own Plex and Jellyfin media servers. It focuses on quality playback, a fast interface, and privacy — including on-device recommendations that surface what to watch next without any of your taste data leaving your device.",
  },
  {
    id: "plex-and-jellyfin",
    question: "Does Pleya work with both Plex and Jellyfin?",
    answer:
      "Yes. Pleya connects to Plex and Jellyfin servers alike. For Plex you sign in with your Plex account; for Jellyfin you can use your username and password or Quick Connect for a one-tap login from another device. Core features — direct play, HDR, subtitles, offline downloads — work the same way on both.",
  },
  {
    id: "beta",
    question: "Is Pleya available yet?",
    answer:
      "Pleya is currently in a private TestFlight beta for iPhone, Apple TV, and macOS. It isn't in the App Store or any other store yet. Join the beta (or the waitlist) on this page and you'll be notified as new builds and platforms roll out.",
  },
  {
    id: "pricing",
    question: "How much does Pleya cost?",
    answer:
      "Pleya is free during the beta. Final pricing hasn't been decided yet — we'll announce it well before Pleya leaves beta, and beta testers will hear first.",
  },
  {
    id: "apple-tv",
    question: "Does Pleya work on Apple TV?",
    answer:
      "Yes. Pleya has a dedicated, Netflix-style tvOS interface built for the living room and the remote. It's part of the current TestFlight beta alongside iPhone and macOS.",
  },
  {
    id: "recommendations-private",
    question: "Are the recommendations private?",
    answer:
      "Completely. Pleya builds your taste profile on your device and keeps it there. Recommendations are computed locally — nothing about what you watch is uploaded, tracked, or shared.",
  },
  {
    id: "watch-together",
    question: "How does Watch Together work?",
    answer:
      "Watch Together uses a lightweight relay to sync playback between people watching the same media on the same server. Only playback sync messages are exchanged — nothing about your server is shared.",
  },
  {
    id: "video-player",
    question: "What video player does Pleya use?",
    answer:
      "Pleya uses mpv for playback on Apple platforms, with direct play whenever possible so your server doesn't have to transcode. On Android, ExoPlayer is used for HDR support and better performance.",
  },
  {
    id: "open-source",
    question: "Is Pleya open source?",
    answer:
      'Pleya is a fork built on the open-source Plezy project, which is licensed under the GPL-3.0. In keeping with that license we credit and link the upstream source in the footer.',
  },
];

function htmlToText(value: string) {
  return value
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&middot;/g, "·")
    .replace(/\s+/g, " ")
    .trim();
}

export const faqSchemaMainEntity = faqs.map((faq) => ({
  "@type": "Question",
  name: faq.question,
  acceptedAnswer: {
    "@type": "Answer",
    text: faq.schemaAnswer ?? htmlToText(faq.answer),
  },
}));
