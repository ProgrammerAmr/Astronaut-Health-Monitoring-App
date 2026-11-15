export class ApiError extends Error {
  constructor(message, status) { super(message); this.status = status; }
}
export async function request(path, { token, method = 'GET', body, fetcher = fetch, preview = import.meta.env?.VITE_ORBITCARE_SYNTHETIC_DEMO === '1' } = {}) {
  let response;
  try {
    response = await fetcher(`/api${path}`, {
      method, headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? (preview ? { 'X-OrbitCare-Demo-Token': token } : { Authorization: `Bearer ${token}` }) : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  } catch {
    throw new ApiError('Cannot reach the backend. Check that the API is running.', 0);
  }
  let data;
  try { data = await response.json(); } catch {
    if (!response.ok) throw new ApiError(`The API request failed (HTTP ${response.status}). Check that the backend and API proxy are running.`, response.status);
    throw new ApiError('The API returned a non-JSON response. Check that /api is routed to the backend, not the frontend.', response.status);
  }
  if (!data || typeof data !== 'object') throw new ApiError('The API returned an invalid response.', response.status);
  if (!response.ok) throw new ApiError(data.message || data.errors?.[0]?.message || `Request failed (${response.status})`, response.status);
  return data;
}
