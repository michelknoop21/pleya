/**
 * De gebruikersroutes van het beheer (S10.4, schermen 26 en 27), in een eigen
 * bestand zodat `admin.ts` er niet bij groeit.
 *
 * Het contract kent geen `GET /users/{id}` en geen leesroute voor de
 * bibliotheekrechten van een gebruiker: `PUT /users/{id}/permissions` schrijft,
 * en antwoordt met de nu geldende lijst. Een client kan de huidige rechten dus
 * pas na een eigen schrijfactie zien. De schermen gaan daar eerlijk mee om.
 */
import type { components } from './schema';
import type { PleyaClient } from './client';
import type { User } from './types';

type S = components['schemas'];

export type Permission = S['Permission'];
export type LibraryPermission = S['LibraryPermission'];
export type CreateUserRequest = S['CreateUserRequest'];
export type UpdateUserRequest = S['UpdateUserRequest'];
export type UserSession = S['Session'];

export function adminUsersApi(client: PleyaClient) {
  return {
    createUser: (body: CreateUserRequest): Promise<User> =>
      client.request((raw) => raw.POST('/users', { body })),

    updateUser: (id: string, body: UpdateUserRequest): Promise<User> =>
      client.request((raw) =>
        raw.PATCH('/users/{id}', { params: { path: { id } }, body })
      ),

    deleteUser: (id: string): Promise<true> =>
      client.request<true>(async (raw) => {
        const result = await raw.DELETE('/users/{id}', { params: { path: { id } } });
        return result.response.ok
          ? { data: true, response: result.response }
          : { error: result.error, response: result.response };
      }),

    /** Vervangt de volledige rechtenlijst; het antwoord is de nu geldende lijst. */
    setPermissions: async (id: string, permissions: LibraryPermission[]): Promise<LibraryPermission[]> =>
      (
        await client.request((raw) =>
          raw.PUT('/users/{id}/permissions', { params: { path: { id } }, body: { permissions } })
        )
      ).items,

    sessionsOf: async (userId: string, signal?: AbortSignal): Promise<UserSession[]> =>
      (
        await client.request((raw) =>
          raw.GET('/sessions', { params: { query: { user_id: userId } }, signal })
        )
      ).items,

    revokeSession: (id: string): Promise<true> =>
      client.request<true>(async (raw) => {
        const result = await raw.DELETE('/sessions/{id}', { params: { path: { id } } });
        return result.response.ok
          ? { data: true, response: result.response }
          : { error: result.error, response: result.response };
      })
  };
}

export type AdminUsersApi = ReturnType<typeof adminUsersApi>;
