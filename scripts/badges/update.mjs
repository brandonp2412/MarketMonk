import { makeBadge } from 'badge-maker';
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const repo = process.env.GITHUB_REPOSITORY || 'brandonp2412/MarketMonk';
const api = (...args) => JSON.parse(execFileSync('gh', ['api', ...args], {
  encoding: 'utf8', maxBuffer: 50 * 1024 * 1024,
}));
const releases = api(`repos/${repo}/releases?per_page=100`, '--paginate', '--slurp').flat();
const count = releases.filter(r => !r.draft).flatMap(r => r.assets)
  .reduce((total, asset) => total + asset.download_count, 0);
const latest = api(`repos/${repo}/releases/latest`).tag_name;

// Match Shields' compact SI formatting.
function metric(n) {
  const units = ['', 'k', 'M', 'G', 'T', 'P', 'E'];
  for (let i = units.length - 1; i > 0; i--) {
    const scaled = n / 1000 ** i;
    if (scaled >= 1) {
      const rounded = scaled < 10 ? Number(scaled.toFixed(1)) : Math.round(scaled);
      return rounded >= 1000 ? '1' + units[i + 1] : rounded + units[i];
    }
  }
  return String(n);
}
function writeBadge(file, label, message) {
  const svg = makeBadge({
    label, message, color: '#151218', labelColor: '#ffb52e',
    style: 'for-the-badge',
  });
  writeFileSync(new URL('../../docs/' + file, import.meta.url), svg + '\n');
}
writeBadge('release.svg', 'release', latest);
writeBadge('downloads.svg', 'downloads', metric(count));
console.log(`Release: ${latest}; downloads: ${count}`);
