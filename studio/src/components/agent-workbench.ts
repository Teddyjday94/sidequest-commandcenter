import type { AgentDTO, StudioSnapshot } from '../types.js'
import { element, emptyState, formatTime, textBlock } from '../lib/dom.js'
import { agentStateLabel, roomForAgent } from '../lib/store.js'

export function agentWorkbench(snapshot: StudioSnapshot, agent: AgentDTO | null): HTMLElement {
  const aside = element('aside', 'workbench surface')
  aside.tabIndex = -1
  aside.setAttribute('aria-labelledby', 'workbench-title')
  const heading = element('div', 'section-heading', [
    element('p', 'eyebrow', ['Anchored workbench']),
    element('h2', '', ['Agent detail']),
  ])
  heading.querySelector('h2')?.setAttribute('id', 'workbench-title')
  aside.append(heading)
  if (!agent) {
    aside.append(emptyState('Select an agent.', 'The workbench shows only reported state and assigned work.'))
    return aside
  }

  const job = snapshot.jobs.find((candidate) => candidate.id === agent.currentJobId) ?? null
  aside.append(
    element('div', 'workbench-identity', [
      element('p', 'room-name', [roomForAgent(agent.id)]),
      element('h3', '', [agent.name]),
      element('p', 'agent-role', [agent.role]),
    ]),
    element('div', 'workbench-facts', [
      textBlock('State', agentStateLabel(agent.state)),
      textBlock('Health', agent.health),
      textBlock('Model route', agent.modelTier),
      textBlock('Queue', String(agent.queueDepth)),
      textBlock('Last heartbeat', formatTime(agent.lastHeartbeat)),
      textBlock('Last result', agent.lastResult ?? 'No result reported'),
    ]),
    job
      ? element('div', 'current-job', [
          element('p', 'eyebrow', ['Current job']),
          element('h4', '', [job.kind.replaceAll('_', ' ')]),
          element('p', '', [`${job.status} · attempt ${job.attempts} of ${job.maxAttempts}`]),
        ])
      : element('p', 'quiet-note', ['No current job is assigned.']),
  )
  return aside
}
