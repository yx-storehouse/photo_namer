// 一次性拆分脚本:按行号区间把代码块从源文件搬到新文件,并做词边界重命名。
// 用法: node tool/_tmp_split.mjs <plan.json>
// 区间行号基于执行前的源文件;先校验锚点与区间不重叠,再统一输出。
import fs from 'node:fs';
import path from 'node:path';

const plan = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const text = fs.readFileSync(plan.source, 'utf8');
const eol = text.includes('\r\n') ? '\r\n' : '\n';
const lines = text.split(/\r?\n/);

for (const ex of plan.extractions ?? []) {
  for (const r of ex.ranges) {
    const [a, , expect] = r;
    if (expect && !(lines[a - 1] ?? '').trimStart().startsWith(expect)) {
      console.error(`ANCHOR MISMATCH ${ex.dest} line ${a}: expected "${expect}", got "${lines[a - 1]}"`);
      process.exit(1);
    }
  }
}

const allRanges = [];
for (const ex of plan.extractions ?? []) for (const [a, b] of ex.ranges) allRanges.push([a, b]);
for (const [a, b] of plan.deletions ?? []) allRanges.push([a, b]);
allRanges.sort((x, y) => x[0] - y[0]);
for (let i = 1; i < allRanges.length; i++) {
  if (allRanges[i][0] <= allRanges[i - 1][1]) {
    console.error(`OVERLAP: [${allRanges[i - 1]}] and [${allRanges[i]}]`);
    process.exit(1);
  }
}

for (const ex of plan.extractions ?? []) {
  const rel = path.relative('lib', ex.dest).replaceAll('\\', '/');
  const selfImport = `package:photo_namer/${rel}`;
  const header = (plan.commonHeader ?? [])
    .filter((l) => !l.includes(selfImport))
    .join(eol);
  const chunks = ex.ranges.map(([a, b]) => lines.slice(a - 1, b).join(eol));
  fs.mkdirSync(path.dirname(ex.dest), { recursive: true });
  fs.writeFileSync(ex.dest, header + eol + eol + chunks.join(eol + eol) + eol);
  console.log(`wrote ${ex.dest}`);
}

let out = lines.slice();
for (const [a, b] of [...allRanges].sort((x, y) => y[0] - x[0])) out.splice(a - 1, b - a + 1);

if (plan.sourceImports?.length) {
  const idx = out.findIndex((l) => l.startsWith(plan.importAnchor));
  if (idx < 0) { console.error('import anchor not found'); process.exit(1); }
  out.splice(idx + 1, 0, ...plan.sourceImports);
}
fs.writeFileSync(plan.source, out.join(eol));
console.log(`source trimmed to ${out.length} lines`);

for (const f of plan.renameFiles ?? []) {
  let t = fs.readFileSync(f, 'utf8');
  for (const [oldName, newName] of Object.entries(plan.renames ?? {})) {
    t = t.replaceAll(new RegExp(`\\b${oldName}\\b`, 'g'), newName);
  }
  fs.writeFileSync(f, t);
  console.log(`renamed in ${f}`);
}
