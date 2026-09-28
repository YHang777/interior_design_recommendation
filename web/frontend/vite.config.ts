import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Admin frontend dev server. The backend base URL comes from
// VITE_API_BASE_URL (see .env.example) — no Firebase in the browser.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
  },
});
