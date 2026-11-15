import { defineConfig } from 'vite';

// Browser requests stay same-origin; only the development server contacts the API.
export default defineConfig({
  server: {
    allowedHosts: true,
    proxy: { '/api': { target: process.env.ORBITCARE_BACKEND_URL || 'http://127.0.0.1:5000', changeOrigin: true } },
  },
});
