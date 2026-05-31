// ========== QUANTUM EDGE PRO - AI ADAPTIVE STRATEGY + S/R SCALPING (TOP FX) ==========
// Updated asset list: XAUUSD, BTCUSD, EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD

let currentAsset = "", currentTf = "", accountBalance = null, riskPercent = null;
let groqApiKey = "", twelveApiKey = "";
let autoInterval = null, tvWidget = null, scalpInterval = null;
let logsEnabled = false;
let currentMarketSnapshot = { price: 0, rsi: 50, atr: 0, macdHist: 0, volatility: 0 };
let currentSignalData = { signal: "HOLD", price: 0, entry: 0, stopLoss: null, takeProfit: null, confidence: 0, confidenceLevel: "Low", reasoning: "", asset: "", timeframe: "", strategy: "" };

function showToast(msg) { 
    const toast = document.createElement('div'); 
    toast.className = 'toast-msg'; 
    toast.innerText = msg; 
    document.body.appendChild(toast); 
    setTimeout(() => toast.remove(), 2500); 
}
function addLog(msg, type='info') { 
    if(!logsEnabled) return; 
    const logDiv = document.getElementById('logArea'); 
    if(logDiv.classList.contains('empty')) { 
        logDiv.classList.remove('empty'); 
        logDiv.innerHTML = ''; 
    } 
    const entry = document.createElement('div'); 
    entry.style.padding = '6px 0'; 
    entry.style.borderBottom = '1px solid #1e293b'; 
    entry.style.fontSize = '0.75rem'; 
    const time = new Date().toLocaleTimeString(); 
    const icons = { signal: '🎯', error: '❌', success: '✅', warning: '⚠️', info: '🔹', send: '📨', scalp: '⚡', strategy: '🧠' }; 
    entry.innerHTML = `[${time}] ${icons[type] || '🔹'} ${msg}`; 
    logDiv.appendChild(entry); 
    entry.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); 
    while(logDiv.children.length > 80) logDiv.removeChild(logDiv.firstChild); 
}
function areAllParametersSelected() {
    const asset = document.getElementById('assetSelect').value;
    const tf = document.getElementById('timeframeSelect').value;
    const balance = document.getElementById('accountBalance').value;
    const risk = document.getElementById('riskPercent').value;
    const all = asset && tf && balance && parseFloat(balance) > 0 && risk && parseFloat(risk) > 0;
    document.getElementById('generateSignalBtn').disabled = !all;
    document.getElementById('autoRefreshBtn').disabled = !all;
    document.getElementById('scalpModeBtn').disabled = !all;
    const sendBtn = document.getElementById('sendSignalToWhatsAppBtn');
    if(all && currentSignalData.signal !== "HOLD" && currentSignalData.price > 0) sendBtn.disabled = false;
    else sendBtn.disabled = true;
    if(all) { 
        if(!logsEnabled) { logsEnabled = true; addLog("✅ Parameters ready", "success"); } 
        document.getElementById('paramsWarning').innerHTML = ''; 
    } else { 
        let missing = []; 
        if(!asset) missing.push("Asset"); 
        if(!tf) missing.push("Timeframe"); 
        if(!balance || parseFloat(balance) <= 0) missing.push("Balance"); 
        if(!risk || parseFloat(risk) <= 0) missing.push("Risk %"); 
        document.getElementById('paramsWarning').innerHTML = `⚠️ ${missing.join(", ")}`; 
        logsEnabled = false; 
        const logDiv = document.getElementById('logArea'); 
        logDiv.innerHTML = ''; 
        logDiv.classList.add('empty');
    }
    return all;
}
function updateParams() { 
    currentAsset = document.getElementById('assetSelect').value; 
    currentTf = document.getElementById('timeframeSelect').value; 
    accountBalance = parseFloat(document.getElementById('accountBalance').value); 
    riskPercent = parseFloat(document.getElementById('riskPercent').value); 
    areAllParametersSelected(); 
}
async function fetchRealTimeData(asset, tf) {
    const symbolMap = { XAUUSD: "XAU/USD", BTCUSD: "BTC/USD", EURUSD: "EUR/USD", GBPUSD: "GBP/USD", USDJPY: "USD/JPY", AUDUSD: "AUD/USD", USDCAD: "USD/CAD" };
    let interval = tf === "1min" ? "1min" : (tf === "5min" ? "5min" : (tf === "1day" ? "1day" : (tf === "4h" ? "4h" : (tf === "1h" ? "1h" : "15min"))));
    if(!twelveApiKey) return generateSimulatedData(asset);
    try {
        const url = `https://api.twelvedata.com/time_series?symbol=${symbolMap[asset]}&interval=${interval}&outputsize=100&apikey=${twelveApiKey}`;
        const resp = await fetch(url); 
        const json = await resp.json();
        if(!json.values || json.values.length < 30) throw new Error();
        let closes = [], highs = [], lows = [];
        for(let i = json.values.length - 1; i >= 0; i--) { 
            closes.push(parseFloat(json.values[i].close)); 
            highs.push(parseFloat(json.values[i].high)); 
            lows.push(parseFloat(json.values[i].low)); 
        }
        const price = closes[closes.length - 1];
        let gains = 0, losses = 0; 
        for(let i = closes.length - 14; i < closes.length - 1; i++) { 
            let diff = closes[i + 1] - closes[i]; 
            if(diff >= 0) gains += diff; 
            else losses -= diff; 
        }
        let rs = (gains / 14) / ((losses / 14) || 0.01); 
        let rsi = parseFloat((100 - 100 / (1 + rs)).toFixed(1));
        let tr = []; 
        for(let i = 1; i < highs.length; i++) tr.push(Math.max(highs[i] - lows[i], Math.abs(highs[i] - closes[i-1]), Math.abs(lows[i] - closes[i-1])));
        let atr = tr.slice(0,14).reduce((a,b) => a + b, 0) / 14; 
        for(let i = 14; i < tr.length; i++) atr = (atr * 13 + tr[i]) / 14;
        atr = parseFloat(atr.toFixed(asset === 'BTCUSD' ? 0 : (asset === 'USDJPY' ? 3 : 5)));
        let ema12 = closes.slice(-12).reduce((a,b) => a + b, 0) / 12;
        let ema26 = closes.slice(-26).reduce((a,b) => a + b, 0) / 26;
        let macdHist = (ema12 - ema26) * 0.5;
        let returns = [];
        for(let i = 1; i < closes.length; i++) returns.push((closes[i] - closes[i-1]) / closes[i-1]);
        let mean = returns.reduce((a,b) => a + b, 0) / returns.length;
        let variance = returns.reduce((a,b) => a + Math.pow(b - mean, 2), 0) / returns.length;
        let volatility = Math.sqrt(variance) * 100;
        let recentHighs = highs.slice(-20);
        let recentLows = lows.slice(-20);
        let resistance = Math.max(...recentHighs);
        let support = Math.min(...recentLows);
        return { price, rsi, atr, macdHist, volatility, support, resistance, closes, highs, lows };
    } catch(e) { 
        addLog(`Twelve Data error: using simulated`, "warning"); 
        return generateSimulatedData(asset); 
    }
}
function generateSimulatedData(asset) { 
    let baseMap = { XAUUSD:2380, BTCUSD:63500, EURUSD:1.089, GBPUSD:1.278, USDJPY:149.5, AUDUSD:0.663, USDCAD:1.358 };
    let base = baseMap[asset] || 1.2;
    let price = base + (Math.random() - 0.5) * base * 0.005; 
    let rsi = 45 + Math.random() * 30; 
    let atr = (asset === 'BTCUSD' ? 800 : base * 0.006);
    let volatility = 5 + Math.random() * 25;
    let support = price * 0.995;
    let resistance = price * 1.005;
    return { price, rsi: parseFloat(rsi.toFixed(1)), atr: parseFloat(atr.toFixed(asset === 'BTCUSD' ? 0 : 4)), macdHist: (Math.random() - 0.5) * 0.6, volatility, support, resistance };
}
function selectAdaptiveStrategy(data) {
    const rsi = data.rsi, macd = data.macdHist, volatility = data.volatility, price = data.price, support = data.support, resistance = data.resistance, atr = data.atr;
    let strategy = "", signal = "HOLD", reasoning = "", confidence = 50;
    const isTrending = Math.abs(macd) > 0.2;
    const nearSupport = price - support < (atr * 0.5);
    const nearResistance = resistance - price < (atr * 0.5);
    if (isTrending && macd > 0 && rsi < 65) { strategy = "TREND FOLLOWING - BULLISH"; signal = "BUY"; reasoning = `Bullish momentum, MACD positive.`; confidence = 75; }
    else if (isTrending && macd < 0 && rsi > 35) { strategy = "TREND FOLLOWING - BEARISH"; signal = "SELL"; reasoning = `Bearish momentum, MACD negative.`; confidence = 75; }
    else if (rsi > 70 && nearResistance) { strategy = "MEAN REVERSION - OVERBOUGHT"; signal = "SELL"; reasoning = `RSI overbought at resistance.`; confidence = 70; }
    else if (rsi < 30 && nearSupport) { strategy = "MEAN REVERSION - OVERSOLD"; signal = "BUY"; reasoning = `RSI oversold at support.`; confidence = 70; }
    else if (volatility > 20) { strategy = "VOLATILITY BREAKOUT"; signal = macd > 0 ? "BUY" : "SELL"; reasoning = `High volatility breakout.`; confidence = 60; }
    else { strategy = "CONSOLIDATION"; signal = "HOLD"; reasoning = `Mixed signals, awaiting clear bias.`; confidence = 40; }
    return { strategy, signal, reasoning, confidence };
}
function calculateSRScalpingSignals(data) {
    const rsi = data.rsi, price = data.price, atr = data.atr, support = data.support, resistance = data.resistance;
    let supportBounce = "HOLD", resistanceReject = "HOLD", supportTarget = null, resistanceTarget = null, rsiDivergence = "No divergence";
    const distToSupport = Math.abs(price - support) / atr;
    const distToResistance = Math.abs(resistance - price) / atr;
    if (rsi < 40 && distToSupport < 0.5) { supportBounce = "🔥 BOUNCE READY"; supportTarget = support + (atr * 0.8); }
    else if (rsi < 45 && distToSupport < 0.8) { supportBounce = "⚠️ WATCH - Near Support"; supportTarget = support + (atr * 0.5); }
    if (rsi > 60 && distToResistance < 0.5) { resistanceReject = "🔥 REJECT READY"; resistanceTarget = resistance - (atr * 0.8); }
    else if (rsi > 55 && distToResistance < 0.8) { resistanceReject = "⚠️ WATCH - Near Resistance"; resistanceTarget = resistance - (atr * 0.5); }
    if (rsi < 30 && distToSupport < 0.3) rsiDivergence = "🔄 BULLISH DIVERGENCE at support!";
    else if (rsi > 70 && distToResistance < 0.3) rsiDivergence = "🔄 BEARISH DIVERGENCE at resistance!";
    return { supportBounce, resistanceReject, supportLevel: support, resistanceLevel: resistance, supportTarget, resistanceTarget, rsiDivergence };
}
async function refreshSignal() {
    if(!areAllParametersSelected()) return;
    addLog(`Fetching ${currentAsset} (${currentTf})...`, "info");
    const data = await fetchRealTimeData(currentAsset, currentTf);
    if(!data) return;
    currentMarketSnapshot = { price: data.price, rsi: data.rsi, atr: data.atr, macdHist: data.macdHist, volatility: data.volatility, support: data.support, resistance: data.resistance };
    const priceFormatted = currentAsset === 'BTCUSD' ? `$${data.price.toFixed(0)}` : `$${data.price.toFixed(currentAsset === 'USDJPY' ? 3 : 2)}`;
    document.getElementById('currentPrice').innerHTML = priceFormatted;
    document.getElementById('rsiValue').innerHTML = data.rsi;
    document.getElementById('atrValue').innerHTML = currentAsset === 'BTCUSD' ? `$${data.atr.toFixed(0)}` : `$${data.atr.toFixed(4)}`;
    let signal = "HOLD", reasoning = "", strategy = "", confidence = { score: 50, level: "Medium" };
    const isScalping = currentTf === '1min' || currentTf === '5min';
    if (isScalping) {
        const scalp = calculateSRScalpingSignals(data);
        strategy = "S/R SCALPING + RSI";
        if (scalp.supportBounce.includes("READY")) { signal = "SCALP-LONG"; reasoning = `Support bounce setup at ${data.support.toFixed(4)}`; confidence.score = 75; }
        else if (scalp.resistanceReject.includes("READY")) { signal = "SCALP-SHORT"; reasoning = `Resistance rejection at ${data.resistance.toFixed(4)}`; confidence.score = 75; }
        else { signal = "HOLD"; reasoning = `Wait for key levels. S:${data.support.toFixed(4)} R:${data.resistance.toFixed(4)}`; confidence.score = 30; }
        document.getElementById('supportBounceSignal').innerHTML = scalp.supportBounce;
        document.getElementById('resistanceRejectSignal').innerHTML = scalp.resistanceReject;
        document.getElementById('supportLevel').innerHTML = `Support: ${currentAsset === 'BTCUSD' ? `$${scalp.supportLevel.toFixed(0)}` : `$${scalp.supportLevel.toFixed(4)}`}`;
        document.getElementById('resistanceLevel').innerHTML = `Resistance: ${currentAsset === 'BTCUSD' ? `$${scalp.resistanceLevel.toFixed(0)}` : `$${scalp.resistanceLevel.toFixed(4)}`}`;
        if(scalp.supportTarget) document.getElementById('supportTarget').innerHTML = `Target: ${currentAsset === 'BTCUSD' ? `$${scalp.supportTarget.toFixed(0)}` : `$${scalp.supportTarget.toFixed(4)}`}`;
        if(scalp.resistanceTarget) document.getElementById('resistanceTarget').innerHTML = `Target: ${currentAsset === 'BTCUSD' ? `$${scalp.resistanceTarget.toFixed(0)}` : `$${scalp.resistanceTarget.toFixed(4)}`}`;
        document.getElementById('rsiDivergence').innerHTML = scalp.rsiDivergence;
        document.getElementById('rsiValueDisplay').innerHTML = `RSI: ${data.rsi.toFixed(0)}`;
        confidence.level = confidence.score >= 70 ? "High" : (confidence.score >= 50 ? "Medium" : "Low");
    } else {
        const adaptive = selectAdaptiveStrategy(data);
        strategy = adaptive.strategy; signal = adaptive.signal; reasoning = adaptive.reasoning; confidence.score = adaptive.confidence;
        confidence.level = adaptive.confidence >= 70 ? "High" : (adaptive.confidence >= 50 ? "Medium" : "Low");
        document.getElementById('supportBounceSignal').innerHTML = "--"; document.getElementById('resistanceRejectSignal').innerHTML = "--";
        document.getElementById('rsiDivergence').innerHTML = "AI Adaptive Mode Active";
        document.getElementById('rsiValueDisplay').innerHTML = `RSI: ${data.rsi.toFixed(0)}`;
    }
    document.getElementById('activeStrategy').innerHTML = strategy;
    document.getElementById('strategyDisplay').innerHTML = strategy.substring(0, 35);
    const stopLoss = (signal === 'BUY' || signal === 'SCALP-LONG') ? data.price - data.atr * 1.2 : ((signal === 'SELL' || signal === 'SCALP-SHORT') ? data.price + data.atr * 1.2 : null);
    const takeProfit = (signal === 'BUY' || signal === 'SCALP-LONG') ? data.price + data.atr * 2.5 : ((signal === 'SELL' || signal === 'SCALP-SHORT') ? data.price - data.atr * 2.5 : null);
    let lotSize = 0, riskAmt = 0, rewardAmt = 0;
    if(stopLoss && accountBalance) { 
        let riskPerUnit = Math.abs(data.price - stopLoss); let riskDollars = (riskPercent / 100) * accountBalance; 
        let raw = riskDollars / riskPerUnit; 
        lotSize = Math.min(5, Math.max(0.01, parseFloat((currentAsset === 'XAUUSD' ? raw / 100 : currentAsset === 'BTCUSD' ? raw / riskPerUnit : raw / 100000).toFixed(2)))); 
        riskAmt = lotSize * riskPerUnit; rewardAmt = riskAmt * 2.5; 
    }
    currentSignalData = { signal, price: data.price, entry: data.price, stopLoss, takeProfit, confidence: confidence.score, confidenceLevel: confidence.level, reasoning, asset: currentAsset, timeframe: currentTf, strategy };
    document.getElementById('signalMain').className = `signal-badge ${signal}`; document.getElementById('signalMain').innerHTML = signal;
    document.getElementById('entryPrice').innerHTML = priceFormatted; document.getElementById('confidenceScore').innerHTML = `${confidence.score}%`;
    document.getElementById('confidenceFill').style.width = `${confidence.score}%`;
    document.getElementById('maxLotSize').innerHTML = lotSize.toFixed(2); document.getElementById('riskAmount').innerHTML = riskAmt.toFixed(2); document.getElementById('rewardAmount').innerHTML = rewardAmt.toFixed(2);
    if(stopLoss) document.getElementById('stopLossValue').innerHTML = currentAsset === 'BTCUSD' ? `$${stopLoss.toFixed(0)}` : `$${stopLoss.toFixed(4)}`;
    if(takeProfit) document.getElementById('takeProfitValue').innerHTML = currentAsset === 'BTCUSD' ? `$${takeProfit.toFixed(0)}` : `$${takeProfit.toFixed(4)}`;
    document.getElementById('reasoningText').innerHTML = `🧠 ${reasoning} | R:R 2.5:1`;
    document.getElementById('assetNameDisplay').innerHTML = currentAsset; document.getElementById('timeframeDisplay').innerHTML = ` • ${currentTf}`;
    updateVolatilityDisplay(data.volatility, strategy);
    addLog(`${currentAsset} | ${signal} @ ${priceFormatted} | ${strategy.substring(0,40)}`, "strategy");
    updateChart();
    const sendBtn = document.getElementById('sendSignalToWhatsAppBtn');
    if(signal !== "HOLD") sendBtn.disabled = false; else sendBtn.disabled = true;
}
function updateVolatilityDisplay(volatility, strategyName) {
    document.getElementById('volatilityValue').innerHTML = volatility.toFixed(2)+'%';
    document.getElementById('strategyDisplay').innerHTML = strategyName.substring(0,30);
    const badgeElem = document.getElementById('volatilityBadge');
    if (volatility > 20) { badgeElem.className = 'volatility-badge volatility-high'; badgeElem.innerHTML = 'HIGH VOLATILITY ⚠️'; }
    else if (volatility > 12) { badgeElem.className = 'volatility-badge volatility-medium'; badgeElem.innerHTML = 'MEDIUM VOLATILITY ⚡'; }
    else { badgeElem.className = 'volatility-badge volatility-low'; badgeElem.innerHTML = 'LOW VOLATILITY ✓'; }
}
function startScalpingMode() {
    if(scalpInterval) { clearInterval(scalpInterval); scalpInterval = null; addLog("Scalping mode stopped", "info"); showToast("Scalping mode stopped"); }
    else { scalpInterval = setInterval(() => { if(currentAsset && currentTf) refreshSignal(); }, 15000); addLog("⚡ S/R Scalping mode ACTIVE", "scalp"); showToast("Scalping mode activated!"); }
    const btn = document.getElementById('scalpModeBtn'); btn.innerHTML = scalpInterval ? "⏹️ STOP SCALP" : "⚡ SCALP MODE"; btn.style.background = scalpInterval ? "#ef4444" : "#f59e0b";
}
function updateChart() { 
    if(!currentAsset) return; 
    const tvMap = { XAUUSD: "OANDA:XAUUSD", BTCUSD: "BITSTAMP:BTCUSD", EURUSD: "FX:EURUSD", GBPUSD: "FX:GBPUSD", USDJPY: "FX:USDJPY", AUDUSD: "FX:AUDUSD", USDCAD: "FX:USDCAD" }; 
    if(tvWidget) try { tvWidget.remove(); } catch(e) {} 
    document.getElementById('tv-chart-container').innerHTML = ''; 
    if(tvMap[currentAsset] && currentTf) { 
        const intMap = { "1min": "1", "5min": "5", "15min": "15", "1h": "60", "4h": "240", "1day": "1D" }; 
        tvWidget = new TradingView.widget({ width: '100%', height: 420, symbol: tvMap[currentAsset], interval: intMap[currentTf] || "60", theme: 'dark', style: '1', locale: 'en', container_id: 'tv-chart-container', studies: ['RSI@tv-basicstudies', 'MACD@tv-basicstudies'] }); 
    } 
}
function formatWhatsAppMessage() {
    const s = currentSignalData; const emoji = s.signal === "BUY" ? "🚀 BUY" : (s.signal === "SELL" ? "📉 SELL" : (s.signal === "SCALP-LONG" ? "⚡ SCALP LONG" : (s.signal === "SCALP-SHORT" ? "⚡ SCALP SHORT" : "⏸️ HOLD")));
    const priceFormatted = s.asset === 'BTCUSD' ? `$${s.price.toFixed(0)}` : `$${s.price.toFixed(4)}`;
    const slFormatted = s.stopLoss ? (s.asset === 'BTCUSD' ? `$${s.stopLoss.toFixed(0)}` : `$${s.stopLoss.toFixed(4)}`) : 'N/A';
    const tpFormatted = s.takeProfit ? (s.asset === 'BTCUSD' ? `$${s.takeProfit.toFixed(0)}` : `$${s.takeProfit.toFixed(4)}`) : 'N/A';
    let confidenceMsg = s.confidence >= 70 ? "✅ HIGH CONFIDENCE" : (s.confidence >= 50 ? "⚠️ MEDIUM CONFIDENCE" : "❌ LOW CONFIDENCE");
    return `⚡ *QUANTUM EDGE SIGNAL* ⚡%0A%0A📊 *Asset:* ${s.asset}%0A⏱️ *Timeframe:* ${s.timeframe || currentTf}%0A🧠 *Strategy:* ${s.strategy || 'AI Adaptive'}%0A🎯 *Signal:* ${emoji}%0A💰 *Entry:* ${priceFormatted}%0A🔒 *Stop Loss:* ${slFormatted}%0A🎯 *Take Profit:* ${tpFormatted}%0A🎲 *Confidence:* ${s.confidence}% (${s.confidenceLevel}) - ${confidenceMsg}%0A💡 *Analysis:* ${s.reasoning.substring(0,150)}%0A📐 *Risk-Reward:* 2.5:1%0A🕐 ${new Date().toLocaleString()}%0A%0ATrade responsibly. Always use stop-loss.`;
}
async function sendWhatsAppSignal() {
    if (currentSignalData.signal === "HOLD" || currentSignalData.price === 0) { showToast("⚠️ No valid signal. Generate a signal first."); return; }
    const method = document.querySelector('input[name="sendMethod"]:checked').value;
    const message = formatWhatsAppMessage();
    if (method === "picker") { window.open(`https://wa.me/?text=${message}`, '_blank'); addLog("📱 Opened WhatsApp contact picker", "send"); }
    else if (method === "direct") { let number = document.getElementById('directNumber').value.trim(); if(!number) { showToast("❌ Enter number"); return; } let cleanNumber = number.replace(/[^0-9+]/g, ''); if (!cleanNumber.startsWith('+')) cleanNumber = '+' + cleanNumber; window.open(`https://wa.me/${encodeURIComponent(cleanNumber)}?text=${message}`, '_blank'); addLog(`📱 Opened WhatsApp for ${cleanNumber}`, "send"); }
    else if (method === "api") { const apiKey = document.getElementById('apiKeyInput').value.trim(); let number = document.getElementById('directNumber').value.trim(); if (!number || !apiKey) { showToast("❌ Missing number or API key"); return; } let cleanNumber = number.replace(/[^0-9+]/g, ''); if (cleanNumber.startsWith('+')) cleanNumber = cleanNumber.substring(1); const textMsg = formatWhatsAppMessage().replace(/%0A/g, '\n').replace(/%20/g, ' '); try { const response = await fetch(`https://api.callmebot.com/whatsapp.php?phone=${cleanNumber}&text=${encodeURIComponent(textMsg)}&apikey=${apiKey}`); const result = await response.text(); if (result.includes("OK")) { addLog(`✅ Auto-sent signal to ${number}`, "success"); showToast("✅ Signal sent!"); } else addLog(`⚠️ API error`, "warning"); } catch(e) { addLog(`❌ API failed`, "error"); } }
}
async function askMarketAI(userQuestion) {
    const q = userQuestion.toLowerCase();
    if(q.includes('strategy') || q.includes('adaptive')) return `🧠 **AI ADAPTIVE STRATEGY**\nScalping (1-5min): S/R + RSI.\nHigher TF: Trend Following, Mean Reversion, Volatility Breakout. Current: ${currentSignalData.strategy || 'Select asset'}`;
    if(q.includes('support') || q.includes('resistance')) return `📊 **S/R LEVELS:** ${currentAsset ? `${currentAsset} Support: ${currentMarketSnapshot.support?.toFixed(4)} Resistance: ${currentMarketSnapshot.resistance?.toFixed(4)}` : 'Select asset first'}\nScalping: LONG at support RSI<40, SHORT at resistance RSI>60.`;
    return `🤖 **AI READY**\nAsset: ${currentAsset || 'None'} | Signal: ${currentSignalData.signal || '--'}\nAsk about strategy, S/R, market conditions.`;
}
// Chat UI
const modal = document.getElementById('aiChatModal');
const floatingBtn = document.getElementById('floatingAiBtn');
const closeBtn = document.getElementById('closeChatBtn');
const chatArea = document.getElementById('chatMessagesArea');
const sendChatBtn = document.getElementById('sendChatMsgBtn');
const chatInput = document.getElementById('chatQuestionInput');
function addChatBubble(text, isUser) { const bubble = document.createElement('div'); bubble.className = `chat-bubble ${isUser ? 'user-bubble' : 'ai-bubble'}`; bubble.innerHTML = text.replace(/\n/g, '<br>'); chatArea.appendChild(bubble); chatArea.scrollTop = chatArea.scrollHeight; }
async function handleChatQuestion() { const q = chatInput.value.trim(); if(!q) return; addChatBubble(q, true); chatInput.value = ''; const loadingDiv = document.createElement('div'); loadingDiv.className = 'chat-bubble ai-bubble'; loadingDiv.innerHTML = "🤔 Analyzing..."; chatArea.appendChild(loadingDiv); chatArea.scrollTop = chatArea.scrollHeight; const answer = await askMarketAI(q); loadingDiv.remove(); addChatBubble(answer, false); }
function quickPromptHandler(e) { const q = e.currentTarget.getAttribute('data-q'); if(q) { chatInput.value = q; handleChatQuestion(); } }
// Event listeners
document.getElementById('saveGroqBtn').onclick = () => { let k = document.getElementById('groqApiKeyInput').value.trim(); if(k){ groqApiKey=k; localStorage.setItem('groq_api_key',k); addLog("Groq API saved","success"); showToast("Groq key saved"); } };
document.getElementById('saveTwelveBtn').onclick = () => { let k = document.getElementById('twelveApiKeyInput').value.trim(); if(k){ twelveApiKey=k; localStorage.setItem('twelve_api_key',k); addLog("Twelve Data API saved","success"); showToast("Twelve Data key saved"); } };
document.getElementById('generateSignalBtn').onclick = refreshSignal;
document.getElementById('autoRefreshBtn').onclick = () => { if(autoInterval){ clearInterval(autoInterval); autoInterval=null; addLog("Auto refresh stopped","info"); } else { autoInterval=setInterval(refreshSignal,30*60*1000); refreshSignal(); addLog("Auto refresh started (30min)","success"); } };
document.getElementById('scalpModeBtn').onclick = startScalpingMode;
document.getElementById('sendSignalToWhatsAppBtn').onclick = sendWhatsAppSignal;
document.getElementById('assetSelect').onchange = updateParams;
document.getElementById('timeframeSelect').onchange = updateParams;
document.getElementById('accountBalance').onchange = updateParams;
document.getElementById('riskPercent').onchange = updateParams;
document.querySelectorAll('input[name="sendMethod"]').forEach(r=>r.onchange=()=>{ const m=document.querySelector('input[name="sendMethod"]:checked').value; document.getElementById('directInputArea').style.display=(m==="direct"||m==="api")?"block":"none"; document.getElementById('apiKeyArea').style.display=(m==="api")?"block":"none"; });
floatingBtn.onclick = () => modal.classList.remove('hidden');
closeBtn.onclick = () => modal.classList.add('hidden');
sendChatBtn.onclick = handleChatQuestion;
chatInput.addEventListener('keypress', (e) => { if(e.key === 'Enter') handleChatQuestion(); });
document.querySelectorAll('.quick-prompt').forEach(el => el.addEventListener('click', quickPromptHandler));
if(localStorage.getItem('groq_api_key')) { groqApiKey = localStorage.getItem('groq_api_key'); document.getElementById('groqApiKeyInput').value = groqApiKey; }
if(localStorage.getItem('twelve_api_key')) { twelveApiKey = localStorage.getItem('twelve_api_key'); document.getElementById('twelveApiKeyInput').value = twelveApiKey; }
updateParams();
addLog("✅ AI Adaptive System Ready | Top Pairs: EURUSD, GBPUSD, USDJPY, AUDUSD, USDCAD + XAU & BTC", "success");
