import { errorResponse, HttpError, jsonResponse } from './_lib/http.js'
import { getAdminClient } from './_lib/supabase.js'
import { requireWorker, throwWorkerProcedureError, type WorkerAdminClient } from './_lib/worker-auth.js'
import { boundedWorkerPayload } from './_lib/worker-request.js'

interface Dependencies { admin?: WorkerAdminClient }

export function createWorkerOfferHandler(dependencies: Dependencies = {}) {
  return async function GET(request: Request): Promise<Response> {
    try {
      const admin = dependencies.admin ?? (getAdminClient() as unknown as WorkerAdminClient)
      const worker = await requireWorker(request, admin)
      const { data, error } = await admin.schema('ops').rpc('offer_job', { p_worker_id: worker.id })
      if (error) throwWorkerProcedureError(error)
      if (data === null) return new Response(null, { status: 204, headers: { 'cache-control': 'private, no-store' } })
      return jsonResponse(boundedWorkerPayload(data), 200, { 'cache-control': 'private, no-store' })
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('worker_offer_failed')
      return errorResponse(error)
    }
  }
}

export const GET = createWorkerOfferHandler()

