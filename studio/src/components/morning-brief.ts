import type { StudioSnapshot } from '../types.js'
import { element } from '../lib/dom.js'
import { prioritizeBrief } from '../lib/store.js'

export function morningBrief(snapshot: StudioSnapshot): HTMLElement {
  const section = element('section', 'morning-brief')
  section.setAttribute('aria-labelledby', 'brief-title')
  const heading = element('div', 'section-heading', [
    element('p', 'eyebrow', ['Owner brief / live']),
    element('h1', '', ['What needs your attention']),
  ])
  heading.querySelector('h1')?.setAttribute('id', 'brief-title')
  section.append(heading)

  const list = element('ol', 'brief-list')
  for (const [index, item] of prioritizeBrief(snapshot).entries()) {
    const entry = element('li', `brief-item brief-${item.kind}`, [
      element('span', 'brief-index', [String(index + 1).padStart(2, '0')]),
      element('div', '', [
        element('p', 'eyebrow', [item.eyebrow]),
        element('h2', '', [item.title]),
        element('p', 'brief-detail', [item.detail]),
      ]),
    ])
    list.append(entry)
  }
  section.append(list)
  return section
}
