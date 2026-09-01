import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  build: {
    target: 'es2022',
    // The single-file bundle used for hosting inlines everything, so keep the
    // output as one chunk and let assets fold into the JS.
    assetsInlineLimit: 1024 * 1024,
    rollupOptions: {
      output: { manualChunks: undefined, inlineDynamicImports: true },
    },
  },
})
