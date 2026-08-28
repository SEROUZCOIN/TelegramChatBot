import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    // Prisma client generation and DB round-trips make these slower than unit tests.
    testTimeout: 20_000,
    hookTimeout: 30_000,
    // The suite shares one database, so files must not run concurrently.
    fileParallelism: false,
  },
});
