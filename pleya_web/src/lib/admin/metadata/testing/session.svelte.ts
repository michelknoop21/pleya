import type { PleyaClient } from '../../../api/client';
class EditorSession {
  client = $state.raw<PleyaClient>(null!);
  canAdminister = $state(true);
  capabilities = $state({ metadata_overrides: true });
  me = $state({ id: 'admin' });
}
export const editorSession = new EditorSession();
