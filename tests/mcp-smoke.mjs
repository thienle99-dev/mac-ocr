import { Client } from '../mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StdioClientTransport } from '../mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js';

const [serverPath, imagePath, pdfPath, textPDFPath] = process.argv.slice(2);
const transport = new StdioClientTransport({ command: process.execPath, args: [serverPath] });
const client = new Client({ name: 'mac-ocr-smoke', version: '1.0.0' });
try {
  await client.connect(transport);
  const { tools } = await client.listTools();
  for (const name of ['ocr_image', 'ocr_images', 'ocr_pdf', 'ocr_screen', 'list_displays']) {
    if (!tools.some(tool => tool.name === name)) throw new Error(`missing tool ${name}`);
  }
  const pdf = tools.find(tool => tool.name === 'ocr_pdf');
  if (!pdf.inputSchema.properties.pages) throw new Error('ocr_pdf.pages schema missing');
  if (!pdf.inputSchema.properties.forceOCR) throw new Error('ocr_pdf.forceOCR schema missing');
  for (const name of ['ocr_image', 'ocr_images', 'ocr_pdf', 'ocr_screen']) {
    if (!tools.find(tool => tool.name === name).inputSchema.properties.pixels) throw new Error(`${name}.pixels schema missing`);
  }
  const pdfResult = await client.callTool({ name: 'ocr_pdf', arguments: { path: pdfPath, pages: '2' } });
  if (!pdfResult.isError || !JSON.stringify(pdfResult.content).includes('out of range')) {
    throw new Error('ocr_pdf.pages="2" was not accepted and validated by OCR');
  }
  const embeddedPDF = await client.callTool({ name: 'ocr_pdf', arguments: { path: textPDFPath } });
  const embeddedOutput = JSON.parse(embeddedPDF.content.find(item => item.type === 'text')?.text ?? '{}');
  if (embeddedPDF.isError || embeddedOutput.pages?.[0]?.source !== 'pdf-text') {
    throw new Error(`ocr_pdf did not use embedded text: ${JSON.stringify(embeddedPDF.content)}`);
  }
  const forcedPDF = await client.callTool({ name: 'ocr_pdf', arguments: { path: textPDFPath, forceOCR: true, languages: ['en-US'] } });
  const forcedOutput = JSON.parse(forcedPDF.content.find(item => item.type === 'text')?.text ?? '{}');
  if (forcedPDF.isError || forcedOutput.pages?.[0]?.source !== 'vision') {
    throw new Error(`ocr_pdf forceOCR failed: ${JSON.stringify(forcedPDF.content)}`);
  }
  const result = await client.callTool({ name: 'ocr_image', arguments: { path: imagePath, languages: ['en-US'] } });
  if (result.isError) throw new Error(JSON.stringify(result.content));
  const displays = await client.callTool({ name: 'list_displays', arguments: {} });
  if (displays.isError) throw new Error(JSON.stringify(displays.content));
  const batch = await client.callTool({ name: 'ocr_images', arguments: { paths: [imagePath, imagePath], languages: ['en-US'] } });
  const batchOutput = JSON.parse(batch.content.find(item => item.type === 'text')?.text ?? '{}');
  if (batch.isError || batchOutput.results?.length !== 2 || batchOutput.results[0].path !== imagePath) {
    throw new Error(`ocr_images failed: ${JSON.stringify(batch.content)}`);
  }
  console.log('PASS: MCP initialize, tools/list, PDF text layer/forceOCR, pages="2", tools/call, and batch OCR');
} finally {
  await transport.close();
}
