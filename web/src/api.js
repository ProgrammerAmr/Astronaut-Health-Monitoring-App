export class ApiError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}
export async function request(path, { token, method = 'GET', body, fetcher = fetch } = {}) {
  let response;
  try {
    response = await fetcher(`/api${path}`, {
      method, headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  } catch {
    throw new ApiError('Cannot reach the backend. Check that the API is running.', 0);
  }
  let data;
  try { data = await response.json(); } catch { throw new ApiError('The backend returned an invalid response. Check the API connection.', response.status); }
  if (!response.ok) throw new ApiError(data.message || data.errors?.[0]?.message || `Request failed (${response.status})`, response.status);
  return data;
}
