# Run the crew through existing ChatGPT/Codex usage

This path uses the Codex CLI's **Sign in with ChatGPT** session. It does not require an OpenAI API key, an additional model subscription, or API credits.

## Billing guard

`runner/run-agent.ps1` runs a Codex Doctor preflight before every real run. It pins the built-in `openai` provider and `on-request` approval policy, then continues only when the effective configuration reports ChatGPT tokens, the OpenAI provider, the official ChatGPT endpoint, and human review enabled. It also refuses to run when `CODEX_API_KEY`, `OPENAI_API_KEY`, or `OPENAI_BASE_URL` is set. If authentication, routing, or approval behavior changes, the runner stops before starting an agent.

Verify the current login:

```powershell
codex login status
```

If needed, switch back to subscription access:

```powershell
codex logout
codex login
```

Complete the browser flow with the ChatGPT account that owns the intended plan.

## Preview the command without consuming a run

Dry-run prints the exact bounded Codex command but does not invoke a model. It is a command preview; real manual runs additionally check authentication, the effective provider, and required plugins.

```powershell
.\runner\run-agent.ps1 -Agent sales-agent -DryRun
```

## Run an agent manually

```powershell
.\runner\run-agent.ps1 -Agent contact-finder
.\runner\run-agent.ps1 -Agent sales-agent
.\runner\run-agent.ps1 -Agent mockup-builder
.\runner\run-agent.ps1 -Agent content-agent
```

Leave `-Model` out to use the account's current Codex default. To select another model already included and available to the signed-in account:

```powershell
.\runner\run-agent.ps1 -Agent content-agent -Model <available-codex-model>
```

The runner uses `workspace-write`, an ephemeral Codex session, and a structured output schema. It deliberately does not use automatic approval. Results are saved under `.codex-runs/`, which is intentionally ignored by Git. A fully blocked result exits with code `20`; a failed result exits with code `21`, so schedulers cannot report those runs as successful.

## Scheduling

Start with supervised manual runs. After the required plugins are connected and their write or destructive actions still require review, the preferred scheduler is the ChatGPT desktop app's **Scheduled** view because it keeps run history visible. Add this repository as a local project, create one scheduled task per file under `agents/codex/`, and retain these Central Time schedules:

| Agent | Schedule |
|---|---|
| Contact Finder | Monday, Wednesday, Friday at 8:07 AM |
| Sales Agent | Weekdays at 9:17 AM |
| Mockup Builder | Tuesday and Thursday at 8:33 AM |
| Content Agent | Sunday at 5:43 PM |

Keep the PC on and the ChatGPT desktop app running for local scheduled tasks. Test every prompt manually before enabling its schedule. Do not grant blanket approval to sending, invoice finalization, unrestricted SQL, or non-`mockup-*` Vercel actions. A scheduled run should fail safely when an action still needs human approval. Disable the corresponding Claude task only after its first Codex run has been reviewed, preventing duplicate drafts or deployments.

## Connections

The agents use existing connected tools rather than secrets committed to this repository. Open Codex, run `/plugins`, install the required free plugin packages, and complete each service's connection flow. Installing a plugin does not authorize actions by itself; review the requested service permissions.

- Supabase is required for every live agent run. The runner stops before invoking a model when it is not installed and enabled.
- Browser or web search is required by Contact Finder.
- Gmail is required for Sales Agent email drafts and reply checks. The runner stops before invoking Sales Agent when it is not installed and enabled.
- Stripe is optional and limited to customers and draft invoices.
- Vercel is required only when Mockup Builder deploys a `mockup-*` project.

The current machine must complete the Supabase and Gmail plugin setup before the live agents can run. When an optional connection is missing, the agent must report the blocked portion and continue only with safe independent work. It must never buy an API plan or fall back to a paid key.

These connection rules apply to the older supervised `run-agent.ps1` path. The guarded queue worker uses no connected plugins: the broker supplies and stores database data, Sales produces a reviewable draft artifact without Gmail access, and Contact Finder alone may use native read-only web search.
