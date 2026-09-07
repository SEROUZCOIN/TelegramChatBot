//+------------------------------------------------------------------+
//|                                                    NGZ_Neuro.mqh |
//|            Neuro Gann Zones - neural inference / training layer   |
//|                                                                   |
//|  A compact multilayer perceptron:                                 |
//|      NGZ_FEATURES  ->  hidden (tanh)  ->  1 (tanh)                |
//|  trained by stochastic gradient descent on closed historical      |
//|  bars only. The seed is an input, so a given history always       |
//|  produces the same weights - the output is reproducible.          |
//+------------------------------------------------------------------+
#ifndef __NGZ_NEURO_MQH__
#define __NGZ_NEURO_MQH__

#include "NGZ_Config.mqh"
#include "NGZ_State.mqh"
#include "NGZ_Math.mqh"

//+------------------------------------------------------------------+
//| Deterministic pseudo-random weight in [-1, +1]                    |
//+------------------------------------------------------------------+
double NgzRandSym(void)
  {
   return ((double)MathRand() / 16383.5) - 1.0;          // MathRand: 0 .. 32767
  }

//+------------------------------------------------------------------+
//| Xavier-style initialisation                                       |
//+------------------------------------------------------------------+
void NgzNetInit(NgzNet &net, const int nIn, const int nHid, const int seed)
  {
   net.nIn      = NgzIMin(NgzIMax(nIn, 1), NGZ_FEATURES);
   net.nHid     = NgzIMin(NgzIMax(nHid, 2), NGZ_HIDDEN_MAX);
   net.b2       = 0.0;
   net.samples  = 0;
   net.epochs   = 0;
   net.loss     = 0.0;
   net.accuracy = 0.0;

   MathSrand((int)seed);

   double limit1 = MathSqrt(6.0 / (double)(net.nIn + net.nHid));
   double limit2 = MathSqrt(6.0 / (double)(net.nHid + 1));

   for(int j = 0; j < net.nHid; j++)
     {
      for(int k = 0; k < net.nIn; k++)
         net.w1[j * net.nIn + k] = NgzRandSym() * limit1;
      net.b1[j] = 0.0;
      net.w2[j] = NgzRandSym() * limit2;
     }
  }

//+------------------------------------------------------------------+
//| Forward pass. 'hid' receives the hidden activations so the        |
//| training step can reuse them without a second forward pass.       |
//+------------------------------------------------------------------+
double NgzNetForward(const NgzNet &net, const double &x[], const int xOffset, double &hid[])
  {
   for(int j = 0; j < net.nHid; j++)
     {
      double s = net.b1[j];
      int    w = j * net.nIn;
      for(int k = 0; k < net.nIn; k++)
         s += net.w1[w + k] * x[xOffset + k];
      hid[j] = NgzTanh(s);
     }

   double o = net.b2;
   for(int j = 0; j < net.nHid; j++)
      o += net.w2[j] * hid[j];

   return NgzTanh(o);
  }

//+------------------------------------------------------------------+
//| One stochastic gradient descent step on the squared error.        |
//| Returns the signed error so the caller can accumulate the loss.   |
//+------------------------------------------------------------------+
double NgzNetTrainStep(NgzNet &net, const double &x[], const int xOffset,
                       const double target, const double lr, const double l2,
                       double &hid[], double &dHid[])
  {
   double y   = NgzNetForward(net, x, xOffset, hid);
   double err = y - target;
   double dO  = err * NgzTanhD(y);

   //--- hidden deltas must be computed with the CURRENT output weights
   for(int j = 0; j < net.nHid; j++)
      dHid[j] = dO * net.w2[j] * NgzTanhD(hid[j]);

   //--- output layer
   for(int j = 0; j < net.nHid; j++)
      net.w2[j] -= lr * (dO * hid[j] + l2 * net.w2[j]);
   net.b2 -= lr * dO;

   //--- hidden layer
   for(int j = 0; j < net.nHid; j++)
     {
      int w = j * net.nIn;
      for(int k = 0; k < net.nIn; k++)
         net.w1[w + k] -= lr * (dHid[j] * x[xOffset + k] + l2 * net.w1[w + k]);
      net.b1[j] -= lr * dHid[j];
     }

   return err;
  }

//+------------------------------------------------------------------+
//| Full training run over a cached feature block.                    |
//|   feats   : flat cache, sample s starts at offsets[s]             |
//|   targets : desired output of every sample, already in [-1, +1]   |
//| Returns true when the network is usable.                          |
//+------------------------------------------------------------------+
bool NgzNetTrain(NgzNet &net, const double &feats[], const int &offsets[],
                 const double &targets[], const int nSamples)
  {
   if(nSamples < InpMinSamples) return false;

   double hid[NGZ_HIDDEN_MAX];
   double dHid[NGZ_HIDDEN_MAX];
   int    order[];
   ArrayResize(order, nSamples);
   for(int k = 0; k < nSamples; k++) order[k] = k;

   double lr     = InpLearnRate;
   int    epochs = NgzIMax(1, InpEpochs);
   double loss   = 0.0;

   for(int e = 0; e < epochs; e++)
     {
      //--- Fisher-Yates shuffle keeps the descent from following bar order
      for(int k = nSamples - 1; k > 0; k--)
        {
         int j   = MathRand() % (k + 1);
         int tmp = order[k];
         order[k] = order[j];
         order[j] = tmp;
        }

      loss = 0.0;
      for(int k = 0; k < nSamples; k++)
        {
         if((k & 1023) == 0 && IsStopped()) return false;
         int s   = order[k];
         double err = NgzNetTrainStep(net, feats, offsets[s], targets[s], lr, InpL2, hid, dHid);
         loss += err * err;
        }
      loss /= (double)nSamples;
      lr   *= InpLrDecay;
     }

   //--- in-sample directional hit rate (diagnostic only, never a promise)
   int hits = 0, counted = 0;
   for(int k = 0; k < nSamples; k++)
     {
      if(MathAbs(targets[k]) < 0.05) continue;          // ignore flat samples
      double y = NgzNetForward(net, feats, offsets[k], hid);
      if((y > 0.0 && targets[k] > 0.0) || (y < 0.0 && targets[k] < 0.0)) hits++;
      counted++;
     }

   net.samples  = nSamples;
   net.epochs   = epochs;
   net.loss     = loss;
   net.accuracy = (counted > 0) ? (double)hits / (double)counted : 0.0;
   return true;
  }

//+------------------------------------------------------------------+
//| Weight persistence (optional). File lives in MQL5\Files.          |
//+------------------------------------------------------------------+
string NgzNetFileName(void)
  {
   return StringFormat("NeuroGannZones_%s_%d.bin", _Symbol, (int)_Period);
  }

bool NgzNetSave(const NgzNet &net)
  {
   int h = FileOpen(NgzNetFileName(), FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(h == INVALID_HANDLE) return false;
   uint written = FileWriteStruct(h, net);
   FileClose(h);
   return (written > 0);
  }

bool NgzNetLoad(NgzNet &net)
  {
   if(!FileIsExist(NgzNetFileName(), FILE_COMMON)) return false;
   int h = FileOpen(NgzNetFileName(), FILE_READ | FILE_BIN | FILE_COMMON);
   if(h == INVALID_HANDLE) return false;
   uint read = FileReadStruct(h, net);
   FileClose(h);

   //--- reject a file that does not match the current architecture
   if(read == 0 || net.nIn != NGZ_FEATURES || net.nHid < 2 || net.nHid > NGZ_HIDDEN_MAX)
      return false;
   return true;
  }

#endif // __NGZ_NEURO_MQH__
//+------------------------------------------------------------------+
