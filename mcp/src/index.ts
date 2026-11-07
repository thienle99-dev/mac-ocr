import { execFile, spawn } from 'node:child_process';
import { access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

const execFileAsync = promisify(execFile);
const here = dirname(fileURLToPath(import.meta.url));
const defaultBinary = resolve(here, '../../.build/release/mac-ocr');
const configuredBinary = process.env.MAC_OCR_BIN;
const defaultTimeout = 60_000;
const configuredTimeout = Number(process.env.MAC_OCR_TIMEOUT_MS);
const timeout = Number.isInteger(configuredTimeout) && configuredTimeout > 0
  ? configuredTimeout
  : defaultTimeout;
const timeoutConfigured = Number.isInteger(configuredTimeout) && configuredTimeout > 0;

const server = new McpServer({ name: 'mac-ocr', version: '1.0.0' });

async function findBinary() {
  let binary = configuredBinary || defaultBinary;
  try {
    await access(binary, constants.X_OK);
  } catch {
    if (!configuredBinary) {
      try {
        const { stdout } = await execFileAsync('/usr/bin/which', ['mac-ocr']);
        binary = stdout.trim();
        await access(binary, constants.X_OK);
      } catch {
        throw new Error(`mac-ocr binary not found at ${defaultBinary} or on PATH. Run \`make install\` or set MAC_OCR_BIN.`);
      }
    } else {
      throw new Error(`mac-ocr binary not found at ${binary}. Set MAC_OCR_BIN to an executable.`);
    }
  }
  return binary;
}

async function runOCR(args: string[], processTimeout = timeout) {
  let binary: string;
  try { binary = await findBinary(); } catch (error) {
    return { content: [{ type: 'text' as const, text: (error as Error).message }], isError: true };
  }
  try {
    const { stdout } = await execFileAsync(binary, args, { maxBuffer: 16 * 1024 * 1024, timeout: processTimeout });
    return { content: [{ type: 'text' as const, text: stdout.trim() }] };
  } catch (error) {
    const failure = error as { stderr?: string; message?: string; killed?: boolean };
    const timedOut = failure.killed === true;
    const detail = timedOut ? `mac-ocr timed out after ${processTimeout} ms.` : failure.stderr?.trim() || failure.message || 'OCR process failed';
    return { content: [{ type: 'text' as const, text: detail }], isError: true };
  }
}

async function runBatch(paths: string[], languages?: string[], level?: 'accurate' | 'fast', pixels = false) {
  let binary: string;
  try { binary = await findBinary(); } catch (error) {
    return { content: [{ type: 'text' as const, text: (error as Error).message }], isError: true };
  }
  return new Promise<{content: {type:'text'; text:string}[]; isError?: boolean}>((resolve) => {
    const child = spawn(binary, ['--batch'], { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = ''; let stderr = ''; let settled = false;
    const finish = (result: {content: {type:'text'; text:string}[]; isError?: boolean}) => { if (!settled) { settled = true; clearTimeout(timer); resolve(result); } };
    const timer = setTimeout(() => { child.kill('SIGKILL'); finish({content:[{type:'text',text:'Batch OCR timed out'}],isError:true}); }, timeout * paths.length);
    child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; }); child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', error => finish({content:[{type:'text',text:error.message}],isError:true}));
    child.on('close', code => finish(code === 0 ? {content:[{type:'text',text:stdout.trim()}]} : {content:[{type:'text',text:stderr.trim() || `Batch OCR exited ${code}`}],isError:true}));
    child.stdin.end(JSON.stringify({paths, languages: languages ?? (process.env.MAC_OCR_LANGS || undefined)?.split(','), level, pixels}));
  });
}

function commonArgs(languages?: string[], level?: 'accurate' | 'fast') {
  const args: string[] = ['--format', 'json'];
  const effectiveLanguages = languages ?? (process.env.MAC_OCR_LANGS || undefined)?.split(',');
  if (effectiveLanguages?.length) args.push('--lang', effectiveLanguages.join(','));
  if (level) args.push('--level', level);
  return args;
}

const readOnlyAnnotations = { readOnlyHint: true, openWorldHint: false };

server.registerTool(
  'ocr_image',
  {
    description: 'Recognize text in an image using Apple Vision. Use accurate (the default), especially for Vietnamese or other text with diacritics; fast may drop them (for example, "Xin chao Vièt Nam, hoc may"). Pass languages such as ["vi-VN", "en-US"] for Vietnamese and English. Output box coordinates are normalized from 0 to 1 with origin at the bottom left; confidence is from 0 to 1.',
    inputSchema: {
      path: z.string().min(1).describe('Path to a local image file'),
      languages: z.array(z.string().min(1)).optional().describe('Recognition languages, for example ["vi-VN", "en-US"] for Vietnamese and English'),
      level: z.enum(['accurate', 'fast']).optional().describe('Use accurate (default), especially for Vietnamese or text with diacritics; fast may drop diacritics'),
      pixels: z.boolean().optional().describe('Use pixel boxes with top-left origin'),
    },
    annotations: readOnlyAnnotations,
  },
  async ({ path, languages, level, pixels }) => {
    return runOCR([path, ...commonArgs(languages, level), ...(pixels ? ['--pixels'] : [])]);
  },
);

server.registerTool('ocr_images', {
  description: 'Recognize text in multiple local image files. Returns one JSON result per input path in the same order. Vietnamese languages always use accurate recognition.',
  inputSchema: {
    paths: z.array(z.string().min(1)).min(1).max(50).describe('Local image file paths, up to 50'),
    languages: z.array(z.string().min(1)).optional(),
    level: z.enum(['accurate', 'fast']).optional(),
    pixels: z.boolean().optional().describe('Use pixel boxes with top-left origin'),
  },
  annotations: readOnlyAnnotations,
}, async ({ paths, languages, level, pixels }) => runBatch(paths, languages, level, pixels));

server.registerTool('ocr_pdf', {
  description: 'Read selectable text embedded in each PDF page when available, otherwise OCR the rendered page with Apple Vision. Set forceOCR to true to ignore embedded text. Optionally select a 1-based inclusive page range such as "1-3".',
  inputSchema: {
    path: z.string().min(1).describe('Path to a local PDF file'),
    pages: z.string().regex(/^\d+(-\d+)?$/).optional().describe('1-based page number or inclusive range, for example "2" or "1-3"'),
    languages: z.array(z.string().min(1)).optional().describe('Recognition languages, for example ["vi-VN", "en-US"]'),
    level: z.enum(['accurate', 'fast']).optional().describe('Recognition level'),
    pixels: z.boolean().optional().describe('Use pixel boxes with top-left origin'),
    forceOCR: z.boolean().optional().describe('Ignore selectable PDF text and run Apple Vision OCR on every selected page'),
  },
  annotations: readOnlyAnnotations,
}, async ({ path, pages, languages, level, pixels, forceOCR }) => {
  const args = [path, ...commonArgs(languages, level)];
  if (pages) args.push('--pages', pages);
  if (pixels) args.push('--pixels');
  if (forceOCR) args.push('--force-ocr');
  const [first, last = first] = pages ? pages.split('-').map(Number) : [1];
  // Without `pages` the whole document is processed and its length is unknown, so allow 5x the default.
  const count = pages ? last - first + 1 : 5;
  return runOCR(args, timeoutConfigured ? timeout : defaultTimeout * Math.max(1, count));
});

server.registerTool('list_displays', {
  description: 'List active displays with desktop point bounds, pixel dimensions, scale, and the 1-based index used by ocr_screen.',
  inputSchema: {},
  annotations: readOnlyAnnotations,
}, async () => runOCR(['--list-displays']));

server.registerTool('ocr_screen', {
  description: 'Capture a display or screen region and recognize its text. The host app needs Screen Recording permission.',
  inputSchema: {
    languages: z.array(z.string().min(1)).optional().describe('Recognition languages, for example ["vi-VN", "en-US"]'),
    level: z.enum(['accurate', 'fast']).optional().describe('Recognition level'),
    region: z.string().regex(/^-?\d+,-?\d+,\d+,\d+$/).optional().describe('Capture rectangle x,y,width,height in desktop points; x or y may be negative'),
    display: z.number().int().positive().optional().describe('1-based display index; cannot be combined with region'),
    pixels: z.boolean().optional().describe('Use pixel boxes with top-left origin'),
  },
  annotations: readOnlyAnnotations,
}, async ({ languages, level, region, display, pixels }) => {
  const args = ['--screen', ...commonArgs(languages, level)];
  if (region) args.push('--region', region);
  if (display) args.push('--display', String(display));
  if (pixels) args.push('--pixels');
  return runOCR(args);
});

const transport = new StdioServerTransport();
await server.connect(transport);
