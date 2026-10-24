import { defineConfig } from 'vite'

export default defineConfig({
  build: {
    lib: {
      entry: 'src/types.ts',
      formats: ['es'],
      fileName: 'studio-types',
    },
  },
  test: {
    environment: 'node',
    include: ['tests/unit/**/*.test.ts'],
  },
})
