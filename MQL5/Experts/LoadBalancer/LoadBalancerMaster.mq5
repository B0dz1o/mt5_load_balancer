//+------------------------------------------------------------------+
//|                                        LoadBalancerMaster.mq5   |
//|                    MT5 Load Balancer – Master Expert Advisor     |
//|                                                                  |
//| Attach to a chart on your PRIMARY (broker A) account.           |
//| This EA monitors trades and writes signal files consumed by      |
//| LoadBalancerSlave EAs running on secondary accounts.            |
//+------------------------------------------------------------------+
#property copyright "MT5 Load Balancer"
#property version   "1.00"
#property description "Master EA: broadcasts trade signals to slave accounts."

#include <LoadBalancer/Config.mqh>
#include <LoadBalancer/TradeSignal.mqh>
#include <LoadBalancer/PositionSync.mqh>
#include <LoadBalancer/Notifications.mqh>

//--- Input parameters
input int    SyncMode          = SYNC_MODE_BOTH;   // Sync mode: 0=Periodic, 1=Hooks, 2=Both
input int    PeriodicInterval  = DEFAULT_SYNC_INTERVAL_SEC; // Periodic interval (seconds)
input string SignalDirectory   = DEFAULT_SIGNAL_DIR;        // Shared signal directory

//--- Internal state
static ulong g_last_deal_ticket = 0;   // Last seen deal ticket (hook mode)
static bool  g_timer_active     = false;

//+------------------------------------------------------------------+
//| EA initialisation                                                |
//+------------------------------------------------------------------+
int OnInit()
{
   LogInfo(StringFormat(
      "Master started – account %lld, mode=%d, interval=%ds, dir=%s",
      AccountInfoInteger(ACCOUNT_LOGIN), SyncMode, PeriodicInterval, SignalDirectory));

   if(SyncMode == SYNC_MODE_PERIODIC || SyncMode == SYNC_MODE_BOTH)
   {
      if(!EventSetTimer(PeriodicInterval))
      {
         LogError("EventSetTimer failed");
         return INIT_FAILED;
      }
      g_timer_active = true;
   }

   // Capture starting deal ticket so we don't replay history on startup
   HistorySelect(TimeCurrent() - 60, TimeCurrent() + 60);
   if(HistoryDealsTotal() > 0)
      g_last_deal_ticket = HistoryDealGetTicket(HistoryDealsTotal() - 1);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EA de-initialisation                                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_timer_active)
      EventKillTimer();
   LogInfo("Master stopped.");
}

//+------------------------------------------------------------------+
//| Periodic timer – full portfolio diff broadcast                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   LogInfo("Periodic sync check triggered.");
   BroadcastSyncCheck();
}

//+------------------------------------------------------------------+
//| Trade transaction hook – fires on every deal/order change        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(SyncMode == SYNC_MODE_PERIODIC)
      return;   // Hooks disabled

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
      ProcessNewDeal(trans.deal);
}

//+------------------------------------------------------------------+
//| Emit a SIGNAL_SYNC_CHECK file so slaves perform a full diff      |
//+------------------------------------------------------------------+
void BroadcastSyncCheck()
{
   TradeSignal sig;
   sig.id            = NewSignalId();
   sig.created_at    = TimeCurrent();
   sig.action        = SIGNAL_SYNC_CHECK;
   sig.symbol        = "";
   sig.master_volume = 0;
   sig.price         = 0;
   sig.sl            = 0;
   sig.tp            = 0;
   sig.master_ticket = 0;
   sig.comment       = "periodic";

   // Also embed current open positions as a JSON array in the comment field
   sig.comment = BuildPositionSnapshot();

   if(!WriteSignalFile(sig, SignalDirectory))
      LogError("Failed to write periodic sync signal");
}

//+------------------------------------------------------------------+
//| Build a compact snapshot of all open positions for slaves to diff|
//+------------------------------------------------------------------+
string BuildPositionSnapshot()
{
   string snap = "[";
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(i > 0) snap += ",";
      snap += StringFormat(
         "{\"sym\":\"%s\",\"type\":%d,\"vol\":%.2f,\"sl\":%.5f,\"tp\":%.5f}",
         PositionGetString(POSITION_SYMBOL),
         (int)PositionGetInteger(POSITION_TYPE),
         PositionGetDouble(POSITION_VOLUME),
         PositionGetDouble(POSITION_SL),
         PositionGetDouble(POSITION_TP)
      );
   }
   snap += "]";
   return snap;
}

//+------------------------------------------------------------------+
//| Convert a completed deal into a trade signal and write it        |
//+------------------------------------------------------------------+
void ProcessNewDeal(ulong deal_ticket)
{
   if(!HistoryDealSelect(deal_ticket))
      return;

   ENUM_DEAL_TYPE    dtype  = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
   ENUM_DEAL_ENTRY   dentry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   string            symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
   double            vol    = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
   double            price  = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
   ulong             pos_id = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
   string            cmt    = HistoryDealGetString(deal_ticket, DEAL_COMMENT);

   // Skip signals we emitted ourselves (prevent feedback loop)
   if(StringFind(cmt, "LB:") == 0 || StringFind(cmt, "LB_CLOSE:") == 0)
      return;

   TradeSignal sig;
   sig.id            = NewSignalId();
   sig.created_at    = TimeCurrent();
   sig.symbol        = symbol;
   sig.master_volume = vol;
   sig.price         = price;
   sig.sl            = 0;
   sig.tp            = 0;
   sig.master_ticket = deal_ticket;
   sig.comment       = cmt;

   // Determine action from deal type + entry
   if(dentry == DEAL_ENTRY_IN || dentry == DEAL_ENTRY_INOUT)
   {
      sig.action = (dtype == DEAL_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

      // Carry SL/TP from the associated position
      if(PositionSelectByTicket(pos_id))
      {
         sig.sl = PositionGetDouble(POSITION_SL);
         sig.tp = PositionGetDouble(POSITION_TP);
      }
   }
   else if(dentry == DEAL_ENTRY_OUT || dentry == DEAL_ENTRY_OUT_BY)
   {
      sig.action = SIGNAL_CLOSE;
   }
   else
   {
      LogWarning("Unsupported deal entry type, skipping: " + IntegerToString(dentry));
      return;
   }

   if(!WriteSignalFile(sig, SignalDirectory))
      LogError("Failed to write signal for deal " + IntegerToString(deal_ticket));
   else
      LogInfo(StringFormat("Signal written: %s %s vol=%.2f", 
              EnumToString((ENUM_SIGNAL_ACTION)sig.action), symbol, vol));
}
