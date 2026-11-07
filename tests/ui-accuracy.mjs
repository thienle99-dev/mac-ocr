// Run with: ego-browser nodejs < tests/ui-accuracy.mjs
const fs = await import('node:fs/promises');
const output = '/private/tmp/mac-ocr-ui-accuracy';
await fs.mkdir(output, { recursive: true });
const task = await taskSpace('mac-ocr UI accuracy');
const page = task.page('p1');
console.log({ spaceId: task.spaceId, output });
const samples = [];
for (const dark of [false, true]) {
  for (const font of [12, 14, 16]) {
    for (const scale of [1, 2]) {
      await page.cdp('Emulation.setDeviceMetricsOverride', {
        width: 1000, height: 720, deviceScaleFactor: scale, mobile: false,
      });
      const html = `<!doctype html><meta charset="utf-8"><style>
        *{box-sizing:border-box}body{margin:0;padding:32px;font:${font}px Arial;background:${dark?'#151820':'#f1f4f8'};color:${dark?'#f1f5fa':'#152032'}}
        main{width:640px;padding:24px;border:1px solid #788391;border-radius:12px;background:${dark?'#222733':'#fff'}}
        p{margin:0 0 12px}span{display:inline-block}h1{font-size:24px;margin:0 0 20px}button{font:inherit;padding:8px 20px;margin-right:16px}
        .error{color:${dark?'#ffb0b0':'#a31515'}}.muted{color:${dark?'#707986':'#9099a3'}}
        .row{display:flex;justify-content:space-between;margin-bottom:12px}.clip{width:90px;overflow:hidden;white-space:nowrap}
      </style><main>
        <h1><span data-ocr>Account settings</span></h1>
        <p><span data-ocr>Hồ sơ người dùng</span></p>
        <p><span data-ocr>Nguyễn Thị Minh Anh</span></p>
        <p><span data-ocr>demo@example.test</span></p>
        <p class="error" role="alert"><span data-ocr>Không thể lưu thay đổi</span></p>
        <p class="error"><span data-ocr>Email address is invalid</span></p>
        <p><span data-ocr>Request failed: HTTP 422</span></p>
        <p><span data-ocr>Mã lỗi: ERR_VALIDATION_01</span></p>
        <div class="row"><span data-ocr>5h 37% used</span><span data-ocr>Week 67% used</span></div>
        <div class="row"><span data-ocr>Subtotal</span><span data-ocr>$1,240.50</span></div>
        <p class="muted"><span data-ocr>Usage unavailable</span></p>
        <p class="clip" data-bug="clipped-text">Thanh toán và quản lý hóa đơn</p>
        <button disabled><span data-ocr>Save changes</span></button><button><span data-ocr>Cancel</span></button>
      </main>`;
      await page.goto('data:text/html;charset=utf-8,' + encodeURIComponent(html));
      const reference = await page.evaluate(() => ({
        width: innerWidth, height: innerHeight, scale: devicePixelRatio,
        labels: [...document.querySelectorAll('[data-ocr]')].map(el => {
          const r = el.getBoundingClientRect();
          return { text: el.textContent, x:r.x, y:r.y, width:r.width, height:r.height };
        }),
        bugs: {
          clipping: document.querySelector('[data-bug]').scrollWidth > document.querySelector('[data-bug]').clientWidth,
          saveDisabled: document.querySelector('button').disabled,
          validationError: document.querySelector('[role=alert]').textContent,
        },
      }));
      const name = `${dark?'dark':'light'}-${font}px-${scale}x`;
      // The screenshot helper normalizes to CSS pixels. CDP preserves device resolution.
      const shot = await page.cdp('Page.captureScreenshot', {format:'png', fromSurface:true});
      await fs.writeFile(`${output}/${name}.png`, Buffer.from(shot.data, 'base64'));
      samples.push({name, ...reference});
    }
  }
}
await fs.writeFile(`${output}/references.json`, JSON.stringify(samples, null, 2));
console.log({samples:samples.length, labels:samples.reduce((n,s)=>n+s.labels.length,0)});
await task.finish({keep:[]});
