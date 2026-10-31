import { basename } from "node:path";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

type Config = {
  sidecarUrl?: string;
  sidecarToken?: string;
  defaultElderId?: string;
  elderIdMap?: Record<string, string>;
  familyShareDefault?: boolean;
  allowRemoteMedia?: boolean;
  failClosed?: boolean;
};

// `before_dispatch` 的事件里不带 media（只有 content/body/channel/senderId 等），
// 但 `message_received` 的事件里带 media（path/contentType/kind）。两个事件都有 messageId，
// 这里用 messageId 把它们对上，再把图片交给侧车的 Qwen-VL 识别。
const mediaByMessageId = new Map<string, any[]>();
function messageKey(event: any, ctx: any): string {
  const account = String(event?.accountId ?? ctx?.accountId ?? "");
  const sender = String(event?.senderId ?? ctx?.senderId ?? "");
  const message = String(event?.messageId ?? "");
  return account && sender && message ? JSON.stringify([account, sender, message]) : "";
}

function channelOf(event: any, ctx: any): string {
  return String(
    event?.channelId ?? event?.channel ?? event?.provider ??
    event?.metadata?.channel ?? event?.metadata?.provider ?? event?.metadata?.surface ??
    ctx?.channelId ?? ""
  ).toLowerCase();
}

function isDirectWeixin(event: any, ctx: any): boolean {
  const channel = channelOf(event, ctx);
  if (!(channel === "openclaw-weixin" || channel === "weixin" || channel === "wechat")) return false;
  // openclaw-weixin 当前主要承载私聊；显式标记为群聊时不把健康资料送入侧车。
  const isGroup = Boolean(event?.isGroup ?? event?.groupId ?? event?.threadId?.startsWith?.("group:"));
  return !isGroup;
}

function textOf(event: any): string {
  return String(event?.bodyForAgent ?? event?.content ?? event?.text ?? event?.cleanedBody ?? "").trim();
}

// 参考 Tinypelican（github.com/Oii6111/Tinypelican）：不信任 contentType，
// 用魔数（magic bytes）判断真实类型，区分图片（png/jpg/gif/webp）和文件（pdf/docx 等）。
function sniffKind(bytes: Buffer, fallbackMime: string): { kind: "image" | "file"; mime: string } {
  const eq = (sig: number[], off = 0) => sig.every((b, j) => bytes[off + j] === b);
  if (bytes.length >= 8 && eq([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return { kind: "image", mime: "image/png" };
  if (bytes.length >= 3 && eq([0xff, 0xd8, 0xff])) return { kind: "image", mime: "image/jpeg" };
  if (bytes.length >= 4 && eq([0x47, 0x49, 0x46, 0x38])) return { kind: "image", mime: "image/gif" };
  if (bytes.length >= 12 && eq([0x52, 0x49, 0x46, 0x46]) && eq([0x57, 0x45, 0x42, 0x50], 8)) return { kind: "image", mime: "image/webp" };
  if (bytes.length >= 5 && eq([0x25, 0x50, 0x44, 0x46])) return { kind: "file", mime: "application/pdf" };
  if (bytes.length >= 4 && eq([0x50, 0x4b, 0x03, 0x04])) return { kind: "file", mime: "application/zip" };
  const mime = String(fallbackMime || "").toLowerCase();
  return mime.startsWith("image/")
    ? { kind: "image", mime: mime || "application/octet-stream" }
    : { kind: "file", mime: mime || "application/octet-stream" };
}

async function mediaToAttachment(media: any, allowRemoteMedia: boolean): Promise<any | null> {
  if (!media || typeof media !== "object") return null;
  const declaredMime = String(media.contentType ?? media.mimeType ?? "application/octet-stream");
  const filename = basename(String(media.path ?? media.filename ?? "media"));

  // OpenClaw 会先把远程媒体 staging 到本地；优先读本地 path，其次 data URL，最后才是远程抓取。
  let bytes: Buffer | null = null;
  if (media.path) {
    try { bytes = await readFile(String(media.path)); } catch { bytes = null; }
  }
  if (!bytes && media.url && String(media.url).startsWith("data:")) {
    const m = /^data:([^;]*);base64,(.*)$/.exec(String(media.url));
    if (m) bytes = Buffer.from(m[2], "base64");
  }
  if (!bytes && allowRemoteMedia && media.url) {
    try {
      const response = await fetch(String(media.url));
      if (response.ok) bytes = Buffer.from(await response.arrayBuffer());
    } catch { bytes = null; }
  }

  if (bytes) {
    const sniffed = sniffKind(bytes, declaredMime);
    if (sniffed.kind === "image") {
      return {
        kind: "image",
        filename,
        mime_type: sniffed.mime,
        data_url: `data:${sniffed.mime};base64,${bytes.toString("base64")}`,
        transcript: String(media.transcribed ?? ""),
        document_type: /药|medicine|medication/i.test(filename) ? "medication" : ""
      };
    }
    // 文件（PDF / docx 等）：只传元数据，不传整份 base64——侧车目前只识别图片。
    return {
      kind: "file",
      filename,
      mime_type: sniffed.mime,
      size: bytes.length,
      transcript: String(media.transcribed ?? "")
    };
  }

  // 语音有时只有转写，没有本地音频；保留转写即可。
  if (media.transcribed) return { kind: "voice", filename, mime_type: declaredMime, transcript: String(media.transcribed) };
  return null;
}

export default definePluginEntry({
  id: "elder-health-sidecar",
  name: "Elder Health Sidecar",
  description: "Keep elder Weixin chats simple and route health work to the safety-first Flask sidecar.",
  register(api) {
    const config = (api.pluginConfig ?? {}) as Config;
    const sidecarUrl = String(config.sidecarUrl ?? "http://127.0.0.1:8000").replace(/\/$/, "");
    const failClosed = config.failClosed !== false;
    const allowRemoteMedia = config.allowRemoteMedia === true;

    // 先在这里把带 media 的消息缓存下来，before_dispatch 里按 messageId 取回图片。
    api.on("message_received", (event: any, ctx: any) => {
      if (!isDirectWeixin(event, ctx)) return;
      const media = Array.isArray(event?.media) ? event.media : [];
      const mid = messageKey(event, ctx);
      if (mid) {
        if (media.length) mediaByMessageId.set(mid, media);
        else mediaByMessageId.delete(mid);
      }
      // 控制缓存大小，避免长期运行无限增长。
      if (mediaByMessageId.size > 200) {
        const oldest = mediaByMessageId.keys().next().value;
        if (oldest !== undefined) mediaByMessageId.delete(oldest);
      }
    });

    api.on("before_dispatch", async (event: any, ctx: any) => {
      if (!isDirectWeixin(event, ctx)) return;
      let mediaFacts = Array.isArray(event?.media) ? event.media : [];
      const mid = messageKey(event, ctx);
      if (!mediaFacts.length && mid && mediaByMessageId.has(mid)) {
        mediaFacts = mediaByMessageId.get(mid) ?? [];
        mediaByMessageId.delete(mid);
      }
      const senderId = String(event?.senderId ?? ctx?.senderId ?? "");
      const accountId = String(event?.accountId ?? ctx?.accountId ?? "");
      // 扫码绑定默认推导与侧车 ilink_binding.elder_ref 一致；仍可用 elderIdMap 覆盖。
      const key = JSON.stringify([accountId, senderId]);
      const elderId = config.elderIdMap?.[key] ?? (accountId && senderId ? "wx_" + createHash("sha256").update(key).digest("hex").slice(0, 24) : "");
      const bound = elderId && config.sidecarToken ? await fetch(`${sidecarUrl}/api/v1/elder/bound?elder_id=${encodeURIComponent(elderId)}`, { headers: { "X-Elder-Sidecar-Token": config.sidecarToken } }).then(r => r.json()).then(d => d?.bound === true).catch(() => false) : false;
      if (!accountId || !senderId || !elderId || !config.sidecarToken || !bound) {
        return { handled: true, text: "请先让家人协助完成账号绑定和授权，再使用健康助手。" };
      }
      // 图片交给侧车识别，文件只传元数据（侧车会引导老人改拍照片）；语音转写已经在 text 里了。
      const attachments = (await Promise.all(
        mediaFacts.map((m: any) => mediaToAttachment(m, allowRemoteMedia))
      )).filter(Boolean);
      const body = {
        elder_id: elderId,
        sender_id: senderId,
        channel_account_id: accountId,
        message_id: String(event?.messageId ?? ""),
        channel: "openclaw-weixin",
        text: textOf(event),
        attachments,
        consent: { family_share: config.familyShareDefault === true }
      };
      try {
        const headers: Record<string, string> = { "content-type": "application/json" };
        if (config.sidecarToken) headers["x-elder-sidecar-token"] = config.sidecarToken;
        const response = await fetch(`${sidecarUrl}/api/v1/elder/message`, {
          method: "POST",
          headers,
          body: JSON.stringify(body)
        });
        if (!response.ok) throw new Error(`sidecar ${response.status}`);
        const result = await response.json() as any;
        const reply = String(result?.reply ?? "").trim();
        return { handled: true, text: reply || "我收到了，稍后再回复你。" };
      } catch (error) {
        // 健康场景默认 fail-closed，避免侧车不可用时落回普通模型随意给医疗建议。
        if (failClosed) return { handled: true, text: "健康助手暂时休息一下，请先联系家人或医生；紧急情况请直接拨打 120。" };
        return;
      }
    });
  }
});
