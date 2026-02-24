//+------------------------------------------------------------------+
//|                                               PositionSync.mqh   |
//|        Core sync logic: diff calculation and order execution     |
//+------------------------------------------------------------------+
#pragma once

#include "Config.mqh"
#include "TradeSignal.mqh"
#include "Notifications.mqh"

//+------------------------------------------------------------------+
//| Apply the slave ratio to the master volume                       |
//+------------------------------------------------------------------+
double ScaleVolume(double master_vol, double ratio, const string &symbol)
{
   double raw   = master_vol * ratio;
   double step  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double min_v = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_v = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0) step = 0.01;
   double scaled = MathFloor(raw / step) * step;
   scaled = MathMax(min_v, MathMin(max_v, scaled));
   return NormalizeDouble(scaled, 2);
}

//+------------------------------------------------------------------+
//| Execute a single trade signal on this slave account              |
//+------------------------------------------------------------------+
bool ExecuteSignal(const TradeSignal &sig, double ratio, int notify_flags)
{
   MqlTradeRequest  req  = {};
   MqlTradeResult   res  = {};

   double vol = ScaleVolume(sig.master_volume, ratio, sig.symbol);
   if(vol <= 0)
   {
      NotifyFailure(sig.symbol, EnumToString((ENUM_SIGNAL_ACTION)sig.action),
                    "Scaled volume is 0 (ratio too small)", notify_flags);
      return false;
   }

   // ---------- Route signal action ----------
   switch((ENUM_SIGNAL_ACTION)sig.action)
   {
      //--- Market buy
      case SIGNAL_BUY:
         req.action    = TRADE_ACTION_DEAL;
         req.type      = ORDER_TYPE_BUY;
         req.price     = SymbolInfoDouble(sig.symbol, SYMBOL_ASK);
         break;

      //--- Market sell
      case SIGNAL_SELL:
         req.action    = TRADE_ACTION_DEAL;
         req.type      = ORDER_TYPE_SELL;
         req.price     = SymbolInfoDouble(sig.symbol, SYMBOL_BID);
         break;

      //--- Pending buy limit
      case SIGNAL_BUY_LIMIT:
         req.action    = TRADE_ACTION_PENDING;
         req.type      = ORDER_TYPE_BUY_LIMIT;
         req.price     = sig.price;
         break;

      //--- Pending sell limit
      case SIGNAL_SELL_LIMIT:
         req.action    = TRADE_ACTION_PENDING;
         req.type      = ORDER_TYPE_SELL_LIMIT;
         req.price     = sig.price;
         break;

      //--- Pending buy stop
      case SIGNAL_BUY_STOP:
         req.action    = TRADE_ACTION_PENDING;
         req.type      = ORDER_TYPE_BUY_STOP;
         req.price     = sig.price;
         break;

      //--- Pending sell stop
      case SIGNAL_SELL_STOP:
         req.action    = TRADE_ACTION_PENDING;
         req.type      = ORDER_TYPE_SELL_STOP;
         req.price     = sig.price;
         break;

      //--- Close / delete
      case SIGNAL_CLOSE:
      {
         // Find matching position by symbol and close it
         if(PositionSelect(sig.symbol))
         {
            req.action    = TRADE_ACTION_DEAL;
            req.position  = PositionGetInteger(POSITION_TICKET);
            double pos_vol = PositionGetDouble(POSITION_VOLUME);
            req.volume    = MathMin(vol, pos_vol);
            req.symbol    = sig.symbol;
            req.deviation = 20;
            req.comment   = "LB_CLOSE:" + sig.comment;

            ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if(ptype == POSITION_TYPE_BUY)
            {
               req.type  = ORDER_TYPE_SELL;
               req.price = SymbolInfoDouble(sig.symbol, SYMBOL_BID);
            }
            else
            {
               req.type  = ORDER_TYPE_BUY;
               req.price = SymbolInfoDouble(sig.symbol, SYMBOL_ASK);
            }

            if(!OrderSend(req, res))
            {
               string err = "Close failed: " + IntegerToString(GetLastError());
               NotifyFailure(sig.symbol, "CLOSE", err, notify_flags);
               return false;
            }
            return true;
         }
         LogWarning("CLOSE signal for " + sig.symbol + " but no matching position found");
         return true;   // not an error – position may not exist on slave
      }

      //--- Modify SL/TP of existing position
      case SIGNAL_MODIFY:
      {
         if(PositionSelect(sig.symbol))
         {
            req.action   = TRADE_ACTION_SLTP;
            req.position = PositionGetInteger(POSITION_TICKET);
            req.symbol   = sig.symbol;
            req.sl       = sig.sl;
            req.tp       = sig.tp;
            if(!OrderSend(req, res))
            {
               string err = "Modify failed: " + IntegerToString(GetLastError());
               NotifyFailure(sig.symbol, "MODIFY", err, notify_flags);
               return false;
            }
            return true;
         }
         LogWarning("MODIFY signal for " + sig.symbol + " but no matching position found");
         return true;
      }

      //--- Periodic sync-check – no single trade to mirror; handled elsewhere
      case SIGNAL_SYNC_CHECK:
         return true;

      default:
         LogWarning("Unknown signal action: " + IntegerToString(sig.action));
         return false;
   }

   // Common fields for open/pending
   req.symbol    = sig.symbol;
   req.volume    = vol;
   req.sl        = sig.sl;
   req.tp        = sig.tp;
   req.deviation = 20;
   req.comment   = "LB:" + sig.comment;
   req.magic     = 9999001;

   if(!OrderSend(req, res))
   {
      int    ec  = GetLastError();
      string err = "OrderSend failed: " + IntegerToString(ec)
                 + " ret=" + IntegerToString(res.retcode);
      NotifyFailure(sig.symbol, EnumToString((ENUM_SIGNAL_ACTION)sig.action), err, notify_flags);
      return false;
   }

   LogInfo(StringFormat("Executed %s %s vol=%.2f ticket=%llu",
           EnumToString((ENUM_SIGNAL_ACTION)sig.action), sig.symbol, vol, res.order));
   return true;
}

//+------------------------------------------------------------------+
//| Write a signal to a file in the shared signal directory          |
//+------------------------------------------------------------------+
bool WriteSignalFile(const TradeSignal &sig, const string &signal_dir)
{
   string path = signal_dir + SIGNAL_FILE_PREFIX + sig.id + SIGNAL_FILE_EXT;
   int fh = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
   {
      LogError("Cannot write signal file: " + path + " err=" + IntegerToString(GetLastError()));
      return false;
   }
   FileWriteString(fh, SignalToJson(sig));
   FileClose(fh);
   return true;
}

//+------------------------------------------------------------------+
//| Read a signal from file; returns false on parse error            |
//+------------------------------------------------------------------+
bool ReadSignalFile(const string &path, TradeSignal &sig)
{
   int fh = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
      return false;

   string json = "";
   while(!FileIsEnding(fh))
      json += FileReadString(fh);
   FileClose(fh);

   return SignalFromJson(json, sig);
}

//+------------------------------------------------------------------+
//| Mark a signal file as processed (rename to .done)               |
//+------------------------------------------------------------------+
void MarkSignalDone(const string &path)
{
   string done = path;
   StringReplace(done, SIGNAL_FILE_EXT, PROCESSED_FILE_EXT);
   FileMove(path, FILE_COMMON, done, FILE_COMMON | FILE_REWRITE);
}

//+------------------------------------------------------------------+
//| Generate a unique signal ID                                      |
//+------------------------------------------------------------------+
string NewSignalId()
{
   return IntegerToString((long)TimeCurrent()) + "_"
        + IntegerToString(MathRand() % 100000);
}
