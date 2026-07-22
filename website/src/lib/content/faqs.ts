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
      "Pleya is a beautiful, cinematic client for your own Plex and Jellyfin media servers. It focuses on quality playback, a fast interface, and privacy, including on-device recommendations that surface what to watch next without any of your taste data leaving your device.",
  },
  {
    id: "plex-and-jellyfin",
    question: "Does Pleya work with both Plex and Jellyfin?",
    answer:
      "Yes. Pleya connects to Plex and Jellyfin servers alike. For Plex you sign in with your Plex account; for Jellyfin you can use your username and password or Quick Connect for a one-tap login from another device. Core features like direct play, HDR, subtitles and offline downloads work the same way on both.",
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
      "Pleya is free during the beta. Final pricing hasn't been decided yet; we'll announce it well before Pleya leaves beta, and beta testers will hear first.",
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
      "Completely. Pleya builds your taste profile on your device and keeps it there. Recommendations are computed locally, so nothing about what you watch is uploaded, tracked, or shared.",
  },
  {
    id: "requests",
    question: "Can I request new movies and shows?",
    answer:
      "Yes, if you run Jellyseerr or Overseerr. Connect your requests server in Pleya and you can browse, search and request movies and shows without leaving the app, then follow each request as it moves from pending to available. Without a Jellyseerr or Overseerr server this feature simply stays hidden.",
  },
  {
    id: "pleya-share",
    question: "What is Pleya Share?",
    answer:
      "Pleya Share turns one of your devices into a mini media server for your other Pleya devices. Pair once with a QR code and stream local files over Wi-Fi, a personal hotspot, or a cable, with no internet needed. A cable can be ethernet adapters, or USB-C with USB tethering enabled on the host (Android, or an iPhone connected to a computer); a direct iPhone-to-iPad USB link is not supported by iOS itself. When both devices are online, streaming also works remotely through Pleya's end-to-end encrypted relay. Multiple devices can stream from one host at the same time, and watch progress and artwork sync with your Plex or Jellyfin account. Pleya Share is a premium feature: it will be part of Pleya's paid tier once pricing is announced after the beta.",
  },
  {
    id: "watch-together",
    question: "How does Watch Together work?",
    answer:
      "Watch Together uses a lightweight relay to sync playback between people watching the same media on the same server. Only playback sync messages are exchanged, and nothing about your server is shared.",
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
      "Yes. Pleya is free software under the GPL-3.0. The full license and third-party notices ship with the app and this site, and Pleya's own source code is linked from the footer.",
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
