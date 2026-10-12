// Geometry of the Big P layers, in the coordinates of the full render (1122 x 1402).
// The WebP files come from scripts/gen-bigp-layers.sh; the numbers are those of
// bigp-layers.json next to the source layers.
import body from '$lib/assets/bigp/body.webp';
import bodyNoleg from '$lib/assets/bigp/body-noleg.webp';
import bodyWijzen from '$lib/assets/bigp/body-wijzen-noleg.webp';
import aimArm from '$lib/assets/bigp/aim-arm.webp';
import waveArm from '$lib/assets/bigp/wave-arm.webp';
import browL from '$lib/assets/bigp/brow-l.webp';
import browR from '$lib/assets/bigp/brow-r.webp';
import legLUpper from '$lib/assets/bigp/leg-l-upper.webp';
import legLLower from '$lib/assets/bigp/leg-l-lower.webp';
import legRUpper from '$lib/assets/bigp/leg-r-upper.webp';
import legRLower from '$lib/assets/bigp/leg-r-lower.webp';
import mouthRest from '$lib/assets/bigp/mouth-rest.webp';
import mouthSmall from '$lib/assets/bigp/mouth-small.webp';
import mouthMid from '$lib/assets/bigp/mouth-mid.webp';
import mouthBig from '$lib/assets/bigp/mouth-big.webp';
import mouthO from '$lib/assets/bigp/mouth-o.webp';
import mouthE from '$lib/assets/bigp/mouth-e.webp';
import mouthLaugh from '$lib/assets/bigp/mouth-laugh.webp';
import poseZwaaien from '$lib/assets/bigp/pose-zwaaien.webp';
import poseJuichen from '$lib/assets/bigp/pose-juichen.webp';
import poseDuim from '$lib/assets/bigp/pose-duim_presenteren.webp';
import poseVinger from '$lib/assets/bigp/pose-vinger_presenteren.webp';
import poseWijzenLinks from '$lib/assets/bigp/pose-wijzen_links.webp';

export type Box = { x: number; y: number; w: number; h: number };
export type Point = [number, number];

export const L = {
  w: 1122,
  h: 1402,
  feet: [545, 1184] as Point,
  mouth: { x: 386, y: 387, w: 257, h: 272 },
  browL: { x: 405, y: 225, w: 119, h: 62 },
  browR: { x: 696, y: 226, w: 102, h: 58 },
  eyes: [
    { cx: 460, cy: 382, rx: 62, ry: 63, lid: '#fc2013' },
    { cx: 768, cy: 378, rx: 47, ry: 63, lid: '#fc5b2e' },
  ],
  wave: { x: 28, y: 267, w: 240, h: 393, pivot: [289, 566] as Point },
  aim: { x: 690, y: 628, w: 388, h: 188, pivot: [722, 658] as Point, tip: [1068, 722] as Point },
  legs: {
    l: { upper: { x: 272, y: 888, w: 218, h: 112 }, lower: { x: 242, y: 986, w: 260, h: 199 }, hip: [445, 884] as Point, knee: [440, 992] as Point },
    r: { upper: { x: 530, y: 698, w: 205, h: 306 }, lower: { x: 563, y: 990, w: 278, h: 196 }, hip: [592, 712] as Point, knee: [600, 996] as Point },
  },
};

export const MOUTHS = ['rest', 'small', 'mid', 'big', 'o', 'e', 'laugh'] as const;
export type Mouth = (typeof MOUTHS)[number];

// Full poses (pose-*.webp) are warped so their P lies on the rest render; the mouth and
// brow layers fit on top. Each has its own leg length: `feet` is where its shoes end.
export const POSES = ['zwaaien', 'juichen', 'duim_presenteren', 'vinger_presenteren', 'wijzen_links'] as const;
export type ImagePose = (typeof POSES)[number];
/** 'rest' and 'wijzen' are the rigged bodies: separate legs, and for 'wijzen' an arm that aims. */
export type Pose = ImagePose | 'rest' | 'wijzen';

export const POSE_FEET: Record<ImagePose, number> = { zwaaien: 1157, juichen: 1238, duim_presenteren: 1147, vinger_presenteren: 1149, wijzen_links: 1228 };
/** Three-quarter view with its own face: no mouth, brow or lid layer on top. */
export const OWN_FACE: Partial<Record<Pose, boolean>> = { wijzen_links: true };

/** The complete figure in one image: fallback before the rig mounts and without JavaScript. */
export const STILL = body;

/** Loaded with the page: everything the rest pose needs to stand, blink, walk and talk. */
export const CORE = {
  rest: bodyNoleg,
  browL,
  browR,
  legs: { l: { upper: legLUpper, lower: legLLower }, r: { upper: legRUpper, lower: legRLower } },
  mouths: { rest: mouthRest, small: mouthSmall, mid: mouthMid, big: mouthBig, o: mouthO, e: mouthE, laugh: mouthLaugh } satisfies Record<Mouth, string>,
};

/** Loaded after the first paint: each pose is only shown once all of its images have arrived. */
export const LATER: Record<Exclude<Pose, 'rest'>, string[]> = {
  wijzen: [bodyWijzen, aimArm],
  zwaaien: [poseZwaaien, waveArm],
  juichen: [poseJuichen],
  duim_presenteren: [poseDuim],
  vinger_presenteren: [poseVinger],
  wijzen_links: [poseWijzenLinks],
};
