//+------------------------------------------------------------------+
//|                                               Notifications.mqh  |
//|          Helper functions for UI/push/email failure alerts       |
//+------------------------------------------------------------------+
#pragma once

#include "Config.mqh"

//+------------------------------------------------------------------+
//| Send a failure notification through all configured channels      |
//+------------------------------------------------------------------+
void NotifyFailure(const string &symbol,
                   const string &action_str,
                   const string &error_msg,
                   int           notify_flags)
{
   string msg = StringFormat(
      "[LB Slave %s] FAILED: %s %s — %s",
      IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)),
      action_str,
      symbol,
      error_msg
   );

   if((notify_flags & NOTIFY_PRINT) != 0)
      Print(msg);

   if((notify_flags & NOTIFY_ALERT) != 0)
      Alert(msg);

   if((notify_flags & NOTIFY_PUSH) != 0)
      SendNotification(msg);

   if((notify_flags & NOTIFY_EMAIL) != 0)
      SendMail("[MT5 LB] Trade failure on " + symbol, msg);
}

//+------------------------------------------------------------------+
//| Log informational message to Experts journal                     |
//+------------------------------------------------------------------+
void LogInfo(const string &msg)
{
   Print("[LoadBalancer] " + msg);
}

//+------------------------------------------------------------------+
//| Log warning message                                              |
//+------------------------------------------------------------------+
void LogWarning(const string &msg)
{
   Print("[LoadBalancer] WARNING: " + msg);
}

//+------------------------------------------------------------------+
//| Log error message                                                |
//+------------------------------------------------------------------+
void LogError(const string &msg)
{
   Print("[LoadBalancer] ERROR: " + msg);
}
