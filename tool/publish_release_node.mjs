import { spawnSync } from 'node:child_process';
import { promises as fs } from 'node:fs';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');
const artifactDir = path.join(repoRoot, 'build', 'release_publish');
const pubspecPath = path.join(repoRoot, 'pubspec.yaml');
const dartConfigPath = path.join(repoRoot, 'lib', 'cloud_sync_page.dart');

function writeStep(message) {
  console.log(`[publish] ${message}`);
}

function formatByteSize(bytes) {
  if (!Number.isFinite(bytes) || bytes < 1024) {
    return `${Math.max(0, Math.round(bytes || 0))} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function splitNotes(text) {
  return String(text || '')
    .split(/\r?\n|;/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function getReleaseNotes(inlineNotes, notesFile) {
  if (inlineNotes && inlineNotes.trim()) {
    return splitNotes(inlineNotes);
  }

  if (notesFile && notesFile.trim()) {
    const resolvedPath = path.isAbsolute(notesFile)
      ? notesFile
      : path.resolve(repoRoot, notesFile);
    const content = requireTextFile(resolvedPath, `Release notes file not found: ${resolvedPath}`);
    return content
      .split(/\r?\n/)
      .map((item) => item.trim())
      .filter(Boolean);
  }

  const gitResult = spawnSync(
    'git',
    ['-C', repoRoot, 'log', '--pretty=format:%s', '-n', '5'],
    { encoding: 'utf8' },
  );
  if (gitResult.status === 0 && gitResult.stdout) {
    const notes = gitResult.stdout
      .split(/\r?\n/)
      .map((item) => item.trim())
      .filter(Boolean);
    if (notes.length > 0) {
      return notes;
    }
  }

  return ['General update'];
}

function requireTextFile(filePath, notFoundMessage) {
  try {
    return readFileSync(filePath, 'utf8');
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      throw new Error(notFoundMessage);
    }
    throw error;
  }
}

function readPubspecVersionInfo() {
  const content = requireTextFile(pubspecPath, `pubspec.yaml not found: ${pubspecPath}`);
  const match = content.match(/^version:\s*([0-9A-Za-z.\-_]+)\+([0-9]+)\s*$/m);
  if (!match) {
    throw new Error('Failed to read version from pubspec.yaml');
  }
  return {
    versionName: match[1],
    versionCode: Number(match[2]),
  };
}

function readDartConstString(constName) {
  const content = requireTextFile(
    dartConfigPath,
    `cloud_sync_page.dart not found: ${dartConfigPath}`,
  );
  const pattern = new RegExp(`static const String ${constName}\\s*=\\s*'([^']+)';`);
  const match = content.match(pattern);
  if (!match) {
    throw new Error(`Failed to read config from cloud_sync_page.dart: ${constName}`);
  }
  return match[1];
}

function getCloudConfig() {
  return {
    accessToken: readDartConstString('accessToken'),
    repoOwner: readDartConstString('repoOwner'),
    repoName: readDartConstString('repoName'),
    branch: readDartConstString('branch'),
    appUpdateFilePath: readDartConstString('appUpdateFilePath'),
  };
}

function parseArgs(argv) {
  const remaining = [...argv];
  let mode = 'publish';
  if (remaining[0] && !remaining[0].startsWith('-')) {
    mode = remaining.shift().toLowerCase();
  }

  const options = {
    mode,
    forceUpdate: false,
    title: 'New version available',
  };

  for (let index = 0; index < remaining.length; index += 1) {
    const token = remaining[index];
    switch (token.toLowerCase()) {
      case '-versionname':
        options.versionName = remaining[++index];
        break;
      case '-versioncode':
        options.versionCode = Number(remaining[++index]);
        break;
      case '-title':
        options.title = remaining[++index];
        break;
      case '-notes':
        options.notes = remaining[++index];
        break;
      case '-notesfile':
        options.notesFile = remaining[++index];
        break;
      case '-forceupdate':
        options.forceUpdate = true;
        break;
      case '-publishonly':
      case '-repairmanifestonly':
      case '-buildonly':
      case '-universalapk':
      case '-skippubget':
      case '-skipbuild':
        break;
      default:
        throw new Error(`Unknown argument: ${token}`);
    }
  }

  if (!['publish', 'repair'].includes(options.mode)) {
    throw new Error(`Unsupported mode: ${options.mode}`);
  }

  if (options.versionCode !== undefined && (!Number.isFinite(options.versionCode) || options.versionCode <= 0)) {
    throw new Error('Invalid version code');
  }

  return options;
}

function normalizePath(filePath) {
  return String(filePath || '').replace(/\\/g, '/').replace(/^\/+|\/+$/g, '');
}

function encodeRepoPath(filePath) {
  return normalizePath(filePath)
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
}

function buildApiUrl(baseUrl, query = {}) {
  const url = new URL(baseUrl);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }
  return url.toString();
}

async function readJsonResponse(response) {
  const text = await response.text();
  if (!text) {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function ensureOk(response, context) {
  if (response.ok) {
    return readJsonResponse(response);
  }

  const payload = await readJsonResponse(response);
  const detail = typeof payload === 'string'
    ? payload
    : payload?.message || JSON.stringify(payload);
  const error = new Error(`${context}: ${detail}`);
  error.status = response.status;
  error.payload = payload;
  throw error;
}

async function getReleaseList(config) {
  const url = buildApiUrl(
    `https://gitee.com/api/v5/repos/${config.repoOwner}/${config.repoName}/releases`,
    {
      access_token: config.accessToken,
      page: 1,
      per_page: 100,
    },
  );
  const response = await fetch(url, {
    headers: {
      Accept: 'application/json',
      'Cache-Control': 'no-cache',
    },
  });
  const payload = await ensureOk(response, 'Failed to list Gitee releases');
  if (Array.isArray(payload)) {
    return payload;
  }
  return payload ? [payload] : [];
}

function findReleaseByTag(releases, tagName) {
  return releases.find((release) => String(release?.tag_name || '').trim() === tagName) || null;
}

async function getOrCreateRelease(config, tagName, releaseName, notes) {
  const releases = await getReleaseList(config);
  const existing = findReleaseByTag(releases, tagName);
  if (existing) {
    return existing;
  }

  const body = new URLSearchParams({
    access_token: config.accessToken,
    tag_name: tagName,
    target_commitish: config.branch,
    name: releaseName,
    body: notes.join('\n'),
    prerelease: 'false',
  });
  const response = await fetch(
    `https://gitee.com/api/v5/repos/${config.repoOwner}/${config.repoName}/releases`,
    {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body,
    },
  );
  return ensureOk(response, 'Failed to create Gitee release');
}

function parseAssetDateValue(asset) {
  const candidates = [
    asset?.created_at,
    asset?.updated_at,
    asset?.createdAt,
    asset?.updatedAt,
  ];
  for (const candidate of candidates) {
    if (!candidate) {
      continue;
    }
    const parsed = Date.parse(String(candidate).trim());
    if (!Number.isNaN(parsed)) {
      return parsed;
    }
  }
  return 0;
}

function parseAssetIdValue(asset) {
  const value = Number(String(asset?.id ?? '').trim());
  return Number.isFinite(value) ? value : 0;
}

function selectReleaseApkAsset(release, preferredAssetName = '') {
  const assets = (Array.isArray(release?.assets) ? release.assets : [release?.assets])
    .filter(Boolean)
    .filter((asset) => String(asset?.name || '').toLowerCase().endsWith('.apk'));

  if (preferredAssetName) {
    const exact = assets.find((asset) => String(asset?.name || '') === preferredAssetName);
    if (exact) {
      return exact;
    }
  }

  return assets
    .sort((left, right) => {
      const dateDelta = parseAssetDateValue(right) - parseAssetDateValue(left);
      if (dateDelta !== 0) {
        return dateDelta;
      }
      const idDelta = parseAssetIdValue(right) - parseAssetIdValue(left);
      if (idDelta !== 0) {
        return idDelta;
      }
      return String(right?.name || '').localeCompare(String(left?.name || ''));
    })[0] || null;
}

function resolveAssetDownloadUrl(asset) {
  const candidates = [
    asset?.browser_download_url,
    asset?.download_url,
    asset?.html_url,
  ];
  return candidates.find((candidate) => candidate && String(candidate).trim()) || null;
}

function buildManifest({
  versionName,
  versionCode,
  title,
  downloadUrl,
  notes,
  forceUpdate,
  publishedBy,
}) {
  return {
    appId: 'photo_namer',
    versionName,
    versionCode,
    title,
    downloadUrl,
    changelog: notes,
    forceUpdate,
    publishedAt: new Date().toISOString(),
    publishedBy,
  };
}

async function getRepoContentMetadata(config, filePath) {
  const normalized = normalizePath(filePath);
  const url = buildApiUrl(
    `https://gitee.com/api/v5/repos/${config.repoOwner}/${config.repoName}/contents/${encodeRepoPath(normalized)}`,
    {
      access_token: config.accessToken,
      ref: config.branch,
      t: Date.now(),
    },
  );
  const response = await fetch(url, {
    headers: {
      Accept: 'application/json',
      'Cache-Control': 'no-cache',
    },
  });

  if (response.status === 404) {
    return null;
  }

  return ensureOk(response, `Failed to fetch repo file metadata: ${normalized}`);
}

async function writeRepoJsonFile(config, filePath, jsonData, message) {
  const normalized = normalizePath(filePath);
  const url = `https://gitee.com/api/v5/repos/${config.repoOwner}/${config.repoName}/contents/${encodeRepoPath(normalized)}`;
  const contentBase64 = Buffer.from(`${JSON.stringify(jsonData, null, 2)}\n`, 'utf8').toString('base64');

  const tryUpdate = async (sha) => {
    const body = new URLSearchParams({
      access_token: config.accessToken,
      content: contentBase64,
      message,
      branch: config.branch,
      sha,
    });
    writeStep(`Cloud manifest update mode: sha=${sha}`);
    const response = await fetch(url, {
      method: 'PUT',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cache-Control': 'no-cache',
      },
      body,
    });
    return ensureOk(response, `Failed to update cloud manifest: ${normalized}`);
  };

  const existing = await getRepoContentMetadata(config, normalized);
  if (existing?.sha) {
    return tryUpdate(existing.sha);
  }

  const createBody = new URLSearchParams({
    access_token: config.accessToken,
    content: contentBase64,
    message,
    branch: config.branch,
  });
  writeStep(`Cloud manifest create mode: ${normalized}`);
  const createResponse = await fetch(url, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      'Cache-Control': 'no-cache',
    },
    body: createBody,
  });

  if (createResponse.ok) {
    return readJsonResponse(createResponse);
  }

  const payload = await readJsonResponse(createResponse);
  const detail = typeof payload === 'string'
    ? payload
    : payload?.message || JSON.stringify(payload);

  if (String(detail).includes('文件名已存在')) {
    writeStep('Cloud manifest create conflict, retrying as direct update');
    const refreshed = await getRepoContentMetadata(config, normalized);
    if (refreshed?.sha) {
      return tryUpdate(refreshed.sha);
    }
  }

  throw new Error(`Failed to create cloud manifest: ${detail}`);
}

async function resolveBuiltApkPath(versionName, versionCode) {
  const summaryPath = path.join(artifactDir, 'last_build_summary.json');
  try {
    const summary = JSON.parse(await fs.readFile(summaryPath, 'utf8'));
    const apkPath = path.isAbsolute(summary.apkPath)
      ? summary.apkPath
      : path.resolve(repoRoot, summary.apkPath);
    if (
      summary.versionName === versionName &&
      Number(summary.versionCode) === Number(versionCode)
      && apkPath
    ) {
      await fs.access(apkPath);
      return {
        apkPath,
        apkFlavor: summary.apkFlavor || 'arm64-v8a',
      };
    }
  } catch {
  }

  const fileEntries = await fs.readdir(artifactDir, { withFileTypes: true });
  const escapedVersionName = versionName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`^photo_namer-(.+)-v${escapedVersionName}-${versionCode}-(\\d{8}_\\d{6})\\.apk$`, 'i');
  const matches = [];

  for (const entry of fileEntries) {
    if (!entry.isFile()) {
      continue;
    }
    const match = entry.name.match(pattern);
    if (!match) {
      continue;
    }
    const fullPath = path.join(artifactDir, entry.name);
    const stats = await fs.stat(fullPath);
    matches.push({
      apkPath: fullPath,
      apkFlavor: match[1],
      mtimeMs: stats.mtimeMs,
      name: entry.name,
    });
  }

  matches.sort((left, right) => {
    const timeDelta = right.mtimeMs - left.mtimeMs;
    if (timeDelta !== 0) {
      return timeDelta;
    }
    return right.name.localeCompare(left.name);
  });

  if (matches.length === 0) {
    throw new Error(`No built APK found for version ${versionName} (${versionCode}) in ${artifactDir}`);
  }

  return matches[0];
}

async function uploadReleaseAsset(config, releaseId, filePath) {
  const fileName = path.basename(filePath);
  const fileBuffer = await fs.readFile(filePath);
  const form = new FormData();
  form.set('access_token', config.accessToken);
  form.set('owner', config.repoOwner);
  form.set('repo', config.repoName);
  form.set('release_id', String(releaseId));
  form.set('file', new Blob([fileBuffer]), fileName);

  writeStep(`Uploading file ${fileName} (${formatByteSize(fileBuffer.byteLength)})`);
  const response = await fetch(
    `https://gitee.com/api/v5/repos/${config.repoOwner}/${config.repoName}/releases/${releaseId}/attach_files`,
    {
      method: 'POST',
      headers: {
        Accept: 'application/json',
      },
      body: form,
    },
  );
  return ensureOk(response, 'Failed to upload APK to Gitee Release');
}

async function writeSummary(fileName, summary) {
  await fs.mkdir(artifactDir, { recursive: true });
  await fs.writeFile(
    path.join(artifactDir, fileName),
    `${JSON.stringify(summary, null, 2)}\n`,
    'utf8',
  );
}

async function publishBuiltRelease(options) {
  const pubspecVersion = readPubspecVersionInfo();
  const versionName = options.versionName?.trim() || pubspecVersion.versionName;
  const versionCode = options.versionCode || pubspecVersion.versionCode;
  const title = options.title?.trim() || 'New version available';
  const config = getCloudConfig();
  const notes = getReleaseNotes(options.notes, options.notesFile);
  const tagName = `v${versionName}-${versionCode}`;
  const releaseName = `PhotoNamer ${versionName} (${versionCode})`;

  const built = await resolveBuiltApkPath(versionName, versionCode);
  writeStep(`Using built APK: ${built.apkPath}`);

  writeStep(`Creating or reusing Gitee Release: ${tagName}`);
  const release = await getOrCreateRelease(config, tagName, releaseName, notes);
  if (!release?.id) {
    throw new Error('Failed to get Gitee Release ID');
  }

  writeStep('Uploading APK to Gitee Release');
  const asset = await uploadReleaseAsset(config, Number(release.id), built.apkPath);
  const downloadUrl = resolveAssetDownloadUrl(asset);
  if (!downloadUrl) {
    throw new Error('Upload succeeded, but no download URL was returned by Gitee');
  }

  const manifest = buildManifest({
    versionName,
    versionCode,
    title,
    downloadUrl,
    notes,
    forceUpdate: Boolean(options.forceUpdate),
    publishedBy: 'release_node_script',
  });

  writeStep('Updating cloud app update manifest');
  await writeRepoJsonFile(
    config,
    config.appUpdateFilePath,
    manifest,
    `photo_namer publish app update ${manifest.publishedAt}`,
  );

  const summary = {
    mode: 'publish_only_node',
    versionName,
    versionCode,
    tagName,
    releaseName,
    downloadUrl,
    apkPath: built.apkPath,
    apkFlavor: built.apkFlavor,
    notes,
    publishedAt: manifest.publishedAt,
    forceUpdate: Boolean(options.forceUpdate),
  };
  await writeSummary('last_publish_summary.json', summary);

  console.log('');
  console.log('Publish completed');
  console.log(`Version: ${versionName} (${versionCode})`);
  console.log(`APK: ${built.apkPath}`);
  console.log(`Download URL: ${downloadUrl}`);
  console.log(`Summary: ${path.join(artifactDir, 'last_publish_summary.json')}`);
}

async function repairReleaseManifest(options) {
  const pubspecVersion = readPubspecVersionInfo();
  const versionName = options.versionName?.trim() || pubspecVersion.versionName;
  const versionCode = options.versionCode || pubspecVersion.versionCode;
  const title = options.title?.trim() || 'New version available';
  const config = getCloudConfig();
  const tagName = `v${versionName}-${versionCode}`;
  const releaseName = `PhotoNamer ${versionName} (${versionCode})`;

  writeStep(`Repairing cloud app update manifest from release: ${tagName}`);
  const releases = await getReleaseList(config);
  const release = findReleaseByTag(releases, tagName);
  if (!release) {
    throw new Error(`Release not found: ${tagName}`);
  }

  const asset = selectReleaseApkAsset(release);
  if (!asset) {
    throw new Error(`APK asset not found in release: ${tagName}`);
  }

  const notes = options.notes?.trim() || options.notesFile
    ? getReleaseNotes(options.notes, options.notesFile)
    : splitNotes(release.body || '');
  const normalizedNotes = notes.length > 0 ? notes : ['General update'];

  const downloadUrl = resolveAssetDownloadUrl(asset);
  if (!downloadUrl) {
    throw new Error(`APK download URL not found in release: ${tagName}`);
  }

  const manifest = buildManifest({
    versionName,
    versionCode,
    title,
    downloadUrl,
    notes: normalizedNotes,
    forceUpdate: Boolean(options.forceUpdate),
    publishedBy: 'release_node_script_repair',
  });

  writeStep('Updating cloud app update manifest');
  await writeRepoJsonFile(
    config,
    config.appUpdateFilePath,
    manifest,
    `photo_namer repair app update ${manifest.publishedAt}`,
  );

  const summary = {
    mode: 'repair_manifest_only_node',
    versionName,
    versionCode,
    tagName,
    releaseName,
    downloadUrl,
    notes: normalizedNotes,
    publishedAt: manifest.publishedAt,
    forceUpdate: Boolean(options.forceUpdate),
  };
  await writeSummary('last_publish_summary.json', summary);

  console.log('');
  console.log('Manifest repair completed');
  console.log(`Version: ${versionName} (${versionCode})`);
  console.log(`Download URL: ${downloadUrl}`);
  console.log(`Summary: ${path.join(artifactDir, 'last_publish_summary.json')}`);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.mode === 'publish') {
    await publishBuiltRelease(options);
    return;
  }
  await repairReleaseManifest(options);
}

main().catch((error) => {
  const message = error?.message || String(error);
  console.error(message);
  process.exitCode = 1;
});
