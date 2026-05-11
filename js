
    // ==============================================================
    // XAUUSD AI SCALPER - EXNESS opens as separate window (no iframe issues)
    // ==============================================================

    let currentPrice = null;
    let supportLevel = null;
    let resistanceLevel = null;
    let rsiValue = null;
    let priceHistory = [];
    let tvWidget = null;
    let autoIntervalId = null;
    let lastGroqResponse = null;
    let twelveDataApiKey = 'demo';
    let groqApiKey = '';
    let exnessWindow = null;

    const logContainer = document.getElementById('logPanel');
    const currentPriceSpan = document.getElementById('currentPrice');
    const supportSpan = document.getElementById('supportVal');
    const resistanceSpan = document.getElementById('resistanceVal');
    const rsiSpan = document.getElementById('rsiVal');
    const aiOutputDiv = document.getElementById('aiOutput');
    const lastSignalSpan = document.getElementById('lastSignalDisplay');
    const dataSourceSpan = document.getElementById('dataSource');

    function addLog(msg, type = 'info') {
        const entry = document.createElement('div');
        entry.className = 'log-entry';
        const time = new Date().toLocaleTimeString();
        const icon = type === 'signal' ? '🎯' : (type === 'error' ? '❌' : (type === 'success' ? '✅' : '🔹'));
        entry.innerHTML = `[${time}] ${icon} ${msg}`;
        logContainer.appendChild(entry);
        entry.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        while (logContainer.children.length > 80) logContainer.removeChild(logContainer.firstChild);
    }

    function calculateRSI(prices, period = 14) {
        if (prices.length < period + 1) return 50;
        let gains = 0, losses = 0;
        let startIdx = Math.max(0, prices.length - period - 1);
        for (let i = startIdx; i < prices.length - 1; i++) {
            const diff = prices[i + 1] - prices[i];
            if (diff >= 0) gains += diff;
            else losses -= diff;
        }
        const avgGain = gains / period;
        const avgLoss = losses / period;
        const rs = avgGain / (avgLoss === 0 ? 0.01 : avgLoss);
        let rsi = 100 - (100 / (1 + rs));
        return Math.min(85, Math.max(15, parseFloat(rsi.toFixed(1))));
    }

    function calculateSupportResistance(prices) {
        if (prices.length < 20) return { support: null, resistance: null };
        const recentPrices = prices.slice(-30);
        const high = Math.max(...recentPrices);
        const low = Math.min(...recentPrices);
        const range = high - low;
        const support = low + (range * 0.236);
        const resistance = high - (range * 0.236);
        return { support: parseFloat(support.toFixed(2)), resistance: parseFloat(resistance.toFixed(2)) };
    }

    async function fetchRealXAUUSD() {
        try {
            addLog("🌐 Fetching REAL XAUUSD data from Twelve Data API...", 'info');
            const response = await fetch(
                `https://api.twelvedata.com/time_series?symbol=XAU/USD&interval=5min&outputsize=50&apikey=${twelveDataApiKey}`
            );
            if (!response.ok) throw new Error(`API Error: ${response.status}`);
            const data = await response.json();
            if (data.code === 401 || data.message === 'Invalid API key') {
                throw new Error("Invalid Twelve Data API key");
            }
            if (!data.values || data.values.length === 0) throw new Error("No data received");
            const prices = data.values.map(v => parseFloat(v.close)).reverse();
            priceHistory = prices;
            currentPrice = prices[prices.length - 1];
            const sr = calculateSupportResistance(prices);
            supportLevel = sr.support;
            resistanceLevel = sr.resistance;
            rsiValue = calculateRSI(prices, 14);
            addLog(`✅ REAL data: XAUUSD = $${currentPrice.toFixed(2)}`, 'success');
            updateUI();
            return true;
        } catch (error) {
            addLog(`❌ Failed to fetch: ${error.message}`, 'error');
            return false;
        }
    }

    function updateUI() {
        if (currentPrice) currentPriceSpan.innerText = `$${currentPrice.toFixed(2)}`;
        if (supportLevel) supportSpan.innerText = `$${supportLevel.toFixed(2)}`;
        if (resistanceLevel) resistanceSpan.innerText = `$${resistanceLevel.toFixed(2)}`;
        if (rsiValue) rsiSpan.innerText = rsiValue.toFixed(1);
        dataSourceSpan.innerText = "Twelve Data (Real)";
        dataSourceSpan.style.color = "#10b981";
    }

    function initTradingViewChart() {
        try {
            if (tvWidget) { try { tvWidget.remove(); } catch(e) {} }
            tvWidget = new TradingView.widget({
                "width": "100%",
                "height": 460,
                "symbol": "OANDA:XAUUSD",
                "interval": "5",
                "timezone": "Etc/UTC",
                "theme": "dark",
                "style": "1",
                "locale": "en",
                "toolbar_bg": "#0f172a",
                "enable_publishing": false,
                "allow_symbol_change": true,
                "container_id": "tradingview-widget",
                "studies": ["RSI@tv-basicstudies", "MACD@tv-basicstudies"]
            });
            addLog("✅ TradingView chart loaded", 'success');
        } catch (error) {
            addLog("⚠️ TradingView note: visual only", 'warning');
        }
    }

    function updateTradeDisplay(analysis) {
        if (!analysis) return;
        document.getElementById('currentTradeLevels').style.display = 'block';
        document.getElementById('displayEntry').innerText = `$${analysis.entry?.toFixed(2) || '---'}`;
        document.getElementById('displayTP').innerText = `$${analysis.takeProfit?.toFixed(2) || '---'}`;
        document.getElementById('displaySL').innerText = `$${analysis.stopLoss?.toFixed(2) || '---'}`;
        document.getElementById('displayConfidence').innerText = analysis.confidence || 'Medium';
        lastSignalSpan.innerHTML = `${analysis.signal} @ $${analysis.entry?.toFixed(2) || '---'} | ${new Date().toLocaleTimeString()}`;
        if (analysis.signal === 'BUY') lastSignalSpan.style.color = '#10b981';
        else if (analysis.signal === 'SELL') lastSignalSpan.style.color = '#ef4444';
        else lastSignalSpan.style.color = '#fbbf24';
    }

    async function fetchDataAndRunGroqAnalysis() {
        groqApiKey = document.getElementById('groqApiKey').value.trim();
        twelveDataApiKey = document.getElementById('twelveDataKey').value.trim() || 'demo';
        if (!groqApiKey) {
            addLog("❌ Please enter your Groq API key", 'error');
            aiOutputDiv.innerHTML = '<div style="color:#ef4444;">❌ Missing Groq API key - get from console.groq.com</div>';
            return;
        }
        addLog("🤖 Fetching market data & analyzing...", 'info');
        aiOutputDiv.innerHTML = '<div style="color:#fbbf24;">⏳ Fetching real market data & analyzing...</div>';
        const success = await fetchRealXAUUSD();
        if (!success || !currentPrice) {
            aiOutputDiv.innerHTML = '<div style="color:#ef4444;">❌ Failed to fetch market data</div>';
            return;
        }
        
        const prompt = `As a professional XAUUSD scalper, analyze: Price=$${currentPrice}, Support=$${supportLevel}, Resistance=$${resistanceLevel}, RSI=${rsiValue}. Use scalping strategy. Return JSON: {"signal":"BUY/SELL/HOLD","confidence":"High/Medium/Low","entry":${currentPrice},"takeProfit":number,"stopLoss":number,"reasoning":"short text"}`;
        
        try {
            const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${groqApiKey}`, 'Content-Type': 'application/json' },
                body: JSON.stringify({ model: 'llama-3.3-70b-versatile', messages: [{ role: 'user', content: prompt }], temperature: 0.2, max_tokens: 400 })
            });
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const data = await response.json();
            let content = data.choices[0].message.content.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
            let analysis = JSON.parse(content);
            const signalClass = analysis.signal || 'HOLD';
            let signalHtml = `<div class="signal ${signalClass}">🎯 AI SIGNAL: ${analysis.signal}</div>`;
            signalHtml += `<div>📊 Confidence: ${analysis.confidence}</div>`;
            signalHtml += `<div>📈 Entry: $${analysis.entry?.toFixed(2)}</div>`;
            signalHtml += `<div>🎯 TP: $${analysis.takeProfit?.toFixed(2)}</div>`;
            signalHtml += `<div>🛑 SL: $${analysis.stopLoss?.toFixed(2)}</div>`;
            signalHtml += `<div>💡 ${analysis.reasoning}</div>`;
            signalHtml += `<div style="margin-top:12px; padding:8px; background:#1e293b; border-radius:12px;">
                            <i class="fas fa-external-link-alt"></i> Next: Click "Open EXNESS" → Use split screen → Paste trade details
                           </div>`;
            aiOutputDiv.innerHTML = signalHtml;
            updateTradeDisplay(analysis);
            addLog(`🤖 AI: ${analysis.signal} (${analysis.confidence})`, 'signal');
            lastGroqResponse = analysis;
            
            const webhookUrl = document.getElementById('webhookUrl').value;
            if (webhookUrl && analysis.signal !== 'HOLD') {
                await fetch(webhookUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ symbol: "XAUUSD", ...analysis }) });
                addLog(`📡 Webhook sent`, 'success');
            }
        } catch (err) {
            addLog(`Groq error: ${err.message}`, 'error');
            aiOutputDiv.innerHTML = `<div style="color:#ef4444;">❌ Analysis failed: ${err.message}</div>`;
        }
    }

    function toggleAutoAnalysis() {
        if (autoIntervalId) {
            clearInterval(autoIntervalId);
            autoIntervalId = null;
            document.getElementById('autoAnalyzeBtn').innerHTML = '<i class="fas fa-clock"></i> Auto-Analyze (every 5min)';
            addLog("⏹️ Auto-analysis stopped", 'info');
        } else {
            if (!document.getElementById('groqApiKey').value.trim()) {
                addLog("❌ Enter Groq API key first", 'error');
                return;
            }
            autoIntervalId = setInterval(fetchDataAndRunGroqAnalysis, 300000);
            document.getElementById('autoAnalyzeBtn').innerHTML = '<i class="fas fa-stop"></i> Stop Auto-Analysis';
            addLog("▶️ Auto-analysis started (every 5min)", 'success');
            fetchDataAndRunGroqAnalysis();
        }
    }

    function copyTradeDetails() {
        if (!lastGroqResponse) { addLog("⚠️ Run AI analysis first", 'error'); alert("Please run AI analysis first"); return; }
        const tradeText = `🔔 XAUUSD ${lastGroqResponse.signal}
📈 Entry: $${lastGroqResponse.entry?.toFixed(2)}
🎯 Take Profit: $${lastGroqResponse.takeProfit?.toFixed(2)}
🛑 Stop Loss: $${lastGroqResponse.stopLoss?.toFixed(2)}
💪 Confidence: ${lastGroqResponse.confidence}
💡 ${lastGroqResponse.reasoning}`;
        navigator.clipboard.writeText(tradeText);
        addLog("📋 Trade details copied to clipboard!", 'success');
        alert("✅ Trade details copied!\n\nOpen EXNESS window and paste these values into your order.");
    }

    function manualBuy() {
        if (!currentPrice) { addLog("⚠️ No price data - click 'Manual Price Fetch' first", 'error'); return; }
        const sl = supportLevel ? (supportLevel - 1.8).toFixed(2) : (currentPrice - 2).toFixed(2);
        const tp = resistanceLevel ? (resistanceLevel - 1.5).toFixed(2) : (currentPrice + 2).toFixed(2);
        const tradeText = `BUY XAUUSD\nEntry: $${currentPrice.toFixed(2)}\nStop Loss: $${sl}\nTake Profit: $${tp}`;
        navigator.clipboard.writeText(tradeText);
        addLog(`📋 BUY parameters copied: Entry $${currentPrice.toFixed(2)}`, 'success');
        alert(`✅ BUY parameters copied!\n\nEntry: $${currentPrice.toFixed(2)}\nSL: $${sl}\nTP: $${tp}\n\nPaste into EXNESS order window.`);
    }
    
    function manualSell() {
        if (!currentPrice) { addLog("⚠️ No price data - click 'Manual Price Fetch' first", 'error'); return; }
        const sl = resistanceLevel ? (resistanceLevel + 1.8).toFixed(2) : (currentPrice + 2).toFixed(2);
        const tp = supportLevel ? (supportLevel + 1.5).toFixed(2) : (currentPrice - 2).toFixed(2);
        const tradeText = `SELL XAUUSD\nEntry: $${currentPrice.toFixed(2)}\nStop Loss: $${sl}\nTake Profit: $${tp}`;
        navigator.clipboard.writeText(tradeText);
        addLog(`📋 SELL parameters copied: Entry $${currentPrice.toFixed(2)}`, 'success');
        alert(`✅ SELL parameters copied!\n\nEntry: $${currentPrice.toFixed(2)}\nSL: $${sl}\nTP: $${tp}\n\nPaste into EXNESS order window.`);
    }

    // Open EXNESS as popup window (controlled size for side-by-side)
    function openExnessWindow(url, width = 800, height = 900) {
        const left = window.screen.width / 2 - width / 2;
        const top = 50;
        exnessWindow = window.open(url, 'ExnessTrading', `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes,status=yes`);
        if (exnessWindow) {
            addLog("🪟 EXNESS window opened - now use split screen layout!", 'success');
            alert("💡 TIP:\n1. Move this window to LEFT half (Win+Left Arrow)\n2. Move EXNESS window to RIGHT half (Win+Right Arrow)\n3. Resize both for perfect side-by-side view!");
        } else {
            addLog("⚠️ Popup blocked - allow popups for this site", 'error');
            alert("Popup blocked! Please allow popups for this site to open EXNESS.");
        }
    }

    function showSplitScreenGuide() {
        alert("📺 HOW TO USE SIDE-BY-SIDE MODE:\n\n1. Click 'Open EXNESS' button\n2. On Windows: Press Windows Key + Left Arrow on THIS window\n3. Press Windows Key + Right Arrow on EXNESS window\n4. On Mac: Use Rectangle or Magnet app, or manually resize both\n5. Run AI analysis and copy trade details\n6. Paste into EXNESS order form\n\nPerfect for executing AI signals instantly!");
        addLog("📺 Split-screen guide shown", 'info');
    }

    function saveKeys() {
        localStorage.setItem('groq_api_key', document.getElementById('groqApiKey').value.trim());
        localStorage.setItem('twelve_data_key', document.getElementById('twelveDataKey').value.trim());
        addLog("✅ API keys saved", 'success');
    }

    async function init() {
        initTradingViewChart();
        
        const savedGroq = localStorage.getItem('groq_api_key');
        const savedTwelve = localStorage.getItem('twelve_data_key');
        if (savedGroq) document.getElementById('groqApiKey').value = savedGroq;
        if (savedTwelve) document.getElementById('twelveDataKey').value = savedTwelve;
        
        await fetchRealXAUUSD();
        
        document.getElementById('fetchAndAnalyzeBtn').addEventListener('click', fetchDataAndRunGroqAnalysis);
        document.getElementById('autoAnalyzeBtn').addEventListener('click', toggleAutoAnalysis);
        document.getElementById('buyBtn').addEventListener('click', manualBuy);
        document.getElementById('sellBtn').addEventListener('click', manualSell);
        document.getElementById('manualRefreshPrice').addEventListener('click', fetchRealXAUUSD);
        document.getElementById('copyTradeDetails').addEventListener('click', copyTradeDetails);
        document.getElementById('saveGroqKey').addEventListener('click', saveKeys);
        document.getElementById('saveTwelveKey').addEventListener('click', saveKeys);
        
        // EXNESS buttons
        document.getElementById('openExnessPopupBtn').addEventListener('click', () => openExnessWindow('https://www.exness.com/trade/xauusd/', 900, 950));
        document.getElementById('openExnessMainBtn').addEventListener('click', () => openExnessWindow('https://www.exness.com/', 900, 950));
        document.getElementById('openExnessQuickBtn').addEventListener('click', () => openExnessWindow('https://www.exness.com/trade/xauusd/', 900, 950));
        document.getElementById('resizeGuideBtn').addEventListener('click', showSplitScreenGuide);
        document.getElementById('floatingHint').addEventListener('click', showSplitScreenGuide);
        
        addLog("✨ XAUUSD AI Scalper Ready!", 'success');
        addLog("💡 Click 'Open EXNESS' → use Windows Split Screen (Win+Arrow) for side-by-side trading", 'success');
        addLog("🔒 EXNESS cannot be embedded due to security policy - separate window is the only option", 'info');
    }

