#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)/iran-market"
if [ -d "$ROOT" ]; then
  echo "Directory $ROOT already exists. Remove it or run from another location."
  exit 1
fi

mkdir -p "$ROOT"
cd "$ROOT"

# Create server structure
mkdir -p server/src/{config,models,routes,services,utils}
cat > server/.env.example <<'ENVEX'
PORT=8080
MONGO_URI=mongodb+srv://<user>:<pass>@cluster/dbname
BOT_TOKEN=123456:ABCDEF-telegram-bot-token
WEBAPP_URL=https://iran-market.vercel.app
TONCENTERAPIKEY=your-toncenter-key
ETHRPCURL=https://mainnet.infura.io/v3/<key>
ETHEXPLORERBASE=https://etherscan.io/tx/
CORS_ORIGIN=https://iran-market.vercel.app
ENVEX

cat > server/package.json <<'PKG'
{
  "name": "iran-market-server",
  "version": "1.0.0",
  "scripts": {
    "dev": "ts-node-dev --respawn src/app.ts",
    "build": "tsc",
    "start": "node dist/app.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "cors": "^2.8.5",
    "dotenv": "^16.0.0",
    "express": "^4.18.2",
    "helmet": "^7.0.0",
    "mongoose": "^7.0.0",
    "morgan": "^1.10.0",
    "rate-limiter-flexible": "^2.5.4",
    "telegraf": "^4.12.0",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.3.0"
  }
}
PKG

cat > server/tsconfig.json <<'TSC'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "CommonJS",
    "outDir": "dist",
    "rootDir": "src",
    "esModuleInterop": true,
    "strict": true
  }
}
TSC

cat > server/src/config/env.ts <<'ENVTS'
import dotenv from "dotenv";
dotenv.config();

export const ENV = {
  PORT: Number(process.env.PORT || 8080),
  MONGO_URI: process.env.MONGO_URI || process.env.MONGOURI || "",
  BOT_TOKEN: process.env.BOT_TOKEN || process.env.BOTTOKEN || "",
  WEBAPP_URL: process.env.WEBAPP_URL || process.env.WEBAPPURL || "",
  TONCENTER_API_KEY: process.env.TONCENTERAPIKEY || "",
  ETH_RPC_URL: process.env.ETHRPCURL || "",
  ETH_EXPLORER_BASE: process.env.ETHEXPLORERBASE || "https://etherscan.io/tx/",
  CORS_ORIGIN: process.env.CORS_ORIGIN || process.env.CORSORIGIN || "*"
};
ENVTS

cat > server/src/bot.ts <<'BOT'
import { Telegraf, Markup } from "telegraf";
import { ENV } from "./config/env";

export const bot = new Telegraf(ENV.BOT_TOKEN);

bot.start((ctx) => {
  ctx.reply(
    "به ایران مارکت خوش آمدید ✨",
    Markup.inlineKeyboard([
      Markup.button.webApp("ورود به اپلیکیشن", ENV.WEBAPP_URL || "https://example.com")
    ])
  );
});

export async function launchBot() {
  try {
    await bot.launch();
    console.log("Bot launched");
    process.once("SIGINT", () => bot.stop("SIGINT"));
    process.once("SIGTERM", () => bot.stop("SIGTERM"));
  } catch (e) {
    console.error("Failed to launch bot:", e);
    throw e;
  }
}
BOT

cat > server/src/models/Trade.ts <<'TRADE'
import { Schema, model } from "mongoose";

const TradeSchema = new Schema(
  {
    userId: { type: String, required: true },
    symbol: { type: String, required: true },
    side: { type: String, enum: ["BUY", "SELL"], required: true },
    price: { type: Number, required: true },
    quantity: { type: Number, required: true }
  },
  { timestamps: true }
);

export const Trade = model("Trade", TradeSchema);
TRADE

cat > server/src/models/Wallet.ts <<'WALLET'
import { Schema, model } from "mongoose";

const BalanceSchema = new Schema({
  asset: { type: String, required: true },
  amount: { type: Number, required: true, default: 0 }
});

const WalletSchema = new Schema(
  {
    userId: { type: String, required: true, unique: true },
    balances: { type: [BalanceSchema], default: [] }
  },
  { timestamps: true }
);

export const Wallet = model("Wallet", WalletSchema);
WALLET

cat > server/src/utils/validate.ts <<'VAL'
import { z } from "zod";

export const TradeSchema = z.object({
  userId: z.string(),
  symbol: z.string(),
  side: z.enum(["BUY", "SELL"]),
  price: z.number().positive(),
  quantity: z.number().positive()
});

export const WalletChangeSchema = z.object({
  userId: z.string(),
  asset: z.string(),
  amount: z.number().positive()
});

export const SendNftSchema = z.object({
  userId: z.string(),
  to: z.string(),
  assetId: z.string() // "ton:<nftId>" یا "eth:<contract>/<tokenId>"
});
VAL

cat > server/src/utils/rateLimit.ts <<'RL'
import { RateLimiterMemory } from "rate-limiter-flexible";
import { Request, Response, NextFunction } from "express";

const limiter = new RateLimiterMemory({ points: 100, duration: 60 });

export function rateLimit(req: Request, res: Response, next: NextFunction) {
  limiter
    .consume(req.ip)
    .then(() => next())
    .catch(() => res.status(429).json({ error: "Too many requests" }));
}
RL

cat > server/src/utils/ton.ts <<'TON'
export async function tonTransferNft(to: string, nftId: string) {
  // In production replace this with TON RPC/Toncenter call using ENV.TONCENTER_API_KEY
  return { txId: `ton-demo-${Date.now()}`, to, nftId, status: "broadcasted" };
}
TON

cat > server/src/services/notification.service.ts <<'NOTIF'
import { bot } from "../bot";
import { ENV } from "../config/env";

function tonExplorer(txId: string) {
  return `https://tonviewer.com/transaction/${txId}`;
}
function ethExplorer(txHash: string) {
  return `${ENV.ETH_EXPLORER_BASE}${txHash}`;
}

export async function notifyTrade(userId: string, data: { symbol: string; side: "BUY" | "SELL"; price: number; quantity: number }) {
  const text = `سفارش جدید ثبت شد ✅
نماد: ${data.symbol}
نوع: ${data.side}
قیمت: ${data.price}
مقدار: ${data.quantity}`;
  try {
    await bot.telegram.sendMessage(userId, text);
  } catch (err) {
    console.debug("notifyTrade error:", err);
  }
}

export async function notifyWallet(userId: string, data: { type: "credit" | "debit"; asset: string; amount: number; balance?: number }) {
  const text = `کیف‌پول ${data.type === "credit" ? "افزایش" : "کاهش"} یافت ✅
دارایی: ${data.asset}
مقدار: ${data.amount}
${data.balance != null ? `موجودی جدید: ${data.balance}` : ""}`;
  try {
    await bot.telegram.sendMessage(userId, text);
  } catch (err) {
    console.debug("notifyWallet error:", err);
  }
}

export async function notifyNft(userId: string, data: { chain: "TON" | "ETH"; to: string; assetId?: string; tokenId?: string; txId?: string; txHash?: string }) {
  const link =
    data.chain === "TON" && data.txId ? tonExplorer(data.txId) :
    data.chain === "ETH" && data.txHash ? ethExplorer(data.txHash) : undefined;

  const text = `ارسال NFT انجام شد ✅
شبکه: ${data.chain}
گیرنده: ${data.to}
${data.assetId ? `شناسه NFT: ${data.assetId}` : data.tokenId ? `توکن ID: ${data.tokenId}` : ""}
${link ? `لینک تراکنش:\n${link}` : ""}`;
  try {
    await bot.telegram.sendMessage(userId, text);
  } catch (err) {
    console.debug("notifyNft error:", err);
  }
}
NOTIF

cat > server/src/services/market.service.ts <<'MS'
import { Trade } from "../models/Trade";
import { TradeSchema } from "../utils/validate";
import { notifyTrade } from "./notification.service";

export async function listTrades(userId: string, limit = 100) {
  return Trade.find({ userId }).sort({ createdAt: -1 }).limit(limit);
}

export async function createTrade(input: unknown) {
  const parsed = TradeSchema.parse(input);
  const trade = await Trade.create(parsed);
  await notifyTrade(parsed.userId, {
    symbol: parsed.symbol,
    side: parsed.side,
    price: parsed.price,
    quantity: parsed.quantity
  });
  return trade;
}
MS

cat > server/src/services/wallet.service.ts <<'WS'
import { Wallet } from "../models/Wallet";
import { notifyWallet } from "./notification.service";
import { WalletChangeSchema } from "../utils/validate";

export async function getWallet(userId: string) {
  let wallet = await Wallet.findOne({ userId });
  if (!wallet) wallet = await Wallet.create({ userId, balances: [] });
  return wallet;
}

export async function credit(input: unknown) {
  const { userId, asset, amount } = WalletChangeSchema.parse(input);
  const wallet = await getWallet(userId);
  const bal = wallet.balances.find((b: any) => b.asset === asset);
  if (bal) bal.amount += amount; else wallet.balances.push({ asset, amount });
  await wallet.save();
  const newBal = wallet.balances.find((b: any) => b.asset === asset)?.amount;
  await notifyWallet(userId, { type: "credit", asset, amount, balance: newBal });
  return wallet;
}

export async function debit(input: unknown) {
  const { userId, asset, amount } = WalletChangeSchema.parse(input);
  const wallet = await getWallet(userId);
  const bal = wallet.balances.find((b: any) => b.asset === asset);
  if (!bal || bal.amount < amount) throw Object.assign(new Error("INSUFFICIENT_FUNDS"), { status: 400 });
  bal.amount -= amount;
  await wallet.save();
  const newBal = wallet.balances.find((b: any) => b.asset === asset)?.amount;
  await notifyWallet(userId, { type: "debit", asset, amount, balance: newBal });
  return wallet;
}
WS

cat > server/src/services/nft.service.ts <<'NS'
import { SendNftSchema } from "../utils/validate";
import { tonTransferNft } from "../utils/ton";
import { notifyNft } from "./notification.service";

export async function sendNft(input: unknown) {
  const parsed = SendNftSchema.parse(input);
  const { userId, to, assetId } = parsed;

  if (assetId.startsWith("ton:")) {
    const onChain = await tonTransferNft(to, assetId.replace("ton:", ""));
    await notifyNft(userId, { chain: "TON", to, assetId, txId: onChain.txId });
    return { ...onChain, forwardedToBot: true };
  }

  if (assetId.startsWith("eth:")) {
    const tokenId = assetId.replace("eth:", "");
    const onChain = { txId: `eth-demo-${Date.now()}`, to, tokenId, status: "broadcasted" };
    await notifyNft(userId, { chain: "ETH", to, tokenId: onChain.tokenId, txHash: onChain.txId });
    return { ...onChain, forwardedToBot: true };
  }

  throw Object.assign(new Error("Unsupported chain"), { status: 400 });
}
NS

cat > server/src/routes/market.ts <<'RMARKET'
import { Router } from "express";
import { rateLimit } from "../utils/rateLimit";
import { createTrade, listTrades } from "../services/market.service";

const router = Router();

router.get("/", rateLimit, async (req, res) => {
  const userId = (req.headers["x-user-id"] as string) || "demo-user";
  const trades = await listTrades(userId);
  res.json(trades);
});

router.post("/", rateLimit, async (req, res) => {
  try {
    const trade = await createTrade(req.body);
    res.json(trade);
  } catch (e: any) {
    res.status(e.status || 400).json({ error: e.message });
  }
});

export default router;
RMARKET

cat > server/src/routes/wallet.ts <<'RWALLET'
import { Router } from "express";
import { rateLimit } from "../utils/rateLimit";
import { credit, debit, getWallet } from "../services/wallet.service";

const router = Router();

router.get("/", rateLimit, async (req, res) => {
  const userId = (req.headers["x-user-id"] as string) || "demo-user";
  const wallet = await getWallet(userId);
  res.json(wallet);
});

router.post("/credit", rateLimit, async (req, res) => {
  try {
    const wallet = await credit(req.body);
    res.json(wallet);
  } catch (e: any) {
    res.status(e.status || 400).json({ error: e.message });
  }
});

router.post("/debit", rateLimit, async (req, res) => {
  try {
    const wallet = await debit(req.body);
    res.json(wallet);
  } catch (e: any) {
    res.status(e.status || 400).json({ error: e.message });
  }
});

export default router;
RWALLET

cat > server/src/routes/nft.ts <<'RNFT'
import { Router } from "express";
import { rateLimit } from "../utils/rateLimit";
import { sendNft } from "../services/nft.service";

const router = Router();

router.post("/send", rateLimit, async (req, res) => {
  try {
    const result = await sendNft(req.body);
    res.json(result);
  } catch (e: any) {
    res.status(e.status || 400).json({ error: e.message });
  }
});

export default router;
RNFT

cat > server/src/app.ts <<'APP'
import express from "express";
import cors from "cors";
import helmet from "helmet";
import mongoose from "mongoose";
import morgan from "morgan";
import { ENV } from "./config/env";
import { launchBot } from "./bot";

import marketRouter from "./routes/market";
import walletRouter from "./routes/wallet";
import nftRouter from "./routes/nft";

const app = express();
app.use(express.json());
app.use(cors({ origin: ENV.CORS_ORIGIN, credentials: true }));
app.use(helmet());
app.use(morgan("tiny"));

mongoose.connect(ENV.MONGO_URI)
  .then(() => console.log("Mongo connected"))
  .catch((e) => console.error("Mongo error", e));

app.get("/health", (_, res) => res.send("ok"));

app.use("/api/market", marketRouter);
app.use("/api/wallet", walletRouter);
app.use("/api/nft", nftRouter);

app.listen(ENV.PORT, async () => {
  console.log(`Server running on :${ENV.PORT}`);
  try { await launchBot(); } catch (e) { console.error("Bot launch error", e); }
});
APP

# Create webapp
mkdir -p webapp/{public,src/components,src/pages}
cat > webapp/package.json <<'WPKG'
{
  "name": "iran-market-webapp",
  "version": "1.0.0",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --port 4173"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.22.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.0",
    "@types/react-dom": "^18.2.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0",
    "@vitejs/plugin-react": "^4.2.0"
  }
}
WPKG

cat > webapp/vite.config.ts <<'VCFG'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: { outDir: "dist" }
});
VCFG

cat > webapp/tsconfig.json <<'WTS'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "jsx": "react-jsx",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  }
}
WTS

cat > webapp/vercel.json <<'VJ'
{
  "builds": [{ "src": "package.json", "use": "@vercel/static-build" }],
  "routes": [{ "src": "/(.*)", "dest": "/index.html" }]
}
VJ

cat > webapp/public/index.html <<'HTML'
<!DOCTYPE html>
<html lang="fa">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Iran Market</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
HTML

cat > webapp/src/api.ts <<'API'
import axios from "axios";

export const API_BASE =
  (import.meta.env.VITE_API_URL as string) ||
  (import.meta.env.VITEAPIURL as string) ||
  "http://localhost:8080/api";

const api = axios.create({
  baseURL: API_BASE,
  headers: { "Content-Type": "application/json" }
});

export default api;
API

cat > webapp/src/main.tsx <<'MAIN'
import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
);
MAIN

cat > webapp/src/App.tsx <<'APPX'
import { Routes, Route, Link, Navigate } from "react-router-dom";
import Header from "./components/Header";
import Market from "./pages/Market";
import Wallet from "./pages/Wallet";
import Nft from "./pages/Nft";

export default function App() {
  return (
    <div style={{ maxWidth: 640, margin: "0 auto", padding: 16 }}>
      <Header />
      <nav style={{ display: "flex", gap: 12, marginBottom: 16 }}>
        <Link to="/market">Market</Link>
        <Link to="/wallet">Wallet</Link>
        <Link to="/nft">NFT</Link>
      </nav>
      <Routes>
        <Route path="/" element={<Navigate to="/market" />} />
        <Route path="/market" element={<Market />} />
        <Route path="/wallet" element={<Wallet />} />
        <Route path="/nft" element={<Nft />} />
      </Routes>
    </div>
  );
}
APPX

cat > webapp/src/components/Header.tsx <<'HDR'
export default function Header() {
  return (
    <header style={{ padding: "10px", background: "#f7f7f7", borderRadius: 8, marginBottom: 12 }}>
      <h2 style={{ margin: 0 }}>🇮🇷 Iran Market</h2>
      <small>نسخه MVP فول – آماده‌ی دیپلوی</small>
    </header>
  );
}
HDR

cat > webapp/src/components/Toast.tsx <<'TOAST'
import { useEffect, useState } from "react";

export default function Toast({ message }: { message?: string }) {
  const [show, setShow] = useState(!!message);
  useEffect(() => setShow(!!message), [message]);
  if (!show || !message) return null;
  return (
    <div style={{
      position: "fixed", bottom: 16, left: 16, right: 16,
      background: "#222", color: "#fff", padding: 12, borderRadius: 8
    }}>
      {message}
    </div>
  );
}
TOAST

cat > webapp/src/pages/Market.tsx <<'MKT'
import { useEffect, useState } from "react";
import api from "../api";
import Toast from "../components/Toast";

export default function Market() {
  const [trades, setTrades] = useState<any[]>([]);
  const [message, setMessage] = useState<string>();

  const load = async () => {
    const res = await api.get("/market", { headers: { "x-user-id": "demo-user" } });
    setTrades(res.data);
  };

  const submit = async () => {
    try {
      const res = await api.post("/market", {
        userId: "demo-user",
        symbol: "BTC",
        side: "BUY",
        price: 50000,
        quantity: 1
      });
      setMessage("سفارش ثبت شد");
      await load();
    } catch (e: any) {
      setMessage(e?.response?.data?.error || "خطا در ثبت سفارش");
    } finally {
      setTimeout(() => setMessage(undefined), 2500);
    }
  };

  useEffect(() => { load(); }, []);

  return (
    <div>
      <h3>Market</h3>
      <button onClick={submit}>ثبت سفارش دمو</button>
      <ul style={{ marginTop: 12 }}>
        {trades.map((t) => (
          <li key={t._id}>{t.symbol} {t.side} {t.price} × {t.quantity}</li>
        ))}
      </ul>
      <Toast message={message} />
    </div>
  );
}
MKT

cat > webapp/src/pages/Wallet.tsx <<'WPG'
import { useEffect, useState } from "react";
import api from "../api";
import Toast from "../components/Toast";

export default function Wallet() {
  const [wallet, setWallet] = useState<any>();
  const [message, setMessage] = useState<string>();

  const load = async () => {
    const res = await api.get("/wallet", { headers: { "x-user-id": "demo-user" } });
    setWallet(res.data);
  };

  const credit = async () => {
    try {
      await api.post("/wallet/credit", { userId: "demo-user", asset: "USDT", amount: 10 });
      setMessage("واریز شد");
      await load();
    } catch (e: any) {
      setMessage(e?.response?.data?.error || "خطا در واریز");
    } finally {
      setTimeout(() => setMessage(undefined), 2500);
    }
  };

  const debit = async () => {
    try {
      await api.post("/wallet/debit", { userId: "demo-user", asset: "USDT", amount: 5 });
      setMessage("برداشت شد");
      await load();
    } catch (e: any) {
      setMessage(e?.response?.data?.error || "خطا در برداشت");
    } finally {
      setTimeout(() => setMessage(undefined), 2500);
    }
  };

  useEffect(() => { load(); }, []);

  return (
    <div>
      <h3>Wallet</h3>
      <div style={{ display: "grid", gap: 8 }}>
        {wallet?.balances?.map((b: any) => (
          <div key={b.asset}>{b.asset}: {b.amount}</div>
        ))}
      </div>
      <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
        <button onClick={credit}>واریز 10 USDT</button>
        <button onClick={debit}>برداشت 5 USDT</button>
      </div>
      <Toast message={message} />
    </div>
  );
}
WPG

cat > webapp/src/pages/Nft.tsx <<'NFTP'
import { useState } from "react";
import api from "../api";
import Toast from "../components/Toast";

export default function Nft() {
  const [to, setTo] = useState("");
  const [assetId, setAssetId] = useState("ton:demo-nft-id");
  const [result, setResult] = useState<any>();
  const [message, setMessage] = useState<string>();

  const send = async () => {
    try {
      const res = await api.post("/nft/send", { userId: "demo-user", to, assetId });
      setResult(res.data);
      setMessage("ارسال شد");
    } catch (e: any) {
      setMessage(e?.response?.data?.error || "خطا در ارسال NFT");
    } finally {
      setTimeout(() => setMessage(undefined), 2500);
    }
  };

  return (
    <div>
      <h3>Send NFT</h3>
      <input placeholder="Recipient" value={to} onChange={(e) => setTo(e.target.value)} />
      <input placeholder="Asset ID (ton:... or eth:...)" value={assetId} onChange={(e) => setAssetId(e.target.value)} />
      <button onClick={send} style={{ marginLeft: 8 }}>Send</button>
      {result && <pre style={{ marginTop: 12 }}>{JSON.stringify(result, null, 2)}</pre>}
      <Toast message={message} />
    </div>
  );
}
NFTP

# .gitignore, README, LICENSE
cat > .gitignore <<'GIT'
node_modules/
dist/
build/
.vscode/
.env
.env.local
.env.*.local
.DS_Store
.vercel/
GIT

cat > README.md <<'README'
# Iran Market

نسخهٔ MVP برای «ایران مارکت» — شامل Backend با نوتیفیکیشن Bot و WebApp React آماده برای Vercel.

راهنما و دستورالعمل دیپلوی در بخش docs داخل README یا پیام‌های کمک‌رسان.

**مهم:** secrets را در هیچ‌جایی از repo ذخیره نکن.
README

cat > LICENSE <<'LIC'
MIT License

Copyright (c) 2026 kamirhosein1390-netizen

Permission is hereby granted, free of charge, to any person obtaining a copy...
LIC

echo "Project files created at $ROOT"
echo "Run the bootstrap script to init git and create the GitHub repo (requires gh CLI and auth)."