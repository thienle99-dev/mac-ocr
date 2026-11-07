import { execFile } from 'node:child_process';
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
const binary = process.env.MAC_OCR_BIN || defaultBinary;
const defaultTimeout = 60_000;
const configuredTimeout = Number(process.env.MAC_OCR_TIMEOUT_MS);
const timeout = Number.isInteger(configuredTimeout) && configuredTimeout > 0
  ? configuredTimeout
  : defaultTimeout;
const timeoutConfigured = Number.isInteger(configuredTimeout) && configuredTimeout > 0;

const server = new McpServer({ name: 'mac-ocr', version: '1.0.0' });

async function runOCR(args: string[], processTimeout = timeout) {
  try {
    await access(binary, constants.X_OK);
  } catch {
    return { content: [{ type: 'text' as const, text: `mac-ocr binary not found at ${binary}. Run \`swift build -c release\` in the project root or set MAC_OCR_BIN.` }], isError: true };
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
    },
    annotations: readOnlyAnnotations,
  },
  async ({ path, languages, level }) => {
    return runOCR([path, ...commonArgs(languages, level)]);
  },
);

server.registerTool('ocr_pdf', {
  description: 'Recognize text in a PDF using Apple Vision. Optionally select a 1-based inclusive page range such as "1-3".',
  inputSchema: {
    path: z.string().min(1).describe('Path to a local PDF file'),
    pages: z.string().regex(/^\d+(-\d+)?$/).optional().describe('1-based page number or inclusive range, for example "2" or "1-3"'),
    languages: z.array(z.string().min(1)).optional().describe('Recognition languages, for example ["vi-VN", "en-US"]'),
    level: z.enum(['accurate', 'fast']).optional().describe('Recognition level'),
  },
  annotations: readOnlyAnnotations,
}, async ({ path, pages, languages, level }) => {
  const args = [path, ...commonArgs(languages, level)];
  if (pages) args.push('--pages', pages);
  const [first, last = first] = pages ? pages.split('-').map(Number) : [1];
  // Without `pages` the whole document is processed and its length is unknown, so allow 5x the default.
  const count = pages ? last - first + 1 : 5;
  return runOCR(args, timeoutConfigured ? timeout : defaultTimeout * Math.max(1, count));
});

server.registerTool('ocr_screen', {
  description: 'Capture the main display and recognize its text. The host app needs Screen Recording permission.',
  inputSchema: {
    languages: z.array(z.string().min(1)).optional().describe('Recognition languages, for example ["vi-VN", "en-US"]'),
    level: z.enum(['accurate', 'fast']).optional().describe('Recognition level'),
  },
  annotations: readOnlyAnnotations,
}, async ({ languages, level }) => runOCR(['--screen', ...commonArgs(languages, level)]));

const transport = new StdioServerTransport();
await server.connect(transport);
