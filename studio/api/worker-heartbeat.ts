import { errorResponse, HttpError, jsonResponse } from './_lib/http.js'
import { getAdminClient } from './_lib/supabase.js'
import { requireWorker, throwWorkerProcedureError, type WorkerAdminClient } from './_lib/worker-auth.js'
import { boundedWorkerPayload, readWorkerBody, workerJobId } from './_lib/worker-request.js'

interface Dependencies { admin?: WorkerAdminClient }

export function createWorkerHeartbeatHandler(dependencies: Dependencies = {}) {
  return async function POST(request: Request): Promise<Response> {
    try {
      const admin = dependencies.admin ?? (getAdminClient() as unknown as WorkerAdminClient)
      const worker = await requireWorker(request, admin)
      const jobId = workerJobId(await readWorkerBody(request))
      const { data, error } = await admin.schema('ops').rpc('heartbeat_job', {
        p_worker_id: worker.id,
        p_job_id: jobId,
      })
      if (error) throwWorkerProcedureError(error)
      return jsonResponse(boundedWorkerPayload(data), 200, { 'cache-control': 'private, no-store' })
    } catch (error) {
      if (!(error instanceof HttpError)) console.error('worker_heartbeat_failed')
      return errorResponse(error)
    }
  }
}

export const POST = createWorkerHeartbeatHandler()

