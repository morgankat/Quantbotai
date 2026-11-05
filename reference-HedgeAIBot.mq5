//+------------------------------------------------------------------+
//|                                            HedgeAIBot.mq5        |
//|  Auto hedge/grid bot - works on ANY MT5 broker, demo or live     |
//+------------------------------------------------------------------+
#property copyright "Series X"
#property version   "1.00"
#property strict
#include <Trade\Trade.mqh>

input group "=== Risk Management ==="
input double InpLot       = 0.02;   // Base lot size
input bool   InpAutoLot   = true;   // Auto lot by balance
input double InpLotPerK   = 0.01;   // Lot per $1,000 balance
input double InpMaxLot    = 5.0;    // Max lot per order
input int    InpMaxPerSide= 5;      // Max trades per direction
input double InpMult      = 1.6;    // Lot multiplier per grid level
input double InpGridStep  = 250;    // Grid step in points
input double InpBasketTP  = 15.0;   // Basket take-profit in account USD
input double InpEqStopPct = 8.0;    // Equity stop: close all at -% of balance

input group "=== Signal Filter ==="
input int    InpFastEMA   = 9;      // Fast EMA
input int    InpSlowEMA   = 21;     // Slow EMA
input int    InpRSIPeriod = 14;     // RSI period
input int    InpMaxSpread = 40;     // Max allowed spread (points)

input group "=== General ==="
input long   InpMagic     = 260925; // Magic number
input int    InpSlippage  = 10;     // Max slippage (points)

CTrade   trade;
int      hFast, hSlow, hRSI;
datetime lastBar = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   hFast = iMA(_Symbol, PERIOD_CURRENT, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow = iMA(_Symbol, PERIOD_CURRENT, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI  = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE || hRSI==INVALID_HANDLE)
      return(INIT_FAILED);
   Print("HedgeAIBot started on ", _Symbol, " ", EnumToString(PERIOD_CURRENT));
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason) { IndicatorRelease(hFast); IndicatorRelease(hSlow); IndicatorRelease(hRSI); }

//+------------------------------------------------------------------+
double NormLot(double lot)
  {
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot/step)*step;
   return MathMax(minL, MathMin(maxL, lot));
  }
//+------------------------------------------------------------------+
double BaseLot()
  {
   if(!InpAutoLot) return NormLot(InpLot);
   return NormLot(AccountInfoDouble(ACCOUNT_BALANCE)/1000.0*InpLotPerK);
  }
//+------------------------------------------------------------------+
int CountSide(ENUM_POSITION_TYPE side, double &vol, double &worstPrice)
  {
   int cnt=0; vol=0; worstPrice=(side==POSITION_TYPE_BUY)?DBL_MAX:0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=side) continue;
      cnt++;
      vol+=PositionGetDouble(POSITION_VOLUME);
      double op=PositionGetDouble(POSITION_PRICE_OPEN);
      if(side==POSITION_TYPE_BUY)  worstPrice=MathMin(worstPrice,op);
      else                         worstPrice=MathMax(worstPrice,op);
     }
   return cnt;
  }
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      trade.PositionClose(tk);
     }
  }
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime cur=iTime(_Symbol,PERIOD_CURRENT,0);
   if(cur==lastBar) return false;
   lastBar=cur; return true;
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double eq =AccountInfoDouble(ACCOUNT_EQUITY);

   //--- equity guard: hard stop
   if(bal>0 && (bal-eq)/bal*100.0 >= InpEqStopPct)
     { CloseAll(); Print("EQUITY STOP hit: all positions closed"); return; }

   //--- basket take-profit in money
   double bVol=0,sVol=0,bWP=0,sWP=0;
   int bCnt=CountSide(POSITION_TYPE_BUY,bVol,bWP);
   int sCnt=CountSide(POSITION_TYPE_SELL,sVol,sWP);
   if(bCnt+sCnt>0)
     {
      double fp=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
         fp+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
        }
      if(fp>=InpBasketTP) { CloseAll(); Print("Basket TP hit: +", DoubleToString(fp,2)); return; }
     }

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   long spread=(long)MathRound((ask-bid)/point);
   if(spread>InpMaxSpread) return;          // skip dirty ticks

   //--- entry only on a fresh bar
   if(!IsNewBar()) return;

   double f[1],s[1],r[1];
   if(CopyBuffer(hFast,0,1,1,f)<1 || CopyBuffer(hSlow,0,1,1,s)<1 || CopyBuffer(hRSI,0,1,1,r)<1) return;
   bool bull = f[0]>s[0] && r[0]>50.0;
   bool bear = f[0]<s[0] && r[0]<50.0;

   if(bCnt==0 && sCnt==0)
     {
      //--- hedge opening: both directions, EMA decides which side gets bigger base
      double lot=BaseLot();
      if(bull) { trade.Buy (lot,_Symbol,0,0,0,"HedgeAI BUY");  trade.Sell(NormLot(lot/2),_Symbol,0,0,0,"HedgeAI SELL"); }
      else if(bear){ trade.Sell(lot,_Symbol,0,0,0,"HedgeAI SELL"); trade.Buy(NormLot(lot/2),_Symbol,0,0,0,"HedgeAI BUY"); }
      else { trade.Buy(lot,_Symbol,0,0,0,"HedgeAI BUY"); trade.Sell(lot,_Symbol,0,0,0,"HedgeAI SELL"); }
      return;
     }

   //--- grid management per side
   double step=InpGridStep*point;
   if(bCnt>0 && bCnt<InpMaxPerSide && bid<bWP-step)
     {
      double nextLot=NormLot(BaseLot()*MathPow(InpMult,bCnt));
      trade.Buy(nextLot,_Symbol,0,0,0,"HedgeAI grid BUY");
     }
   if(sCnt>0 && sCnt<InpMaxPerSide && ask>sWP+step)
     {
      double nextLot=NormLot(BaseLot()*MathPow(InpMult,sCnt));
      trade.Sell(nextLot,_Symbol,0,0,0,"HedgeAI grid SELL");
     }
  }
//+------------------------------------------------------------------+
