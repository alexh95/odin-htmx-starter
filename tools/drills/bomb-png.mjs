// A small PNG whose decode fills the uploads arena's cap: 4400 × 4400, 16 bits, four channels, one
// colour. Well under 40 MP and 10 MiB, so it passes every check before the decode, and its raw
// rows and pixels come to more than the 256 MiB a decode may hold.
//
//   node tools/drills/bomb-png.mjs <out.png> [width] [height]

import { writeFileSync } from 'node:fs';
import zlib from 'node:zlib';

const out = process.argv[2];
const W = Number(process.argv[3] || 4400), H = Number(process.argv[4] || 4400);
const chunk = (type, data) => {
  const head = Buffer.alloc(4);
  head.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const sum = Buffer.alloc(4);
  sum.writeUInt32BE(zlib.crc32(body) >>> 0);
  return Buffer.concat([head, body, sum]);
};
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0);
ihdr.writeUInt32BE(H, 4);
ihdr[8] = 16; // bits a channel
ihdr[9] = 6; // RGBA
const raw = Buffer.alloc((1 + W * 8) * H);
writeFileSync(out, Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0)),
]));
