const { chromium } = require('playwright');

const BASE_URL = 'https://vps-ovh8.tail95f2ee.ts.net';
const PATHS = ['/', '/vault', '/agent-vault'];

async function testUrl(page, url) {
  try {
    const response = await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
    const status = response.status();
    const title = await page.title();
    const content = await page.textContent('body');
    return { url, status, title, success: status >= 200 && status < 400, contentLength: content.length };
  } catch (error) {
    return { url, status: 'ERROR', title: '', success: false, error: error.message };
  }
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  
  console.log('Testing URLs...\n');
  
  for (const path of PATHS) {
    const url = `${BASE_URL}${path}`;
    const result = await testUrl(page, url);
    
    if (result.success) {
      console.log(`✓ ${result.url} - Status: ${result.status} - Title: "${result.title}" - Content: ${result.contentLength} chars`);
    } else {
      console.log(`✗ ${result.url} - Status: ${result.status} - Error: ${result.error || 'Failed'}`);
    }
  }
  
  await browser.close();
  console.log('\nDone.');
}

main().catch(console.error);