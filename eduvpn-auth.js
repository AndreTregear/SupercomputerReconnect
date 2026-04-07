// Playwright automation for EduVPN OAuth/Shibboleth login
// Usage: npx playwright test eduvpn-auth.js (or node with playwright runner)
//   AUTH_URL=<url> IDP_USER=<user> IDP_PASS=<pass> npx playwright test eduvpn-auth.js
//
// Handles UF Shibboleth flow: auth URL → IdP login → callback to localhost

const { chromium } = require('playwright');

const AUTH_URL = process.env.AUTH_URL;
const IDP_USER = process.env.IDP_USER;
const IDP_PASS = process.env.IDP_PASS;

if (!AUTH_URL || !IDP_USER || !IDP_PASS) {
    console.error('Missing environment variables: AUTH_URL, IDP_USER, IDP_PASS');
    process.exit(1);
}

(async () => {
    const browser = await chromium.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-gpu'],
    });
    const page = await browser.newPage();

    console.log('[eduvpn-auth] Navigating to auth URL...');
    await page.goto(AUTH_URL, { waitUntil: 'networkidle', timeout: 30000 });

    // The flow may go through several redirects:
    // 1. eduVPN portal → Shibboleth IdP selection
    // 2. IdP login page (username/password)
    // 3. Possibly a consent/approve page
    // 4. Redirect back to localhost callback

    try {
        // Wait for a login form to appear — try common selectors
        // UF uses Shibboleth which typically has username/password fields
        const usernameSelector = await Promise.race([
            page.waitForSelector('input[name="j_username"]', { timeout: 15000 }).then(() => 'input[name="j_username"]'),
            page.waitForSelector('input[name="username"]', { timeout: 15000 }).then(() => 'input[name="username"]'),
            page.waitForSelector('input[name="login"]', { timeout: 15000 }).then(() => 'input[name="login"]'),
            page.waitForSelector('input[type="email"]', { timeout: 15000 }).then(() => 'input[type="email"]'),
            page.waitForSelector('#username', { timeout: 15000 }).then(() => '#username'),
        ]);

        console.log(`[eduvpn-auth] Found login field: ${usernameSelector}`);
        await page.fill(usernameSelector, IDP_USER);

        // Find and fill password
        const passwordSelector = await Promise.race([
            page.waitForSelector('input[name="j_password"]', { timeout: 5000 }).then(() => 'input[name="j_password"]'),
            page.waitForSelector('input[name="password"]', { timeout: 5000 }).then(() => 'input[name="password"]'),
            page.waitForSelector('input[type="password"]', { timeout: 5000 }).then(() => 'input[type="password"]'),
            page.waitForSelector('#password', { timeout: 5000 }).then(() => '#password'),
        ]);

        console.log(`[eduvpn-auth] Found password field: ${passwordSelector}`);
        await page.fill(passwordSelector, IDP_PASS);

        // Submit the form
        const submitSelector = await Promise.race([
            page.waitForSelector('button[type="submit"]', { timeout: 5000 }).then(() => 'button[type="submit"]'),
            page.waitForSelector('input[type="submit"]', { timeout: 5000 }).then(() => 'input[type="submit"]'),
            page.waitForSelector('.btn-submit', { timeout: 5000 }).then(() => '.btn-submit'),
            page.waitForSelector('#submit', { timeout: 5000 }).then(() => '#submit'),
        ]);

        console.log('[eduvpn-auth] Submitting login...');
        await page.click(submitSelector);

        // Wait for redirect — might hit an approval page or go straight to callback
        await page.waitForTimeout(3000);

        // Check if there's an approve/authorize button (eduVPN OAuth consent)
        try {
            const approveBtn = await page.waitForSelector(
                'button:has-text("Approve"), button:has-text("Allow"), button:has-text("Accept"), input[value="Approve"], input[value="Allow"]',
                { timeout: 5000 }
            );
            if (approveBtn) {
                console.log('[eduvpn-auth] Clicking approve button...');
                await approveBtn.click();
                await page.waitForTimeout(2000);
            }
        } catch {
            // No approve button — that's fine, might auto-approve
        }

        // Check if we landed on localhost callback (success)
        const finalUrl = page.url();
        if (finalUrl.includes('127.0.0.1') || finalUrl.includes('localhost')) {
            console.log('[eduvpn-auth] SUCCESS — callback received');
        } else {
            // Take a screenshot for debugging
            await page.screenshot({ path: '/tmp/eduvpn-auth-debug.png' });
            console.log(`[eduvpn-auth] Ended at: ${finalUrl}`);
            console.log('[eduvpn-auth] Debug screenshot saved to /tmp/eduvpn-auth-debug.png');
        }

    } catch (err) {
        // Maybe we're already at callback (no login needed), or something unexpected
        const url = page.url();
        if (url.includes('127.0.0.1') || url.includes('localhost')) {
            console.log('[eduvpn-auth] SUCCESS — already at callback (no login needed)');
        } else {
            await page.screenshot({ path: '/tmp/eduvpn-auth-debug.png' });
            console.error(`[eduvpn-auth] ERROR: ${err.message}`);
            console.error(`[eduvpn-auth] Current URL: ${url}`);
            console.error('[eduvpn-auth] Debug screenshot: /tmp/eduvpn-auth-debug.png');
            await browser.close();
            process.exit(1);
        }
    }

    await browser.close();
    console.log('[eduvpn-auth] Done');
})();
