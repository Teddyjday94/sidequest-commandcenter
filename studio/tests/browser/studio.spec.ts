import { expect, test, type Page } from '@playwright/test'

function studioSnapshot() {
  return {
    serverTime: '2026-10-24T20:05:00.000Z',
    agents: [
      {
        id: 'finder', name: 'Contact Finder', role: 'Public business research', status: 'Live', state: 'working',
        health: 'healthy', modelTier: 'local', currentJobId: 'job-1', queueDepth: 1,
        lastHeartbeat: '2026-10-24T20:04:30.000Z', lastRun: null, lastResult: 'Qualified one lead',
      },
      {
        id: 'reviewer', name: 'Draft Reviewer', role: 'Internal quality review', status: 'Live', state: 'reviewing',
        health: 'healthy', modelTier: 'codex', currentJobId: null, queueDepth: 0,
        lastHeartbeat: '2026-10-24T20:04:50.000Z', lastRun: null, lastResult: null,
      },
    ],
    jobs: [
      {
        id: 'job-1', workflowId: 'workflow-1', leadId: null, agentId: 'finder', kind: 'research', status: 'running',
        priority: 20, confidence: null, attempts: 1, maxAttempts: 3, scheduledFor: null,
        lockedAt: '2026-10-24T20:04:00.000Z', lockOwner: 'native-worker', createdAt: null, updatedAt: null,
        completedAt: null, errorCode: null, errorSummary: null, isStateChanging: false,
      },
    ],
    approvals: [
      {
        id: 'approval-1', jobId: 'job-1', leadId: null, actionType: 'send_draft', title: 'Review welcome draft',
        risk: 'medium', status: 'pending', requestedAt: '2026-10-24T20:02:00.000Z', decidedAt: null,
        decisionNote: null, externalActionCompletedAt: null,
        preview: [
          { label: 'Recipient', value: 'owner@example.test' },
          { label: 'Subject', value: 'Website introduction' },
          { label: 'Draft', value: 'A bounded draft for review.' },
        ],
      },
    ],
    events: [
      { id: 1, jobId: 'job-1', at: '2026-10-24T20:01:00.000Z', event: 'queued', actor: 'system', summary: 'Research queued' },
      { id: 2, jobId: 'job-1', at: '2026-10-24T20:04:00.000Z', event: 'claimed', actor: 'native-worker', summary: 'Worker claimed job' },
    ],
    pipeline: [],
    heartbeats: [
      { agentId: 'finder', health: 'healthy', lastHeartbeat: '2026-10-24T20:04:30.000Z' },
      { agentId: 'reviewer', health: 'healthy', lastHeartbeat: '2026-10-24T20:04:50.000Z' },
    ],
    missions: [
      {
        id: 'weekday-research', name: 'Weekday research', agentId: 'finder', jobKind: 'research',
        cadenceMinutes: 1440, nextRunAt: '2026-10-25T14:00:00.000Z', enabled: true, priority: 20,
        maxAttempts: 3, lastDispatchedAt: null,
      },
    ],
    autonomy: {
      emergencyStop: false, dailyJobLimit: 12, maximumAttempts: 3, runtimeMinutes: 15,
      windowStart: '07:00', windowEnd: '20:00', timezone: 'America/Chicago',
    },
  }
}

async function mockStudio(page: Page) {
  let snapshot = studioSnapshot()
  const calls: Array<{ path: string; body: unknown }> = []
  await page.addInitScript(() => sessionStorage.setItem('sidequest_owner_token', 'browser-test-owner'))
  await page.route('**/api/**', async (route) => {
    const request = route.request()
    const path = new URL(request.url()).pathname
    if (path === '/api/snapshot') {
      await route.fulfill({ json: snapshot })
      return
    }
    const body = request.postDataJSON() as Record<string, unknown>
    calls.push({ path, body })
    if (path === '/api/approval-resolve') {
      snapshot = { ...snapshot, approvals: [] }
      await route.fulfill({ json: { id: body.approvalId, status: 'approved' } })
      return
    }
    if (path === '/api/emergency-stop') {
      snapshot = { ...snapshot, autonomy: { ...snapshot.autonomy, emergencyStop: body.enabled === true } }
      await route.fulfill({ json: { enabled: body.enabled } })
      return
    }
    if (path === '/api/mission-toggle') {
      snapshot = {
        ...snapshot,
        missions: snapshot.missions.map((mission) => mission.id === body.missionId ? { ...mission, enabled: body.enabled === true } : mission),
      }
      await route.fulfill({ json: { id: body.missionId, enabled: body.enabled } })
      return
    }
    await route.fulfill({ status: 404, json: { error: 'not_found' } })
  })
  return calls
}

test('keyboard navigation, workbench, ledger, approvals, and stop confirmation use live state', async ({ page }) => {
  const calls = await mockStudio(page)
  await page.goto('/')

  await expect(page.getByRole('heading', { name: 'What needs your attention' })).toBeVisible()
  await page.keyboard.press('Tab')
  await expect(page.getByRole('link', { name: 'Skip to command center' })).toBeFocused()

  await page.getByRole('button', { name: 'Draft Reviewer' }).click()
  await expect(page.locator('.workbench')).toBeFocused()
  await expect(page.locator('.workbench')).toContainText('Draft Reviewer')

  const events = page.locator('.ledger-entry .ledger-summary')
  await expect(events.nth(0)).toHaveText('Worker claimed job')
  await expect(events.nth(1)).toHaveText('Research queued')

  await expect(page.locator('.approval-item')).toContainText('owner@example.test')
  await expect(page.locator('.approval-item')).toContainText('A bounded draft for review.')
  await page.locator('.approval-item').getByRole('button', { name: 'Approve' }).click()
  await expect(page.getByText('No decisions are waiting.')).toBeVisible()
  expect(calls.some((call) => call.path === '/api/approval-resolve')).toBe(true)

  await page.getByRole('button', { name: 'Stop automation' }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toContainText('Stop all new automated work?')
  await dialog.getByRole('button', { name: 'Stop automation' }).click()
  await expect(page.getByText('Automation stopped', { exact: true }).first()).toBeVisible()
  await expect(page.getByRole('checkbox', { name: /Weekday research/ })).toBeDisabled()
  expect(calls.some((call) => call.path === '/api/emergency-stop' && (call.body as { enabled: boolean }).enabled)).toBe(true)
})

test('desktop rooms and workbench sit side-by-side', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1360, height: 900 })
  await mockStudio(page)
  await page.goto('/')

  const floor = await page.locator('.studio-floor').boundingBox()
  const workbench = await page.locator('.workbench').boundingBox()
  expect(floor).not.toBeNull()
  expect(workbench).not.toBeNull()
  expect(floor!.x + floor!.width).toBeLessThanOrEqual(workbench!.x + 2)
  await page.screenshot({ path: testInfo.outputPath('desktop-studio.png'), fullPage: true })
})

test('mobile reflows the workbench below rooms without horizontal clipping', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await mockStudio(page)
  await page.goto('/')

  const floor = await page.locator('.studio-floor').boundingBox()
  const workbench = await page.locator('.workbench').boundingBox()
  expect(workbench!.y).toBeGreaterThan(floor!.y + floor!.height - 2)
  const bodyWidth = await page.evaluate(() => document.body.scrollWidth)
  expect(bodyWidth).toBeLessThanOrEqual(390)
  await page.screenshot({ path: testInfo.outputPath('mobile-studio.png'), fullPage: true })
})
