import { defineConfig } from 'vite';

// Browser requests stay same-origin; only the development server contacts the API.
export default defineConfig({
  server: {
    allowedHosts: true,
    proxy: {
      '/api': {
        target: process.env.ORBITCARE_BACKEND_URL || 'http://127.0.0.1:5000',
        changeOrigin: true,
        configure(proxy) {
          proxy.on('error', (_error, _req, res) => {
            if (res && !res.headersSent && !res.writableEnded && typeof res.writeHead === 'function') {
              res.writeHead(502, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ message: 'Cannot connect to the backend. Start MongoDB and the Node API, then try again. See web/README.md for setup.' }));
            }
          });
        },
      },
    },
  },
});
