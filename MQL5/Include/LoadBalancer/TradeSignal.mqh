//+------------------------------------------------------------------+
//|                                                  TradeSignal.mqh |
//|              Signal structure written by Master, read by Slaves  |
//+------------------------------------------------------------------+
#pragma once

//--- Signal action types
enum ENUM_SIGNAL_ACTION
{
   SIGNAL_BUY          = 0,   // Open/increase long position
   SIGNAL_SELL         = 1,   // Open/increase short position
   SIGNAL_BUY_LIMIT    = 2,
   SIGNAL_SELL_LIMIT   = 3,
   SIGNAL_BUY_STOP     = 4,
   SIGNAL_SELL_STOP    = 5,
   SIGNAL_CLOSE        = 6,   // Close position / delete order
   SIGNAL_MODIFY       = 7,   // Modify SL/TP
   SIGNAL_SYNC_CHECK   = 8,   // Periodic full-portfolio diff check
};

//--- Compact signal structure stored in the JSON file
struct TradeSignal
{
   string   id;           // Unique signal ID (timestamp + random suffix)
   datetime created_at;   // UTC timestamp when signal was created
   int      action;       // ENUM_SIGNAL_ACTION value

   // Instrument
   string   symbol;

   // Volume (master side, before ratio scaling)
   double   master_volume;

   // Order parameters
   double   price;        // 0 = market order
   double   sl;           // Stop-loss (0 = none)
   double   tp;           // Take-profit (0 = none)

   // Position/order ticket on master (for CLOSE / MODIFY)
   ulong    master_ticket;

   // Comment forwarded to slave orders
   string   comment;

   // Filled by Slave after processing
   bool     processed;
   string   slave_account; // Account login (string) of the slave
   string   error_message; // Empty = success
};

//+------------------------------------------------------------------+
//| Serialise a TradeSignal to a simple JSON string                  |
//+------------------------------------------------------------------+
string SignalToJson(const TradeSignal &s)
{
   string j = "{\n";
   j += "  \"id\": \""            + s.id              + "\",\n";
   j += "  \"created_at\": "      + IntegerToString((long)s.created_at) + ",\n";
   j += "  \"action\": "          + IntegerToString(s.action)           + ",\n";
   j += "  \"symbol\": \""        + s.symbol          + "\",\n";
   j += "  \"master_volume\": "   + DoubleToString(s.master_volume, 8)  + ",\n";
   j += "  \"price\": "           + DoubleToString(s.price, 8)          + ",\n";
   j += "  \"sl\": "              + DoubleToString(s.sl, 8)             + ",\n";
   j += "  \"tp\": "              + DoubleToString(s.tp, 8)             + ",\n";
   j += "  \"master_ticket\": "   + IntegerToString((long)s.master_ticket) + ",\n";
   j += "  \"comment\": \""       + s.comment         + "\"\n";
   j += "}";
   return j;
}

//+------------------------------------------------------------------+
//| Parse a TradeSignal from a JSON string (minimal hand-rolled parser)|
//+------------------------------------------------------------------+
string _JsonStr(const string &json, const string &key)
{
   string search = "\"" + key + "\": \"";
   int pos = StringFind(json, search);
   if(pos < 0) return "";
   pos += StringLen(search);
   int end = StringFind(json, "\"", pos);
   if(end < 0) return "";
   return StringSubstr(json, pos, end - pos);
}

double _JsonDbl(const string &json, const string &key)
{
   string search = "\"" + key + "\": ";
   int pos = StringFind(json, search);
   if(pos < 0) return 0.0;
   pos += StringLen(search);
   int end = pos;
   while(end < StringLen(json))
   {
      ushort c = StringGetCharacter(json, end);
      if(c == ',' || c == '\n' || c == '}') break;
      end++;
   }
   return StringToDouble(StringSubstr(json, pos, end - pos));
}

long _JsonLng(const string &json, const string &key)
{
   string search = "\"" + key + "\": ";
   int pos = StringFind(json, search);
   if(pos < 0) return 0;
   pos += StringLen(search);
   int end = pos;
   while(end < StringLen(json))
   {
      ushort c = StringGetCharacter(json, end);
      if(c == ',' || c == '\n' || c == '}') break;
      end++;
   }
   return StringToInteger(StringSubstr(json, pos, end - pos));
}

bool SignalFromJson(const string &json, TradeSignal &s)
{
   s.id             = _JsonStr(json, "id");
   s.created_at     = (datetime)_JsonLng(json, "created_at");
   s.action         = (int)_JsonLng(json, "action");
   s.symbol         = _JsonStr(json, "symbol");
   s.master_volume  = _JsonDbl(json, "master_volume");
   s.price          = _JsonDbl(json, "price");
   s.sl             = _JsonDbl(json, "sl");
   s.tp             = _JsonDbl(json, "tp");
   s.master_ticket  = (ulong)_JsonLng(json, "master_ticket");
   s.comment        = _JsonStr(json, "comment");
   s.processed      = false;
   s.slave_account  = "";
   s.error_message  = "";
   return s.id != "";
}
