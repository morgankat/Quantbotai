HEDGE AI BOT - STANDALONE (GitHub Pages)
========================================
One file: index.html. No server, no Node, no Railway.

1. Create a GitHub repository and upload index.html (repo root).
2. Settings > Pages > Deploy from branch (main, / root). Your link is
   https://YOURNAME.github.io/REPO/
3. IMPORTANT: add that exact link as a Redirect URI on your cTrader Open API
   application (the same place you did it for your other bots), otherwise the
   cTrader login page will refuse to return to the bot.
4. Open the link, choose Demo or Real, tap LOGIN WITH CTRADER, tick the account(s),
   and you land on the dashboard with live balance, positions and XAUUSD quotes.

Login flow = same as the Series X / Megan bots: official cTrader page, your Cloudflare
Worker swaps the code for a token, then the cTrader Open API WebSocket.
Your cTrader password is never entered in the bot.

Current scope: login + live data + EMA9/21 + RSI14 SIGNAL display. The signal
engine does NOT place orders yet. reference-HedgeAIBot.mq5 is kept for the
strategy that would be ported.
