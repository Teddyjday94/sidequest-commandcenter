import { mountStudio } from './components/app-shell.js'
import { createStudioApi } from './lib/api.js'
import { createOwnerSessionManager } from './lib/owner-session.js'
import './styles.css'

const root = document.querySelector<HTMLElement>('#app')
if (!root) throw new Error('studio_root_missing')

const ownerSession = createOwnerSessionManager()
mountStudio(
  root,
  createStudioApi(() => sessionStorage.getItem('sidequest_owner_token') ?? ownerSession.accessToken()),
  ownerSession,
)
