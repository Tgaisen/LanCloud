#!/usr/bin/env node
//
// Renders assets/icon_master.svg (the icon master: rounded tile + cloud) into
// PNG frames at exact pixel sizes, so the Windows .ico does not have to be
// downscaled from one big bitmap. Rendering per size straight from the vector
// is what keeps the 16–48px frames crisp (see tools/gen_app_icons.ps1).
//
// Usage:
//   npm i @resvg/resvg-js            # once, anywhere (NODE_PATH works too)
//   node tools/render_icon_pngs.cjs assets/icon_master.svg <outDir> 16,20,30,… [options]
//
//   --crop-tile   crop the viewBox to the rounded tile itself, so the tile fills
//                 the whole frame (what the Windows taskbar / Explorer expect).
//                 Without it the 108x108 canvas is kept (Android/iOS safe zone).
//   --cloud-only  drop the rounded tile and keep only the cloud glyph. Used for
//                 Android's monochrome (themed icon) layer, where a filled tile
//                 would just render as a solid block.
//   --bg RRGGBB   composite onto an opaque background of that colour
//                 (Android legacy icons / iOS, which are full-bleed squares).
//   --fix-seams   the master's cloud is a multi-subpath trace with hairline gaps
//                 between the lobes; a same-colour 1.2 stroke closes them.
//
const fs = require('fs');
const path = require('path');

function fail(message) {
  console.error(message);
  process.exit(1);
}

let Resvg;
try {
  ({ Resvg } = require('@resvg/resvg-js'));
} catch (error) {
  fail(
    '缺少 @resvg/resvg-js，先安装：npm i @resvg/resvg-js\n' +
      '（或用 NODE_PATH 指向已安装的 node_modules）\n' +
      String(error && error.message ? error.message : error),
  );
}

const [, , svgPath, outDir, sizesArg, ...flags] = process.argv;
if (!svgPath || !outDir || !sizesArg) {
  fail(
    '用法: node tools/render_icon_pngs.cjs <svg> <outDir> <sizes csv> [--crop-tile] [--fix-seams]',
  );
}

const cropTile = flags.includes('--crop-tile');
const cloudOnly = flags.includes('--cloud-only');
const fixSeams = flags.includes('--fix-seams');
const bgIndex = flags.indexOf('--bg');
const background =
  bgIndex >= 0 && flags[bgIndex + 1] ? `#${flags[bgIndex + 1]}` : 'rgba(0,0,0,0)';

let svg = fs.readFileSync(svgPath, 'utf8');
if (cloudOnly) {
  // <rect id="矩形_1" … fill="#0ac4e0"/> —— 直角/圆角方块那层
  svg = svg.replace(/<rect id="[^"]*"[^>]*fill="#0ac4e0"\/>/i, '');
}
if (fixSeams) {
  svg = svg.replace(
    /fill="#fff"\/>/g,
    'fill="#fff" stroke="#fff" stroke-width="1.2" stroke-linejoin="round"/>',
  );
}
if (cropTile) {
  // 圆角方块：宽高 70、圆角 20，经 transform 平移后位于 (19, 19)
  svg = svg.replace(/viewBox="0 0 108 108"/, 'viewBox="19 19 70 70"');
}

fs.mkdirSync(outDir, { recursive: true });
for (const size of sizesArg.split(',').map((s) => Number(s.trim()))) {
  if (!Number.isFinite(size) || size <= 0) fail(`无效尺寸: ${size}`);
  const renderer = new Resvg(svg, {
    fitTo: { mode: 'width', value: size },
    background,
  });
  fs.writeFileSync(path.join(outDir, `${size}.png`), renderer.render().asPng());
}
