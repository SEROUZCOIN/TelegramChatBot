import { Module } from '@nestjs/common';
import {
  AdminPaymentsController,
  PaymentWebhooksController,
  PaymentsController,
} from './payments.controller';
import { PaymentsService } from './payments.service';
import { PAYMENT_PROVIDERS_TOKEN } from './payment-provider.interface';
import { StripeProvider } from './providers/stripe.provider';
import { CryptoProvider } from './providers/crypto.provider';
import { BankProvider } from './providers/bank.provider';
import { IapProvider } from './providers/iap.provider';

@Module({
  controllers: [PaymentsController, PaymentWebhooksController, AdminPaymentsController],
  providers: [
    PaymentsService,
    StripeProvider,
    CryptoProvider,
    BankProvider,
    IapProvider,
    {
      // All four rails are registered. Which of them a given plan may actually
      // use is decided per plan by `paymentMode`, so switching the recorded-
      // video tier to in-app purchase is a data change, not a deploy.
      provide: PAYMENT_PROVIDERS_TOKEN,
      inject: [StripeProvider, CryptoProvider, BankProvider, IapProvider],
      useFactory: (
        stripe: StripeProvider,
        crypto: CryptoProvider,
        bank: BankProvider,
        iap: IapProvider,
      ) => [stripe, crypto, bank, iap],
    },
  ],
  exports: [PaymentsService],
})
export class PaymentsModule {}
