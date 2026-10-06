import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    // The API only allows this origin (backend/.env CORS_ORIGINS), so landing on
    // another port silently breaks every request. Vite's default 5173 is taken by
    // another project on this machine, and auto-picking the next free port is exactly
    // what we must not do here — fail loudly instead.
    port: 5180,
    strictPort: true,
  },
})
