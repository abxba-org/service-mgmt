import { test, expect } from '@playwright/test';

const TEST_URLS = [
  { name: 'local-dashboard-vault', url: 'http://127.0.0.1:8080' },
  { name: 'local-agent-vault', url: 'http://127.0.0.1:14321' },
  { name: 'tailscale-dashboard', url: 'https://vps-ovh8.tail95f2ee.ts.net/' },
  { name: 'tailscale-vault-home', url: 'https://vps-ovh8.tail95f2ee.ts.net/vault' },
  { name: 'tailscale-agent-vault', url: 'https://vps-ovh8.tail95f2ee.ts.net/agent-vault' },
];

for (const { name, url } of TEST_URLS) {
  test(`${name} - ${url}`, async ({ page }) => {
    const response = await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
    
    const status = response?.status() ?? 0;
    const title = await page.title();
    const content = await page.textContent('body');
    const contentLength = content?.length ?? 0;
    
    console.log(`${name} (${url}) - Status: ${status} - Title: "${title}" - Content: ${contentLength} chars`);
    
    await expect(response).not.toBeNull();
    expect(status).toBeGreaterThanOrEqual(200);
    expect(status).toBeLessThan(400);
    expect(title.length).toBeGreaterThan(0);
    expect(contentLength).toBeGreaterThan(0);
    
    await page.screenshot({ path: `screenshots/${name.replace(/\//g, '-')}.png`, fullPage: true });
  });
}