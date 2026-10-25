export type Child = Node | string | null | undefined | false

export function element<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className = '',
  children: Child[] = [],
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag)
  if (className) node.className = className
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue
    node.append(child instanceof Node ? child : document.createTextNode(child))
  }
  return node
}

export function textBlock(label: string, value: string, className = ''): HTMLElement {
  const wrapper = element('div', className)
  wrapper.append(element('span', 'meta-label', [label]), element('strong', '', [value]))
  return wrapper
}

export function button(label: string, className = '', type: 'button' | 'submit' = 'button'): HTMLButtonElement {
  const node = element('button', className, [label])
  node.type = type
  return node
}

export function emptyState(title: string, detail: string): HTMLElement {
  return element('div', 'empty-state', [element('p', 'eyebrow', ['Quiet state']), element('h3', '', [title]), element('p', '', [detail])])
}

export function formatTime(value: string | null): string {
  if (!value) return 'Not yet'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return 'Unknown'
  return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(date)
}
