import puppeteer from 'puppeteer';

const WAIT_MS = 3000;

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  if (!command) { die('No command specified'); return; }

  let result;
  switch (command) {
    case 'screenshot':
      result = await screenshot(rest[0], rest[1]);
      break;
    case 'extract':
      result = await extractText(rest[0], rest[1]);
      break;
    case 'click':
      result = await clickElement(rest[0], rest[1]);
      break;
    case 'fill':
      result = await fillForm(rest[0], JSON.parse(rest[1] || '{}'));
      break;
    default:
      die(`Unknown command: ${command}`);
  }

  process.stdout.write(JSON.stringify(result));
}

async function screenshot(url, selector) {
  const browser = await puppeteer.launch({ headless: 'new' });
  try {
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    await page.setViewport({ width: 1280, height: 800 });

    if (selector) {
      await page.waitForSelector(selector, { timeout: 10000 });
    }

    await autoScroll(page);
    const base64 = await page.screenshot({ encoding: 'base64', fullPage: !!selector });
    return { ok: true, data: base64, format: 'base64' };
  } finally {
    await browser.close();
  }
}

async function extractText(url, selector) {
  const browser = await puppeteer.launch({ headless: 'new' });
  try {
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });

    if (selector) {
      await page.waitForSelector(selector, { timeout: 10000 });
      const text = await page.$eval(selector, el => el.innerText);
      return { ok: true, text, url, selector };
    } else {
      const text = await page.evaluate(() => document.body.innerText);
      const title = await page.title();
      return { ok: true, text: text.slice(0, 50000), title, url };
    }
  } finally {
    await browser.close();
  }
}

async function clickElement(url, selector) {
  const browser = await puppeteer.launch({ headless: 'new' });
  try {
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    await page.waitForSelector(selector, { timeout: 10000 });
    await page.click(selector);
    await page.waitForTimeout(WAIT_MS);
    const base64 = await page.screenshot({ encoding: 'base64' });
    return { ok: true, data: base64, format: 'base64', action: 'click', selector };
  } finally {
    await browser.close();
  }
}

async function fillForm(url, fields) {
  const browser = await puppeteer.launch({ headless: 'new' });
  try {
    const page = await browser.newPage();
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });

    for (const [sel, value] of Object.entries(fields)) {
      await page.waitForSelector(sel, { timeout: 10000 });
      await page.type(sel, String(value), { delay: 50 });
    }

    const base64 = await page.screenshot({ encoding: 'base64' });
    return { ok: true, data: base64, format: 'base64', action: 'fill_form', fields: Object.keys(fields) };
  } finally {
    await browser.close();
  }
}

async function autoScroll(page) {
  await page.evaluate(async () => {
    await new Promise(resolve => {
      let total = 0;
      const dist = 500;
      const timer = setInterval(() => {
        window.scrollBy(0, dist);
        total += dist;
        if (total >= document.body.scrollHeight) {
          clearInterval(timer);
          resolve();
        }
      }, 100);
    });
  });
}

function die(msg) {
  process.stdout.write(JSON.stringify({ ok: false, error: msg }));
  process.exit(1);
}

main().catch(err => die(err.message));
