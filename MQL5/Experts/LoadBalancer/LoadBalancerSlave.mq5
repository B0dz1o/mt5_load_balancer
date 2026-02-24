//+------------------------------------------------------------------+
//|                                        LoadBalancerSlave.mq5    |
//|                    MT5 Load Balancer – Slave Expert Advisor      |
//|                                                                  |
//| Attach to a chart on each SECONDARY account (broker B, C, D…). |
//| This EA reads signal files written by the Master EA and mirrors  |
//| trades scaled by the configured ratio.                           |
//+------------------------------------------------------------------+
#property copyright "MT5 Load Balancer"
#property version   "1.00"
#property description "Slave EA: mirrors trades from the master account with ratio scaling."

#include <LoadBalancer/Config.mqh>
#include <LoadBalancer/TradeSignal.mqh>
#include <LoadBalancer/PositionSync.mqh>
#include <LoadBalancer/Notifications.mqh>

//--- Input parameters
input double SlaveRatio         = DEFAULT_RATIO;          // Volume ratio (e.g. 0.7 = 70 % of master)
input int    PollIntervalSec    = 5;                      // How often to check for new signal files (seconds)
input string SignalDirectory    = DEFAULT_SIGNAL_DIR;     // Must match Master's SignalDirectory
input int    NotifyFlags        = NOTIFY_ALERT | NOTIFY_PRINT; // Failure notification channels

//+------------------------------------------------------------------+
//| EA initialisation                                                |
//+------------------------------------------------------------------+
int OnInit()
{
   if(SlaveRatio <= 0 || SlaveRatio > 10)
   {
      LogError("SlaveRatio must be > 0 and ≤ 10. Got: " + DoubleToString(SlaveRatio, 3));
      return INIT_PARAMETERS_INCORRECT;
   }

   LogInfo(StringFormat(
      "Slave started – account %lld, ratio=%.2f, poll=%ds, dir=%s",
      AccountInfoInteger(ACCOUNT_LOGIN), SlaveRatio, PollIntervalSec, SignalDirectory));

   if(!EventSetTimer(PollIntervalSec))
   {
      LogError("EventSetTimer failed");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EA de-initialisation                                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   LogInfo("Slave stopped.");
}

//+------------------------------------------------------------------+
//| Timer: poll signal directory for new files                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   ProcessPendingSignals();
}

//+------------------------------------------------------------------+
//| Scan signal directory and execute any unprocessed signals        |
//+------------------------------------------------------------------+
void ProcessPendingSignals()
{
   string search = SignalDirectory + SIGNAL_FILE_PREFIX + "*" + SIGNAL_FILE_EXT;
   string fname  = "";
   long   handle = FileFindFirst(search, fname, FILE_COMMON);

   if(handle == INVALID_HANDLE)
      return;  // No pending signals

   int processed_count = 0;
   do
   {
      if(processed_count >= MAX_SIGNAL_FILES)
      {
         LogWarning("MAX_SIGNAL_FILES reached – remaining files will be processed next cycle.");
         break;
      }

      string full_path = SignalDirectory + fname;
      TradeSignal sig;

      if(!ReadSignalFile(full_path, sig))
      {
         LogWarning("Could not parse signal file: " + fname);
         MarkSignalDone(full_path);  // Move it aside to avoid reprocessing
         continue;
      }

      // Handle periodic sync check separately
      if((ENUM_SIGNAL_ACTION)sig.action == SIGNAL_SYNC_CHECK)
         HandleSyncCheck(sig, full_path);
      else
         HandleTradeSignal(sig, full_path);

      processed_count++;
   }
   while(FileFindNext(handle, fname));

   FileFindClose(handle);
}

//+------------------------------------------------------------------+
//| Execute a trade signal and mark the file done                    |
//+------------------------------------------------------------------+
void HandleTradeSignal(const TradeSignal &sig, const string &file_path)
{
   bool ok = ExecuteSignal(sig, SlaveRatio, NotifyFlags);

   if(!ok)
   {
      LogError(StringFormat("Signal %s execution failed for %s", sig.id, sig.symbol));
   }

   MarkSignalDone(file_path);
}

//+------------------------------------------------------------------+
//| Handle a periodic sync-check signal                              |
//| Reads the master snapshot from sig.comment and compares it       |
//| against this slave's current open positions.                     |
//+------------------------------------------------------------------+
void HandleSyncCheck(const TradeSignal &sig, const string &file_path)
{
   LogInfo("Processing sync-check signal " + sig.id);

   // Parse master positions from the embedded snapshot
   // Format: [{"sym":"EURUSD","type":0,"vol":1.00,"sl":1.05,"tp":1.12},…]
   string snap = sig.comment;
   if(StringLen(snap) < 2)
   {
      MarkSignalDone(file_path);
      return;
   }

   // For each master position entry, check if a matching slave position exists
   int pos = 0;
   while(true)
   {
      int start = StringFind(snap, "{", pos);
      if(start < 0) break;
      int end = StringFind(snap, "}", start);
      if(end < 0) break;

      string entry = StringSubstr(snap, start, end - start + 1);
      pos = end + 1;

      string sym      = _JsonStr(entry, "sym");
      int    ptype    = (int)_JsonLng(entry, "type");
      double master_v = _JsonDbl(entry, "vol");
      double sl       = _JsonDbl(entry, "sl");
      double tp       = _JsonDbl(entry, "tp");

      if(sym == "") continue;

      double target_v = ScaleVolume(master_v, SlaveRatio, sym);

      if(!PositionSelect(sym))
      {
         // Position missing on slave – open it
         TradeSignal fill;
         fill.id            = NewSignalId();
         fill.created_at    = TimeCurrent();
         fill.action        = (ptype == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
         fill.symbol        = sym;
         fill.master_volume = master_v;
         fill.price         = 0;
         fill.sl            = sl;
         fill.tp            = tp;
         fill.master_ticket = 0;
         fill.comment       = "sync_fill";

         LogInfo(StringFormat("Sync: opening missing position %s vol=%.2f", sym, target_v));
         ExecuteSignal(fill, SlaveRatio, NotifyFlags);
      }
      else
      {
         double slave_v = PositionGetDouble(POSITION_VOLUME);
         double diff    = NormalizeDouble(target_v - slave_v, 2);

         if(MathAbs(diff) >= SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP))
         {
            // Volume mismatch – adjust
            TradeSignal adj;
            adj.id            = NewSignalId();
            adj.created_at    = TimeCurrent();
            adj.symbol        = sym;
            adj.master_volume = MathAbs(diff);
            adj.price         = 0;
            adj.sl            = sl;
            adj.tp            = tp;
            adj.master_ticket = 0;
            adj.comment       = "sync_adj";

            if(diff > 0)
               adj.action = (ptype == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
            else
               adj.action = SIGNAL_CLOSE;   // partial close

            LogInfo(StringFormat("Sync: adjusting %s by %.2f lots", sym, diff));
            ExecuteSignal(adj, 1.0, NotifyFlags);  // volume already scaled
         }
      }
   }

   // Check for slave-only positions that are not in the master snapshot
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string sym = PositionGetString(POSITION_SYMBOL);

      // Check if this symbol appears in the master snapshot
      if(StringFind(snap, "\"sym\":\"" + sym + "\"") < 0)
      {
         LogInfo("Sync: closing orphan position " + sym);
         TradeSignal close_sig;
         close_sig.id            = NewSignalId();
         close_sig.created_at    = TimeCurrent();
         close_sig.action        = SIGNAL_CLOSE;
         close_sig.symbol        = sym;
         close_sig.master_volume = PositionGetDouble(POSITION_VOLUME);
         close_sig.price         = 0;
         close_sig.sl            = 0;
         close_sig.tp            = 0;
         close_sig.master_ticket = 0;
         close_sig.comment       = "sync_orphan";
         ExecuteSignal(close_sig, 1.0, NotifyFlags);
      }
   }

   MarkSignalDone(file_path);
}
