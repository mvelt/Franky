import { defineConfig } from 'vite';

// GitHub Pages serves from /<repo-name>/ by default.
// Override VITE_BASE_PATH to '/' for custom domains or root deployments.
const base = process.env.VITE_BASE_PATH ?? '/';

export default defineConfig({
  base,
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    target: 'es2022',
  },
  // Treat .wgsl files as raw strings (imported with ?raw in the shaders)
  assetsInclude: ['**/*.wgsl'],
});
