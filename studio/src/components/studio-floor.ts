import type { AgentDTO, StudioSnapshot } from '../types.js'
import { button, element, emptyState, formatTime } from '../lib/dom.js'
import { agentStateLabel, isWorkerOffline, roomForAgent } from '../lib/store.js'

export function studioFloor(
  snapshot: StudioSnapshot,
  selectedAgentId: string | null,
  onSelect: (agent: AgentDTO) => void,
): HTMLElement {
  const section = element('section', 'studio-floor surface')
  section.setAttribute('aria-labelledby', 'floor-title')
  const heading = element('div', 'section-heading inline-heading', [
    element('div', '', [element('p', 'eyebrow', ['Live floor']), element('h2', '', ['Agent rooms'])]),
    element('p', 'section-note', [`${snapshot.agents.length} registered`]),
  ])
  heading.querySelector('h2')?.setAttribute('id', 'floor-title')
  section.append(heading)

  if (snapshot.agents.length === 0) {
    section.append(emptyState('No agents are registered.', 'Rooms will appear when the private snapshot reports an agent.'))
    return section
  }

  const floor = element('div', 'room-map')
  for (const agent of snapshot.agents) {
    const offline = isWorkerOffline(agent.lastHeartbeat, snapshot.serverTime)
    const room = element('article', `agent-room state-${offline ? 'offline' : agent.state}`)
    const select = button(agent.name, 'room-select')
    select.dataset.agentId = agent.id
    select.setAttribute('aria-pressed', String(agent.id === selectedAgentId))
    select.addEventListener('click', () => onSelect(agent))
    room.append(
      element('p', 'room-name', [roomForAgent(agent.id)]),
      select,
      element('p', 'agent-role', [agent.role]),
      element('div', 'agent-state-row', [
        element('span', 'state-label', [offline ? 'Offline' : agentStateLabel(agent.state)]),
        element('span', 'heartbeat-copy', [`Last signal ${formatTime(agent.lastHeartbeat)}`]),
      ]),
    )
    floor.append(room)
  }
  section.append(floor)
  return section
}
