import { mountStudio } from './components/app-shell.js'
import { createStudioApi } from './lib/api.js'
import './styles.css'

const root = document.querySelector<HTMLElement>('#app')
if (!root) throw new Error('studio_root_missing')

mountStudio(root, createStudioApi())
