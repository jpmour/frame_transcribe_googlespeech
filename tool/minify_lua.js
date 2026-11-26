// Regenerates assets/frame_app.min.lua from assets/frame_app.lua.
// The Flutter app loads the .min.lua file, so it must always match the source.
//
//   cd tool && npm ci          (once)
//   node tool/minify_lua.js           regenerate the min file
//   node tool/minify_lua.js --check   exit 1 if the committed min file is out of date
const fs = require('fs');
const path = require('path');
const luamin = require('luamin');

const assets = path.join(__dirname, '..', 'assets');
const source = path.join(assets, 'frame_app.lua');
const target = path.join(assets, 'frame_app.min.lua');

const minified = luamin.minify(fs.readFileSync(source, 'utf8'));

if (process.argv.includes('--check')) {
  const current = fs.existsSync(target) ? fs.readFileSync(target, 'utf8') : '';
  if (current !== minified) {
    console.error('assets/frame_app.min.lua is out of date. Run: node tool/minify_lua.js');
    process.exit(1);
  }
  console.log('frame_app.min.lua is up to date.');
} else {
  fs.writeFileSync(target, minified);
  console.log(`Wrote ${target} (${minified.length} bytes)`);
}
