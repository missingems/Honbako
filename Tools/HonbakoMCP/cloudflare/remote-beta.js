import { remoteFetch } from './remote/worker.js';
import { reply } from './core.js';
export { HonbakoAuthorization, HonbakoWorkspace } from './remote/worker.js';

// Apple test purchases have their own deployment, keys and storage namespaces.
// This entry never exposes the existing owner pilot or accepts production Pro.
export default {
  fetch(request, env) {
    if (env.APP_STORE_ENVIRONMENT !== 'Sandbox')
      return reply(503, { error: { code: 'beta_not_configured', message: 'Remote beta purchase verification is not configured' } });
    const path = new URL(request.url).pathname;
    if (path === '/remote' || path.startsWith('/remote/') || path.startsWith('/.well-known/'))
      return remoteFetch(request, env);
    return reply(404, { error: { code: 'not_found', message: 'Endpoint not found' } });
  }
};
