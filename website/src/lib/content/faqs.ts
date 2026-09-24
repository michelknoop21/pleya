export type Faq = {
  id: string;
  question: string;
  answer: string;
  schemaAnswer?: string;
};

export const faqs: Faq[] = [
  {
    id: "pricing",
    question: "How much does Pleya cost?",
    answer:
      "Pleya is free during the beta. Final pricing has not been decided; it will be announced well before Pleya leaves beta, and beta testers hear first.",
  },
  {
    id: "beta",
    question: "Is Pleya available yet?",
    answer:
      "Pleya is in a private TestFlight beta for iPhone, Apple TV and Mac. It is not in the App Store or any other store yet.",
  },
  {
    id: "plex-and-jellyfin",
    question: "Does it work with both Plex and Jellyfin?",
    answer:
      "Yes, also at the same time. For Plex you sign in with your Plex account; for Jellyfin you use a username and password or Quick Connect.",
  },
  {
    id: "recommendations-private",
    question: "Are the recommendations private?",
    answer:
      "Yes. Pleya builds your taste profile on the device and keeps it there. Nothing about what you watch is uploaded, tracked or shared.",
  },
  {
    id: "share-vs-watch-together",
    question: "How is Pleya Share different from Watch Together?",
    answer:
      "Watch Together keeps playback in step for people watching from the same server. Pleya Share streams local files from one of your devices to another, with or without internet, and will be a paid feature after the beta.",
  },
  {
    id: "video-player",
    question: "What video player does Pleya use?",
    answer: "mpv on Apple platforms, with direct play whenever possible so your server does not have to transcode.",
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
