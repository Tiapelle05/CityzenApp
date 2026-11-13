import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          leaflet: ['leaflet'],
          icons: ['lucide-react'],
        },
      },
    },
  },
  server: {
    host: '0.0.0.0',
    port: process.env.PORT ? Number(process.env.PORT) : 5173,
    open: false,
    proxy: {
      '/auth':         { target: 'http://localhost:8000', changeOrigin: true },
      '/practices/ws': { target: 'ws://localhost:8000',   ws: true, changeOrigin: true },
      '/practices':    { target: 'http://localhost:8000', changeOrigin: true, ws: true },
      '/events':       { target: 'http://localhost:8000', changeOrigin: true },
      '/devices':      { target: 'http://localhost:8000', changeOrigin: true },
      '/parks':        { target: 'http://localhost:8000', changeOrigin: true },
      '/onboarding':   { target: 'http://localhost:8000', changeOrigin: true },
      '/sla':          { target: 'http://localhost:8000', changeOrigin: true },
      '/mini':         { target: 'http://localhost:8000', changeOrigin: true },
      '/power':        { target: 'http://localhost:8000', changeOrigin: true },
      '/citizen-reports': { target: 'http://localhost:8000', changeOrigin: true },
      '/static':       { target: 'http://localhost:8000', changeOrigin: true },
      '/api':          { target: 'http://localhost:8000', changeOrigin: true },
    }
  },
  preview: {
    host: '0.0.0.0',
    port: 5173,
  },
})
