import { BadRequestException, PipeTransform } from '@nestjs/common';
import { ZodError, ZodSchema } from 'zod';

/**
 * Validates a request body against a schema from `@tsp/shared`.
 *
 * Using the shared schemas here rather than Nest DTO classes means the admin
 * panel's forms, the mobile client's types and this validation all derive from
 * one definition — a field cannot drift out of sync between them.
 */
export class ZodValidationPipe<T> implements PipeTransform<unknown, T> {
  constructor(private readonly schema: ZodSchema<T>) {}

  transform(value: unknown): T {
    try {
      return this.schema.parse(value);
    } catch (err) {
      if (err instanceof ZodError) {
        throw new BadRequestException({
          message: 'Validation failed',
          issues: err.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
        });
      }
      throw err;
    }
  }
}
