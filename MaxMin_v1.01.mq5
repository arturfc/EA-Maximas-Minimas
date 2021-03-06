//+------------------------------------------------------------------+
//|                                                       MaxMin.mq5 |
//|                                                      Artur Cunha |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2022, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.01"

#include <Trade/Trade.mqh> 
CTrade trade;

input int horaInicioAbertura = 9;   //Hora de Inicio de Abertura de Posições
input int minutoInicioAbertura = 5; //Minuto de Inicio de Abertura de Pisoções

input int horaFimAbertura = 16;  //Hora de Encerramento de Abertura de Posições
input int minutoFimAbertura = 30;   //Minuto de Encerramento de Abertura de Posições

input int horaInicioFechamento = 17;   //Hora de Inicio de Fechamento de Posições
input int minutoInicioFechamento = 30; //Minuto de Inicio de Fechamento de Posições

input int keltnerPeriod = 21;
input double keltnerDesvio = 0.4;

bool triggerBuy;
bool triggerSell;

//limite de barras a manter a operação ativa
int thresholdBuy;    
int thresholdSell;

bool lockBar;  //variável para impedir mais de um trade na mesma barra
bool firstTP;  //variável para permitir TP logo ao acionar a primeira ordem

int keltnerHandle;
double keltnerUpperBand[];
double keltnerLowerBand[];


input ulong magicNum = 123456;   //Magic Number
input ENUM_ORDER_TYPE_FILLING preenchimento = ORDER_FILLING_RETURN;  //Preenchimento da Ordem


MqlDateTime horaAtual;
MqlTick tick;
MqlRates rates[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   ArraySetAsSeries(keltnerLowerBand, true);
   ArraySetAsSeries(keltnerUpperBand, true);
   
   keltnerHandle = iCustom(_Symbol, PERIOD_CURRENT, "keltner_channel315.ex5", PERIOD_CURRENT, keltnerPeriod, 0, 1, 0, clrDeepSkyBlue, clrPaleVioletRed, keltnerPeriod, keltnerDesvio, 1);

   if(horaInicioAbertura > horaFimAbertura || horaFimAbertura > horaInicioFechamento)
     {
      Alert("Inconsistência de Horários de Negociação! ERROR 1");
      return(INIT_FAILED);
     }
   if(horaInicioAbertura == horaFimAbertura && minutoInicioAbertura >= minutoFimAbertura)
     {
      Alert("Inconsistência de Horários de Negociação! ERROR 2");
      return(INIT_FAILED);
     }
   if(horaFimAbertura == horaInicioFechamento && minutoFimAbertura >= minutoInicioAbertura)
     {
      Alert("Inconsistência de Horários de Negociação! ERROR 3");
      return(INIT_FAILED);
     }
     trade.SetTypeFilling(preenchimento);
     trade.SetExpertMagicNumber(magicNum);
     
     ArraySetAsSeries(rates,true);

//---
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(CopyBuffer(keltnerHandle, 2, 0, 2, keltnerUpperBand) < 0)
     {
      Alert("Erro ao copiar dados da keltner upper band: ", GetLastError());
      return;
     }
   
   if(CopyBuffer(keltnerHandle, 3, 0, 2, keltnerLowerBand) < 0)
     {
      Alert("Erro ao copiar dados da keltner lower band: ", GetLastError());
      return;
     }
   
   if(CopyRates(_Symbol, _Period, 0, 3, rates) < 0)
     {
      Alert("Erro ao obter as informações de MqlRates: ", GetLastError());
      return;
     }
     
   if(firstTP && OrdersTotal() == 0 && PositionsTotal() != 0)
     {
      for(int i=PositionsTotal()-1; i>=0; i--)
       {
        string symbol=PositionGetSymbol(i);
        ulong magic=PositionGetInteger(POSITION_MAGIC);
        if(symbol==_Symbol && magic==magicNum)
          {
           lockBar = true;
           //Pega os dados correspondentes do ticket aberto
           ulong PositionTicket= PositionGetInteger(POSITION_TICKET);
           double TakeProfitCorrente=PositionGetDouble(POSITION_TP);
           
           //Modificando TP de compra 
           if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
             {
              trade.SellLimit(1, rates[1].high, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
             }
           else if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)
             {
              trade.BuyLimit(1, rates[1].low, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
             }
          }
       }
      
      firstTP = false;
     }
   
   lockBar = false;
  
   //obtem o preço do tick corrente
   double currentPrice = SymbolInfoDouble(_Symbol,SYMBOL_LAST);
   
   //variáveis para detectar nova barra --> isso tem que ser modificado no tickBarExpert
   int candleNumber = Bars(_Symbol, _Period);
   bool isnewBar = CheckingNewBar(candleNumber);
   
   //cancela ordem pendente se surgir nova barra e houver ordem aberta - OBS: não faz sentido custar tanta CPU se só entra a cada newBar...
   if(isnewBar && OrdersTotal() != 0 && PositionsTotal() == 0)
     {
      for(int i=OrdersTotal()-1; i>=0; i--)
       {
        //Pegando os dados correspondentes do ticket aberto
        ulong ticket = OrderGetTicket(i);
        string symbol = OrderGetString(ORDER_SYMBOL);
        ulong magic = OrderGetInteger(ORDER_MAGIC);
        if(symbol == _Symbol && magic == magicNum)
          {
           //deletando ordem
           trade.OrderDelete(ticket);
          }
       }
     }
   
   //modificador de TP se surgir nova barra e houver posições abertas
   if(isnewBar && PositionsTotal() != 0)
    {
     //nova ordem limite como TP (posição contrária a inicial)... OBS: para TP acionado logo de cara, este if se tornará obsoleto
     if(OrdersTotal() == 0)
       {
        for(int i=PositionsTotal()-1; i>=0; i--)
          {
           string symbol=PositionGetSymbol(i);
           ulong magic=PositionGetInteger(POSITION_MAGIC);
           if(symbol==_Symbol && magic==magicNum)
             {
              lockBar = true;
              //pega os dados correspondentes do ticket aberto
              ulong PositionTicket= PositionGetInteger(POSITION_TICKET);
              double TakeProfitCorrente=PositionGetDouble(POSITION_TP);
              
              //Modificando TP de compra 
              if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                {
                 trade.SellLimit(1, rates[1].high, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
                 thresholdBuy+=1;
                }
              else if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)
                {
                 trade.BuyLimit(1, rates[1].low, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
                 thresholdSell+=1;
                }
             }
          }
       }
     else
       {
        //deleta TP antigo
        for(int i=OrdersTotal()-1; i>=0; i--)
          {
           //Pegando os dados correspondentes do ticket aberto
           ulong ticket = OrderGetTicket(i);
           string symbol = OrderGetString(ORDER_SYMBOL);
           ulong magic = OrderGetInteger(ORDER_MAGIC);
           if(symbol == _Symbol && magic == magicNum)
             {
              //deletando ordem
              trade.OrderDelete(ticket);
             }
          }
         //insere novo TP 
         for(int i=PositionsTotal()-1; i>=0; i--)
          {
           string symbol=PositionGetSymbol(i);
           ulong magic=PositionGetInteger(POSITION_MAGIC);
           if(symbol==_Symbol && magic==magicNum)
             {
              lockBar = true;
              //pega os dados correspondentes do ticket aberto
              ulong PositionTicket= PositionGetInteger(POSITION_TICKET);
              double TakeProfitCorrente=PositionGetDouble(POSITION_TP);
              
              //Modificando TP de compra 
              if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
                {
                 if(thresholdBuy < 3)
                   {
                    //em caso de spread vantajoso ao surgir nova barra
                    if(rates[0].open > rates[1].high)
                      {
                       trade.PositionClose(PositionTicket);
                      }
                    else
                      {
                       if(rates[1].high != rates[2].high)
                         {
                          //TP modification
                          trade.SellLimit(1, rates[1].high, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
                          thresholdBuy+=1;
                         }
                       else
                         {
                          thresholdBuy+=1;
                         }
                      }
                   }
                 else if(thresholdBuy == 3) 
                   {
                    //trade.SellLimit(1, rates[0].open, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
                    //Print("Limit order adjust at ", rates[0].open, " -> Ticket número ", PositionTicket);
                    trade.PositionClose(PositionTicket);
                   }
                 else
                   {
                    //force to close
                    //trade.PositionClose(PositionTicket);
                    //Print(((rates[1].open - rates[0].open)/0.5), " tick efficiency");
                   }
                   
                }
              //Analisando TP de venda  
              else if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)
                {
                 if(thresholdSell < 3)
                   {
                    //em caso de spread vantajoso ao surgir nova barra
                    if(rates[0].open < rates[1].low)
                      {
                       trade.PositionClose(PositionTicket);
                      }
                    else
                      {
                       if(rates[1].low != rates[2].low)
                         {
                          //TP modification
                          trade.BuyLimit(1, rates[1].low, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
                          thresholdSell+=1;
                         }
                       else
                         {
                          thresholdSell+=1;
                         }  
                      }
                   }
                 else if(thresholdSell == 3) 
                   {
                    //trade.BuyLimit(1, rates[0].open, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
                    //Print("Limit order adjust at ", rates[0].open, " -> Ticket número ", PositionTicket);
                    trade.PositionClose(PositionTicket);
                   }
                 else
                   {
                    //force to close
                    //trade.PositionClose(PositionTicket);
                    //Print(((rates[0].open - rates[1].open)/0.5), " tick efficiency");
                   }
                }
             }
          }
       }     
     }
     //UPGRADE PERFORMANCE HINT - USAR ESTAS CONDIÇÕES APENAS PARA SURGIMENTO DE NOVA BARRA (REPENSANDO, NAO FAZ SENTIDO!)
     //---Gatilho para compra 
     triggerBuy = false;
     if(rates[1].close > keltnerUpperBand[1] && !lockBar)   
         {triggerBuy = true;}
     
     if(OrdersTotal()==0 && PositionsTotal()==0 && triggerBuy && HoraNegociacao())
       {
        thresholdBuy = 0; 
        trade.BuyLimit(1, rates[1].low, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
        firstTP = true;
       }
     
     //Gatilho para venda
     triggerSell = false;
     if(rates[1].close < keltnerLowerBand[1] && !lockBar) 
         triggerSell = true;
     
     if(OrdersTotal()==0 && PositionsTotal()==0 && triggerSell && HoraNegociacao())
       {
        thresholdSell = 0; 
        trade.SellLimit(1, rates[1].high, _Symbol, 0, 0, ORDER_TIME_GTC,0,NULL);
        firstTP = true;
       }
     Comment("Real Profit: ", PrintProfit());  
     //Comment("Ordem pendente: ", OrdersTotal(), "\nOrdens executadas: ", PositionsTotal(), "\nNova barra: ",isnewBar);
  }
//+------------------------------------------------------------------+



//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   datetime agora = TimeCurrent();
   datetime hoje = (agora*86400)*86400;
   
   HistorySelect(hoje,agora);
   
   int total = HistoryDealsTotal();
   double dayProfit = 0;
  
   for(int i=1;i<total;i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
        {
         dayProfit = dayProfit + HistoryDealGetDouble(ticket, DEAL_PROFIT);
         //Print("Ticket: ", ticket, " profit: ", HistoryDealGetDouble(ticket, DEAL_PROFIT));
        }
     }
   
   Print("Total de negócios: ", total-1,
         "\nToday's gross profit: ", dayProfit,
         "\nToday's real profit: ", dayProfit - ((double)total*1.33));
   
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool HoraNegociacao()
  {
   TimeToStruct(TimeCurrent(), horaAtual);
   if(horaAtual.hour >= horaInicioAbertura && horaAtual.hour <= horaFimAbertura)
     {
      if(horaAtual.hour == horaInicioAbertura)
        {
         if(horaAtual.min >= minutoInicioAbertura)
           {
            return true;
           }
         else
           {
            return false;
           }
        }
      if(horaAtual.hour == horaFimAbertura)
        {
         if(horaAtual.min <= minutoFimAbertura)
           {
            return true;
           }
         else
           {
            return false;
           }
        }
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool HoraFechamento()
  {
   TimeToStruct(TimeCurrent(), horaAtual);
   if(horaAtual.hour >= horaInicioFechamento)
     {
      if(horaAtual.hour == horaInicioFechamento)
        {
         if(horaAtual.min >= minutoInicioFechamento)
           {
            return true;
           }
         else
           {
            return false;
           }
        }
      return true;
     }
   return false;
  }
//---
//---

bool CheckingNewBar(int candleNumber)
  {
   static int lastBarNumber;
   
   if(candleNumber > lastBarNumber)
     {
      //Print("NEW BAR FORMED");
      lastBarNumber = candleNumber;
      return true;
     }
   else
     {
      return false;
     }
  }
  
double PrintProfit()
  {
   datetime agora = TimeCurrent();
   datetime hoje = (agora*86400)*86400;
   
   HistorySelect(hoje,agora);
   
   int total = HistoryDealsTotal();
   double dayProfit = 0;
  
   for(int i=1;i<total;i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
        {
         dayProfit = dayProfit + HistoryDealGetDouble(ticket, DEAL_PROFIT);
         //Print("Ticket: ", ticket, " profit: ", HistoryDealGetDouble(ticket, DEAL_PROFIT));
        }
     }
   if(total == 1)
     {
      return 0;
     }
   else 
      return (dayProfit - ((double)total*1.33));
  }