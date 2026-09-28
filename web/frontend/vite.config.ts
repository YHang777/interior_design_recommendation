import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Admin frontend dev server. The backend base URL comes from
// VITE_API_BASE_URL (see .env.example) — no Firebase in the browser.
export default defineConfig({
  // The console is served from /admin on the unified host (see web/Dockerfile
  // and web/backend/src/app.ts), so emitted asset URLs must be prefixed.
  // Dev URL becomes http://localhost:5173/admin/
  base: '/admin/',
  plugins: [react()],
  server: {
    port: 5173,
  },
});
