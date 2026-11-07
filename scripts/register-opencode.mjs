import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

const serverPath = process.argv[2];
if (!serverPath) throw new Error('Usage: register-opencode.mjs <server-entrypoint>');
const configPath = join(homedir(), '.config', 'opencode', 'opencode.json');
await mkdir(dirname(configPath), { recursive: true });
let config = {};
try {
  config = JSON.parse(await readFile(configPath, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw new Error(`Cannot safely update ${configPath}: ${error.message}`);
}
config.mcp ??= {};
config.mcp['mac-ocr'] = { type: 'local', command: ['node', serverPath], enabled: true };
await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
