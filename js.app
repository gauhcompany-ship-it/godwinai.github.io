 // ==============================================================
    // DUAL ASSET SCALPER: XAUUSD & BTCUSD using Twelve Data + Groq
    // ==============================================================
    
    // State for each asset
    let assets = {
        XAUUSD: { price: null, support: null, resistance: null, rsi: null, history: [], lastSignal: null, widget: null },
        BTCUSD: { price: null, support: null, resistance: null, rsi: null, history: [], lastSignal: null, widget: null }
    };
    
    let twelveApiKey = 'demo';
    let groqApiKey = '';
    let autoIntervalId = null;
    
    // DOM elements
    const logPanel = document.getElementById('logPanel');
    function addLog(msg, type = 'info') {
        const entry = document.createElement('div');
        entry.className = 'log-entry';
        const time = new Date().toLocaleTimeString();
        const icon = type === 'signal' ? '🎯' : (type === 'error' ? '❌' : (type === 'success' ? '✅' : '🔹'));
        entry.innerHTML = `[${time}] ${icon} ${msg}`;
        logPanel.appendChild(entry);
        entry.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        while (logPanel.children.length > 90) logPanel.removeChild(logPanel.firstChild);
    }
    
    // Technical functions
    function calculateRSI(prices, period = 14) {
        if (prices.length < period + 1) return 50;
        let gains = 0, losses = 0;
        let startIdx = Math.max(0, prices.length - period - 1);
        for (let i = startIdx; i < prices.length - 1; i++) {
            const diff = prices[i+1] - prices[i];
            if (diff >= 0) gains += diff;
            else losses -= diff;
        }
        const avgGain = gains / period;
        const avgLoss = losses / period;
        const rs = avgGain / (avgLoss === 0 ? 0.01 : avgLoss);
        let rsi = 100 - (100 / (1 + rs));
        return Math.min(85, Math.max(15, parseFloat(rsi.toFixed(1))));
    }
    
    function calcSupportResistance(prices) {
        if (prices.length < 20) return { support: null, resistance: null };
        const recent = prices.slice(-30);
        const high = Math.max(...recent);
        const low = Math.min(...recent);
        const range = high - low;
        const support = low + (range * 0.236);
        const resistance = high - (range * 0.236);
        return { support: parseFloat(support.toFixed(2)), resistance: parseFloat(resistance.toFixed(2)) };
    }
    
    async function fetchRealAsset(symbol, assetKey) {
        try {
            // map symbol for Twelve Data: XAU/USD, BTC/USD
            const apiSymbol = symbol === 'XAUUSD' ? 'XAU/USD' : 'BTC/USD';
            const url = `https://api.twelvedata.com/time_series?symbol=${apiSymbol}&interval=5min&outputsize=50&apikey=${twelveApiKey}`;
            const response = await fetch(url);
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const data = await response.json();
            if (data.code === 401 || data.message?.includes('Invalid')) throw new Error("Invalid Twelve Data key");
            if (!data.values || data.values.length === 0) throw new Error("No price data");
            
            const prices = data.values.map(v => parseFloat(v.close)).reverse();
            assets[assetKey].history = prices;
            const currentPrice = prices[prices.length-1];
            assets[assetKey].price = currentPrice;
            const sr = calcSupportResistance(prices);
            assets[assetKey].support = sr.support;
            assets[assetKey].resistance = sr.resistance;
            assets[assetKey].rsi = calculateRSI(prices, 14);
            return true;
        } catch (err) {
            addLog(`⚠️ ${symbol} fetch error: ${err.message}`, 'error');
            return false;
        }
    }
    
    async function fetchBothAssets() {
        addLog("🌐 Fetching real-time XAUUSD & BTCUSD data...", 'info');
        const xauOk = await fetchRealAsset('XAUUSD', 'XAUUSD');
        const btcOk = await fetchRealAsset('BTCUSD', 'BTCUSD');
        updateUI();
        if (xauOk && btcOk) addLog("✅ Both assets updated successfully", 'success');
        else addLog("⚠️ Some assets failed to update, check API key", 'error');
        return (xauOk || btcOk);
    }
    
    function updateUI() {
        // XAU
        const xau = assets.XAUUSD;
        document.getElementById('xauPrice').innerText = xau.price ? `$${xau.price.toFixed(2)}` : '---';
        document.getElementById('xauSupport').innerText = xau.support ? `$${xau.support.toFixed(2)}` : '---';
        document.getElementById('xauResistance').innerText = xau.resistance ? `$${xau.resistance.toFixed(2)}` : '---';
        document.getElementById('xauRsi').innerText = xau.rsi ? xau.rsi.toFixed(1) : '---';
        if (xau.rsi > 70) document.getElementById('xauRsi').style.color = "#ef4444";
        else if (xau.rsi < 30) document.getElementById('xauRsi').style.color = "#10b981";
        else if (xau.rsi) document.getElementById('xauRsi').style.color = "#fbbf24";
        
        // BTC
        const btc = assets.BTCUSD;
        document.getElementById('btcPrice').innerText = btc.price ? `$${btc.price.toFixed(0)}` : '---';
        document.getElementById('btcSupport').innerText = btc.support ? `$${btc.support.toFixed(0)}` : '---';
        document.getElementById('btcResistance').innerText = btc.resistance ? `$${btc.resistance.toFixed(0)}` : '---';
        document.getElementById('btcRsi').innerText = btc.rsi ? btc.rsi.toFixed(1) : '---';
        if (btc.rsi > 70) document.getElementById('btcRsi').style.color = "#ef4444";
        else if (btc.rsi < 30) document.getElementById('btcRsi').style.color = "#10b981";
        else if (btc.rsi) document.getElementById('btcRsi').style.color = "#fbbf24";
        
        document.getElementById('dataSourceStatus').innerHTML = `Twelve Data (Real) | ${new Date().toLocaleTimeString()}`;
    }
    
    async function analyzeAssetWithGroq(assetKey, symbolName, apiSymbolForPrompt) {
        const asset = assets[assetKey];
        if (!asset.price) {
            addLog(`⚠️ No price data for ${symbolName}, fetch real data first.`, 'error');
            return null;
        }
        const nearSupport = asset.support && Math.abs(asset.price - asset.support) < (assetKey === 'XAUUSD' ? 1.8 : 180);
        const nearResistance = asset.resistance && Math.abs(asset.price - asset.resistance) < (assetKey === 'XAUUSD' ? 1.8 : 250);
        
        const prompt = `As a professional scalper for ${symbolName}, analyze this REAL market data:
Price: $${asset.price}
Dynamic Support: $${asset.support}
Dynamic Resistance: $${asset.resistance}
RSI(14): ${asset.rsi} (${asset.rsi > 70 ? 'overbought' : (asset.rsi < 30 ? 'oversold' : 'neutral')})
Price Action: ${nearSupport ? 'Touching SUPPORT zone' : (nearResistance ? 'Touching RESISTANCE zone' : 'Between levels')}
Strategy: Scalp BUY at support with RSI oversold, SELL at resistance with RSI overbought. Provide strict entry, stop loss, take profit.
Return ONLY JSON: {"signal": "BUY/SELL/HOLD", "confidence": "High/Medium/Low", "entry": number, "takeProfit": number, "stopLoss": number, "reasoning": "short"}.`;

        try {
            const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${groqApiKey}`, 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    model: 'llama-3.3-70b-versatile',
                    messages: [{ role: 'user', content: prompt }],
                    temperature: 0.2,
                    max_tokens: 400
                })
            });
            if (!response.ok) throw new Error(`Groq HTTP ${response.status}`);
            const data = await response.json();
            let content = data.choices[0].message.content;
            content = content.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
            const analysis = JSON.parse(content);
            asset.lastSignal = analysis;
            return analysis;
        } catch (err) {
            addLog(`🤖 Groq error for ${symbolName}: ${err.message}`, 'error');
            return null;
        }
    }
    
    async function analyzeBothAndDisplay() {
        if (!groqApiKey) {
            addLog("❌ Groq API key missing. Enter & save your key first.", 'error');
            return;
        }
        if (!twelveApiKey || twelveApiKey === 'demo') {
            addLog("⚠️ Using demo Twelve Data key – limited requests. Get free key at twelvedata.com", 'warning');
        }
        
        addLog("🔍 Fetching latest REAL market data for both assets...", 'info');
        await fetchBothAssets();
        
        addLog("🧠 Running Groq AI analysis on XAUUSD...", 'info');
        const xauSignal = await analyzeAssetWithGroq('XAUUSD', 'XAUUSD', 'XAU/USD');
        addLog("🧠 Running Groq AI analysis on BTCUSD...", 'info');
        const btcSignal = await analyzeAssetWithGroq('BTCUSD', 'BTCUSD', 'BTC/USD');
        
        // Update UI with signals
        const xauBox = document.getElementById('xauSignalBox');
        const btcBox = document.getElementById('btcSignalBox');
        
        if (xauSignal) {
            xauBox.innerHTML = renderSignalHTML(xauSignal, assets.XAUUSD.price);
            addLog(`📊 XAUUSD AI: ${xauSignal.signal} (${xauSignal.confidence}) - ${xauSignal.reasoning}`, 'signal');
        } else { xauBox.innerHTML = `<div style="color:#ef4444;">❌ Analysis failed</div>`; }
        
        if (btcSignal) {
            btcBox.innerHTML = renderSignalHTML(btcSignal, assets.BTCUSD.price);
            addLog(`📊 BTCUSD AI: ${btcSignal.signal} (${btcSignal.confidence}) - ${btcSignal.reasoning}`, 'signal');
        } else { btcBox.innerHTML = `<div style="color:#ef4444;">❌ Analysis failed</div>`; }
        
        // Update last signals display
        const lastDisplay = document.getElementById('lastSignalsDisplay');
        lastDisplay.innerHTML = `🪙 XAU: ${xauSignal?.signal || 'N/A'} @ ${assets.XAUUSD.price ? '$'+assets.XAUUSD.price.toFixed(2) : '--'} <br> ₿ BTC: ${btcSignal?.signal || 'N/A'} @ ${assets.BTCUSD.price ? '$'+assets.BTCUSD.price.toFixed(0) : '--'}`;
        
        // Webhook if any signal is actionable and URL present
        const webhookUrl = document.getElementById('webhookUrl').value.trim();
        if (webhookUrl) {
            const signalsToSend = [];
            if (xauSignal && xauSignal.signal !== 'HOLD') signalsToSend.push({ asset: "XAUUSD", ...xauSignal, price: assets.XAUUSD.price });
            if (btcSignal && btcSignal.signal !== 'HOLD') signalsToSend.push({ asset: "BTCUSD", ...btcSignal, price: assets.BTCUSD.price });
            for (const sig of signalsToSend) {
                try {
                    await fetch(webhookUrl, {
                        method: 'POST', headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ ...sig, source: "REAL_DATA+Groq", timestamp: new Date().toISOString() })
                    });
                    addLog(`📡 Webhook sent for ${sig.asset} ${sig.signal}`, 'success');
                } catch(e) { addLog(`Webhook error: ${e.message}`, 'error'); }
            }
        }
    }
    
    function renderSignalHTML(signal, currentPrice) {
        if (!signal) return '<div style="color:#9ca3af;">No signal</div>';
        const signalClass = signal.signal || 'HOLD';
        return `<div class="signal ${signalClass}">🎯 AI SIGNAL: ${signal.signal}</div>
                <div>📊 Confidence: ${signal.confidence || 'Medium'}</div>
                <div>📈 Entry: $${(signal.entry || currentPrice || 0).toFixed(signal.entry > 1000 ? 0 : 2)}</div>
                <div>🎯 TP: $${(signal.takeProfit || 0).toFixed(signal.takeProfit > 1000 ? 0 : 2)}</div>
                <div>🛑 SL: $${(signal.stopLoss || 0).toFixed(signal.stopLoss > 1000 ? 0 : 2)}</div>
                <div style="margin-top:6px;">💡 ${signal.reasoning || 'Analysis complete'}</div>`;
    }
    
    // Manual trade triggers with current data
    function manualTrade(assetKey, side) {
        const asset = assets[assetKey];
        if (!asset.price) { addLog(`⚠️ No price for ${assetKey}. Click "Refresh All Real Data" first.`, 'error'); return; }
        const price = asset.price;
        let sl, tp;
        if (assetKey === 'XAUUSD') {
            if (side === 'buy') { sl = asset.support ? (asset.support - 1.8).toFixed(2) : (price - 2).toFixed(2); tp = asset.resistance ? (asset.resistance - 0.5).toFixed(2) : (price + 2.5).toFixed(2); }
            else { sl = asset.resistance ? (asset.resistance + 1.8).toFixed(2) : (price + 2).toFixed(2); tp = asset.support ? (asset.support + 1.2).toFixed(2) : (price - 2.5).toFixed(2); }
            addLog(`${side === 'buy' ? '🟢 MANUAL BUY' : '🔴 MANUAL SELL'} XAUUSD @ $${price.toFixed(2)} (SL: $${sl}, TP: $${tp})`, 'signal');
            alert(`${side.toUpperCase()} XAUUSD at $${price.toFixed(2)}\nStop: $${sl}\nTake Profit: $${tp}`);
        } else {
            if (side === 'buy') { sl = asset.support ? (asset.support - 180).toFixed(0) : (price - 300).toFixed(0); tp = asset.resistance ? (asset.resistance - 120).toFixed(0) : (price + 400).toFixed(0); }
            else { sl = asset.resistance ? (asset.resistance + 180).toFixed(0) : (price + 300).toFixed(0); tp = asset.support ? (asset.support + 150).toFixed(0) : (price - 400).toFixed(0); }
            addLog(`${side === 'buy' ? '🟢 MANUAL BUY' : '🔴 MANUAL SELL'} BTCUSD @ $${price.toFixed(0)} (SL: $${sl}, TP: $${tp})`, 'signal');
            alert(`${side.toUpperCase()} BTCUSD at $${price.toFixed(0)}\nStop: $${sl}\nTake Profit: $${tp}`);
        }
    }
    
    function toggleAutoMode() {
        if (autoIntervalId) {
            clearInterval(autoIntervalId);
            autoIntervalId = null;
            document.getElementById('autoBothBtn').innerHTML = '🔄 Auto (5min Both)';
            document.getElementById('autoBothBtn').classList.add('secondary');
            addLog("⏹️ Auto-analysis stopped", 'info');
        } else {
            if (!groqApiKey) { addLog("❌ Enter Groq API key first", 'error'); return; }
            autoIntervalId = setInterval(() => {
                analyzeBothAndDisplay();
            }, 300000);
            document.getElementById('autoBothBtn').innerHTML = '⏹️ Stop Auto';
            document.getElementById('autoBothBtn').classList.remove('secondary');
            addLog("▶️ Auto-analysis started (every 5 min)", 'success');
            analyzeBothAndDisplay();
        }
    }
    
    function initTradingViewCharts() {
        try {
            if (assets.XAUUSD.widget) assets.XAUUSD.widget.remove();
            if (assets.BTCUSD.widget) assets.BTCUSD.widget.remove();
            assets.XAUUSD.widget = new TradingView.widget({
                width: "100%", height: 380, symbol: "OANDA:XAUUSD", interval: "5", theme: "dark", style: "1", locale: "en",
                container_id: "tv-xau-container", studies: ["RSI@tv-basicstudies"], autosize: false
            });
            assets.BTCUSD.widget = new TradingView.widget({
                width: "100%", height: 380, symbol: "BITSTAMP:BTCUSD", interval: "5", theme: "dark", style: "1", locale: "en",
                container_id: "tv-btc-container", studies: ["RSI@tv-basicstudies"]
            });
            addLog("📈 TradingView charts loaded (visual reference)", 'success');
        } catch(e) { addLog("Chart visual only (AI works fine)", 'warning'); }
    }
    
    function saveKeys() {
        const groq = document.getElementById('groqApiKey').value.trim();
        const twelve = document.getElementById('twelveDataKey').value.trim();
        if (groq) { localStorage.setItem('groq_api_key', groq); groqApiKey = groq; }
        if (twelve) { localStorage.setItem('twelve_data_key', twelve); twelveApiKey = twelve; }
        addLog("✅ API keys saved", 'success');
    }
    
    async function init() {
        const savedGroq = localStorage.getItem('groq_api_key');
        const savedTwelve = localStorage.getItem('twelve_data_key');
        if (savedGroq) document.getElementById('groqApiKey').value = savedGroq;
        if (savedTwelve) document.getElementById('twelveDataKey').value = savedTwelve;
        groqApiKey = savedGroq || '';
        twelveApiKey = savedTwelve || 'demo';
        initTradingViewCharts();
        await fetchBothAssets();
        // Event listeners
        document.getElementById('analyzeBothBtn').addEventListener('click', analyzeBothAndDisplay);
        document.getElementById('autoBothBtn').addEventListener('click', toggleAutoMode);
        document.getElementById('manualRefreshAll').addEventListener('click', () => fetchBothAssets());
        document.getElementById('saveGroqKey').addEventListener('click', saveKeys);
        document.getElementById('saveTwelveKey').addEventListener('click', saveKeys);
        document.getElementById('xauBuyBtn').addEventListener('click', () => manualTrade('XAUUSD', 'buy'));
        document.getElementById('xauSellBtn').addEventListener('click', () => manualTrade('XAUUSD', 'sell'));
        document.getElementById('btcBuyBtn').addEventListener('click', () => manualTrade('BTCUSD', 'buy'));
        document.getElementById('btcSellBtn').addEventListener('click', () => manualTrade('BTCUSD', 'sell'));
        addLog("✨ AI Dual Scalper ready — XAUUSD + BTCUSD", 'success');
    }
    init();
