// Playwright automation for EduVPN OAuth/Shibboleth login
// Handles: InCommon WAYF → IdP login → OAuth callback
//
// Environment variables:
//   AUTH_URL  — OAuth authorize URL from eduvpn-cli
//   IDP_USER  — IdP username
//   IDP_PASS  — IdP password
//   IDP_NAME  — Organization name for WAYF (default: "Florida State University")

const { chromium } = require('playwright');

const AUTH_URL = process.env.AUTH_URL;
const IDP_USER = process.env.IDP_USER;
const IDP_PASS = process.env.IDP_PASS;
const IDP_NAME = process.env.IDP_NAME || 'Florida State University';

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
    page.setDefaultTimeout(20000);

    try {
        console.log('[eduvpn-auth] Navigating to auth URL...');
        await page.goto(AUTH_URL, { waitUntil: 'networkidle', timeout: 30000 });

        // ─── Stage 1: InCommon WAYF (federation discovery) ──────────
        const url = page.url();
        if (url.includes('wayf') || url.includes('DS/WAYF') || url.includes('discovery')) {
            console.log('[eduvpn-auth] WAYF page detected — selecting organization...');

            // Select organization from dropdown (select[name="user_idp"])
            const selectEl = await page.$('select[name="user_idp"]');
            if (selectEl) {
                // Find matching option by partial text
                const matchValue = await page.evaluate((name) => {
                    const sel = document.querySelector('select[name="user_idp"]');
                    const opt = [...sel.options].find(o => o.text.includes(name));
                    return opt ? opt.value : null;
                }, IDP_NAME);

                if (!matchValue) throw new Error(`Organization "${IDP_NAME}" not found in WAYF`);
                // Use evaluate to set the value directly (bypasses visibility checks)
                await page.evaluate((val) => {
                    const sel = document.querySelector('select[name="user_idp"]');
                    sel.value = val;
                    sel.dispatchEvent(new Event('change', { bubbles: true }));
                }, matchValue);
                console.log(`[eduvpn-auth] Selected: ${IDP_NAME}`);
            } else {
                // Fallback: text input
                const input = await page.$('input[type="text"]');
                if (input) {
                    await input.fill(IDP_NAME);
                    await page.waitForTimeout(1000);
                }
            }

            // Submit form and wait for navigation
            console.log('[eduvpn-auth] Submitting WAYF form...');
            await Promise.all([
                page.waitForNavigation({ waitUntil: 'networkidle', timeout: 30000 }),
                page.evaluate(() => document.getElementById('IdPList').submit()),
            ]);
        }

        // ─── Stage 2: IdP Login (Shibboleth/SAML) ──────────────────
        const loginUrl = page.url();
        console.log(`[eduvpn-auth] At: ${loginUrl.substring(0, 80)}...`);

        // Find username field — try common selectors
        const usernameSelector = await Promise.race([
            page.waitForSelector('input[name="j_username"]', { timeout: 10000 }).then(() => 'input[name="j_username"]'),
            page.waitForSelector('input[name="username"]', { timeout: 10000 }).then(() => 'input[name="username"]'),
            page.waitForSelector('input[name="login"]', { timeout: 10000 }).then(() => 'input[name="login"]'),
            page.waitForSelector('input[type="email"]', { timeout: 10000 }).then(() => 'input[type="email"]'),
            page.waitForSelector('#username', { timeout: 10000 }).then(() => '#username'),
        ]);

        console.log(`[eduvpn-auth] Found login field: ${usernameSelector}`);
        await page.fill(usernameSelector, IDP_USER);

        // Find password field
        const passwordSelector = await Promise.race([
            page.waitForSelector('input[name="j_password"]', { timeout: 5000 }).then(() => 'input[name="j_password"]'),
            page.waitForSelector('input[name="password"]', { timeout: 5000 }).then(() => 'input[name="password"]'),
            page.waitForSelector('input[type="password"]', { timeout: 5000 }).then(() => 'input[type="password"]'),
        ]);

        console.log(`[eduvpn-auth] Found password field: ${passwordSelector}`);
        await page.fill(passwordSelector, IDP_PASS);

        // Submit
        const submitSelector = await Promise.race([
            page.waitForSelector('button[type="submit"]', { timeout: 5000 }).then(() => 'button[type="submit"]'),
            page.waitForSelector('input[type="submit"]', { timeout: 5000 }).then(() => 'input[type="submit"]'),
        ]);

        console.log('[eduvpn-auth] Submitting credentials...');
        await page.click(submitSelector);
        await page.waitForTimeout(3000);

        // ─── Stage 3: Duo MFA ─────────────────────────────────────────
        const postLoginUrl = page.url();
        if (postLoginUrl.includes('duosecurity') || postLoginUrl.includes('duo')) {
            console.log('[eduvpn-auth] Duo MFA detected — waiting for push approval...');

            // Wait up to 60s for Duo push to be approved
            // After approval, Duo shows "Is this your device?" or redirects
            for (let i = 0; i < 60; i++) {
                const curUrl = page.url();
                // Check if we've left Duo entirely
                if (!curUrl.includes('duo')) break;

                // Look for "Yes, this is my device" button and click it
                try {
                    const trustBtn = await page.$('button:has-text("Yes, this is my device")');
                    if (trustBtn) {
                        console.log('[eduvpn-auth] Clicking "Yes, this is my device"...');
                        await trustBtn.click();
                        await page.waitForTimeout(3000);
                        break;
                    }
                } catch { /* not yet */ }

                await page.waitForTimeout(1000);
            }

            // Wait for redirect back from Duo
            console.log('[eduvpn-auth] Waiting for redirect after Duo...');
            for (let i = 0; i < 30; i++) {
                const curUrl = page.url();
                if (curUrl.includes('127.0.0.1') || curUrl.includes('localhost') || curUrl.includes('callback')) {
                    break;
                }
                if (!curUrl.includes('duo')) {
                    // We left Duo — might be on consent page or callback
                    break;
                }
                await page.waitForTimeout(1000);
            }
        }

        // ─── Stage 4: Attribute Consent / Approve page ────────────────
        // CAS may show "Attribute Consent" asking to send info to the SP
        await page.waitForTimeout(2000);
        for (let attempt = 0; attempt < 3; attempt++) {
            try {
                const consentBtn = await page.$('button:has-text("Continue"), a:has-text("Continue"), button:has-text("Approve"), button:has-text("Allow"), button:has-text("Accept"), input[value="Continue"], input[value="Approve"], input[value="Allow"]');
                if (consentBtn) {
                    console.log('[eduvpn-auth] Consent/approve page — clicking Continue...');
                    await Promise.all([
                        page.waitForNavigation({ waitUntil: 'networkidle', timeout: 30000 }).catch(() => {}),
                        consentBtn.click(),
                    ]);
                    await page.waitForTimeout(2000);
                } else {
                    break;
                }
            } catch {
                break;
            }
        }

        // ─── Stage 5: Check result ──────────────────────────────────
        const finalUrl = page.url();
        if (finalUrl.includes('127.0.0.1') || finalUrl.includes('localhost') || finalUrl.includes('callback')) {
            console.log('[eduvpn-auth] SUCCESS — OAuth callback completed');
        } else if (finalUrl.includes('error') || finalUrl.includes('denied')) {
            await page.screenshot({ path: '/tmp/eduvpn-auth-debug.png' });
            console.error(`[eduvpn-auth] Auth may have failed. Final URL: ${finalUrl}`);
            console.error('[eduvpn-auth] Debug screenshot: /tmp/eduvpn-auth-debug.png');
        } else {
            // Might be a post-login redirect still in progress
            console.log(`[eduvpn-auth] Ended at: ${finalUrl.substring(0, 80)}`);
            // Wait a bit more for final redirect
            try {
                await page.waitForURL('**/callback*', { timeout: 10000 });
                console.log('[eduvpn-auth] SUCCESS — callback received after wait');
            } catch {
                await page.screenshot({ path: '/tmp/eduvpn-auth-debug.png' });
                console.log('[eduvpn-auth] Final screenshot saved. eduvpn-cli may still complete via form_post.');
            }
        }

    } catch (err) {
        const url = page.url();
        if (url.includes('127.0.0.1') || url.includes('localhost')) {
            console.log('[eduvpn-auth] SUCCESS — at callback despite error');
        } else {
            await page.screenshot({ path: '/tmp/eduvpn-auth-debug.png' });
            console.error(`[eduvpn-auth] ERROR: ${err.message}`);
            console.error(`[eduvpn-auth] URL: ${url}`);
            console.error('[eduvpn-auth] Debug screenshot: /tmp/eduvpn-auth-debug.png');
            await browser.close();
            process.exit(1);
        }
    }

    await browser.close();
    console.log('[eduvpn-auth] Done');
})();
