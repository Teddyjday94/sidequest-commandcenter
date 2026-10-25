import type { StudioSnapshot } from '../types.js'
import { element, emptyState, formatTime } from '../lib/dom.js'
import { sortEvents } from '../lib/store.js'

export function liveLedger(snapshot: StudioSnapshot): HTMLElement {
  const section = element('section', 'live-ledger surface')
  section.setAttribute('aria-labelledby', 'ledger-title')
  const heading = element('div', 'section-heading inline-heading', [
    element('div', '', [element('p', 'eyebrow', ['Evidence trail']), element('h2', '', ['Live ledger'])]),
    element('p', 'section-note', ['Newest first']),
  ])
  heading.querySelector('h2')?.setAttribute('id', 'ledger-title')
  section.append(heading)
  if (snapshot.events.length === 0) {
    section.append(emptyState('No activity has been recorded.', 'Worker and approval events will appear here.'))
    return section
  }

  const list = element('ol', 'ledger-list')
  for (const event of sortEvents(snapshot.events)) {
    list.append(
      element('li', 'ledger-entry', [
        element('time', '', [formatTime(event.at)]),
        element('div', '', [
          element('p', 'ledger-summary', [event.summary]),
          element('p', 'ledger-meta', [`${event.event.replaceAll('_', ' ')} / ${event.actor}`]),
        ]),
      ]),
    )
  }
  section.append(list)
  return section
}
