import { Module } from '@nestjs/common';
import { AdminUsersController, UsersController } from './users.controller';

@Module({ controllers: [UsersController, AdminUsersController] })
export class UsersModule {}
