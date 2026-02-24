//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|                          MT5 Load Balancer – Master/Slave Config |
//+------------------------------------------------------------------+
#pragma once

//--- Sync mode constants
#define SYNC_MODE_PERIODIC 0   // Timer-based sync (every N minutes)
#define SYNC_MODE_HOOKS    1   // Event-driven sync (OnTrade/OnTradeTransaction)
#define SYNC_MODE_BOTH     2   // Both periodic AND event-driven

//--- Default values
#define DEFAULT_SYNC_INTERVAL_SEC 300   // 5 minutes
#define DEFAULT_RATIO             1.0   // 100% mirror
#define MAX_SIGNAL_FILES          1000  // Maximum pending signal files to process

//--- Signal file directory (relative to MT5 data folder, or absolute path)
//    Both master and all slaves must point to the same shared directory.
//    On a single machine this works out of the box; across machines use a
//    network share / mapped drive and set SignalDirectory in the EA inputs.
#define DEFAULT_SIGNAL_DIR "LoadBalancer\\signals\\"

//--- File naming
#define SIGNAL_FILE_PREFIX  "sig_"
#define SIGNAL_FILE_EXT     ".json"
#define PROCESSED_FILE_EXT  ".done"

//--- Notification flags
#define NOTIFY_ALERT     0x01   // Show Alert() pop-up
#define NOTIFY_PRINT     0x02   // Print to Experts log
#define NOTIFY_PUSH      0x04   // Mobile push notification
#define NOTIFY_EMAIL     0x08   // Email notification
#define NOTIFY_ALL       0x0F
