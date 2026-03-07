import * as admin from "firebase-admin";
import { onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";

admin.initializeApp();
const db = admin.firestore();
const _defaultWhatsappGraphVersion = process.env.WHATSAPP_GRAPH_VERSION ?? "v23.0";

type WhatsAppApiResponse = {
  messages?: Array<{ id?: string }>;
  error?: {
    message?: string;
    code?: number;
    type?: string;
    error_data?: { details?: string };
  };
};

function _ensureAuthenticated(uid: string | undefined): string {
  if (!uid) {
    throw new Error("unauthenticated");
  }
  return uid;
}

function _readWhatsappConfig(): {
  phoneNumberId: string;
  accessToken: string;
  graphVersion: string;
  verifyToken: string;
} {
  const phoneNumberId = String(process.env.WHATSAPP_PHONE_NUMBER_ID ?? "").trim();
  const accessToken = String(process.env.WHATSAPP_ACCESS_TOKEN ?? "").trim();
  const graphVersion = String(process.env.WHATSAPP_GRAPH_VERSION ?? _defaultWhatsappGraphVersion).trim();
  const verifyToken = String(process.env.WHATSAPP_VERIFY_TOKEN ?? "").trim();

  return {
    phoneNumberId,
    accessToken,
    graphVersion: graphVersion || _defaultWhatsappGraphVersion,
    verifyToken
  };
}

function _validateRecipient(raw: unknown): string {
  const value = String(raw ?? "").trim();
  const normalized = value.replaceAll(/\s+/g, "");
  const e164 = normalized.startsWith("+") ? normalized : `+${normalized}`;
  if (!/^\+[1-9]\d{6,14}$/.test(e164)) {
    throw new Error("invalid-recipient");
  }
  return e164;
}

async function _sendWhatsappMessage(payload: Record<string, unknown>): Promise<{
  messageId: string | null;
  raw: WhatsAppApiResponse;
}> {
  const config = _readWhatsappConfig();
  if (!config.phoneNumberId || !config.accessToken) {
    throw new Error(
      "whatsapp-not-configured: set WHATSAPP_PHONE_NUMBER_ID and WHATSAPP_ACCESS_TOKEN"
    );
  }

  const endpoint = `https://graph.facebook.com/${config.graphVersion}/${config.phoneNumberId}/messages`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.accessToken}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  const raw = (await response.json()) as WhatsAppApiResponse;
  if (!response.ok) {
    const errorMessage = raw.error?.message ?? "unknown-error";
    const details = raw.error?.error_data?.details ?? "";
    throw new Error(`whatsapp-api-error: ${errorMessage}${details ? ` (${details})` : ""}`);
  }

  return {
    messageId: raw.messages?.[0]?.id ?? null,
    raw
  };
}

export const issuePreKeyBundle = onCall(async (request) => {
  const uid = _ensureAuthenticated(request.auth?.uid);
  const deviceId = String(request.data.deviceId ?? "unknown");
  const docId = `${uid}_${deviceId}`;
  const payload = {
    uid,
    deviceId,
    preKey: request.data.preKey ?? "",
    signedPreKey: request.data.signedPreKey ?? "",
    updatedAt: Date.now()
  };
  await db.collection("prekeys").doc(docId).set(payload, { merge: true });
  return { ok: true, docId };
});

export const rotateSignedPreKey = onCall(async (request) => {
  const uid = _ensureAuthenticated(request.auth?.uid);
  const deviceId = String(request.data.deviceId ?? "unknown");
  const docId = `${uid}_${deviceId}`;
  await db.collection("prekeys").doc(docId).set(
    {
      signedPreKey: request.data.signedPreKey ?? "",
      rotatedAt: Date.now()
    },
    { merge: true }
  );
  return { ok: true };
});

export const linkDeviceStart = onCall(async (request) => {
  const uid = _ensureAuthenticated(request.auth?.uid);
  const token = Math.random().toString(36).slice(2, 10);
  await db.collection("users").doc(uid).collection("link_tokens").doc(token).set({
    createdAt: Date.now(),
    consumed: false
  });
  return { token };
});

export const linkDeviceConfirm = onCall(async (request) => {
  const uid = request.auth?.uid;
  const token = String(request.data.token ?? "");
  if (!uid || token.length === 0) {
    throw new Error("invalid-args");
  }
  await db.collection("users").doc(uid).collection("devices").doc(token).set(
    {
      linkedAt: Date.now(),
      publicIdentityKey: request.data.publicIdentityKey ?? ""
    },
    { merge: true }
  );
  return { ok: true };
});

export const backupKeyWrap = onCall(async (request) => {
  const uid = _ensureAuthenticated(request.auth?.uid);
  await db.collection("users").doc(uid).collection("backup").doc("active").set(
    {
      wrappedKey: request.data.wrappedKey ?? "",
      updatedAt: Date.now()
    },
    { merge: true }
  );
  return { ok: true };
});

export const backupKeyRestore = onCall(async (request) => {
  const uid = _ensureAuthenticated(request.auth?.uid);
  const doc = await db.collection("users").doc(uid).collection("backup").doc("active").get();
  return { wrappedKey: doc.data()?.wrappedKey ?? null };
});

export const sendCallInvite = onCall(async (request) => {
  const callId = String(request.data.callId ?? "");
  if (callId.length === 0) {
    throw new Error("invalid-call");
  }
  await db.collection("calls").doc(callId).set(
    {
      invite: true,
      updatedAt: Date.now()
    },
    { merge: true }
  );
  return { ok: true };
});

export const fanoutMessageEvent = onCall(async (request) => {
  const conversationId = String(request.data.conversationId ?? "");
  const messageId = String(request.data.messageId ?? "");
  if (conversationId.length === 0 || messageId.length === 0) {
    throw new Error("invalid-args");
  }
  logger.info("fanoutMessageEvent", { conversationId, messageId });
  return { ok: true };
});

export const outboxRetryAssist = onCall(async (request) => {
  const uid = _ensureAuthenticated(request.auth?.uid);
  const clientMessageId = String(request.data.clientMessageId ?? "");
  await db.collection("outbox_acks").doc(uid).collection("items").doc(clientMessageId).set(
    {
      updatedAt: Date.now(),
      acked: true
    },
    { merge: true }
  );
  return { ok: true };
});

export const expireStatus24h = onSchedule("every 15 minutes", async () => {
  const now = Date.now();
  const snapshot = await db.collectionGroup("items").where("expiresAt", "<=", now).get();
  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  logger.info("expireStatus24h done", { count: snapshot.size });
});

export const sendWhatsappText = onCall(async (request) => {
  const uid = _ensureAuthenticated(request.auth?.uid);
  const to = _validateRecipient(request.data.to);
  const body = String(request.data.body ?? "").trim();
  if (!body) {
    throw new Error("invalid-body");
  }

  const result = await _sendWhatsappMessage({
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to,
    type: "text",
    text: {
      body,
      preview_url: false
    }
  });

  logger.info("sendWhatsappText", {
    uid,
    to,
    messageId: result.messageId
  });
  return {
    ok: true,
    to,
    messageId: result.messageId,
    provider: "whatsapp-cloud-api"
  };
});

export const sendWhatsappTemplate = onCall(async (request) => {
  const uid = _ensureAuthenticated(request.auth?.uid);
  const to = _validateRecipient(request.data.to);
  const templateName = String(request.data.templateName ?? "").trim();
  const languageCode = String(request.data.languageCode ?? "en_US").trim();
  if (!templateName) {
    throw new Error("invalid-template-name");
  }

  const bodyParamsRaw = request.data.bodyParams;
  const bodyParams = Array.isArray(bodyParamsRaw)
    ? bodyParamsRaw.map((item) => String(item ?? "").trim()).filter((item) => item.length > 0)
    : [];

  const templatePayload: Record<string, unknown> = {
    name: templateName,
    language: {
      code: languageCode || "en_US"
    }
  };
  if (bodyParams.length > 0) {
    templatePayload.components = [
      {
        type: "body",
        parameters: bodyParams.map((text) => ({
          type: "text",
          text
        }))
      }
    ];
  }

  const result = await _sendWhatsappMessage({
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to,
    type: "template",
    template: templatePayload
  });

  logger.info("sendWhatsappTemplate", {
    uid,
    to,
    templateName,
    languageCode,
    bodyParamsCount: bodyParams.length,
    messageId: result.messageId
  });
  return {
    ok: true,
    to,
    templateName,
    messageId: result.messageId,
    provider: "whatsapp-cloud-api"
  };
});

export const whatsappWebhook = onRequest(async (request, response) => {
  const config = _readWhatsappConfig();

  if (request.method === "GET") {
    const mode = String(request.query["hub.mode"] ?? "");
    const verifyToken = String(request.query["hub.verify_token"] ?? "");
    const challenge = String(request.query["hub.challenge"] ?? "");

    if (!config.verifyToken) {
      logger.error("whatsappWebhook verify token not configured");
      response.status(500).send("verify-token-not-configured");
      return;
    }
    if (mode === "subscribe" && verifyToken === config.verifyToken) {
      response.status(200).send(challenge);
      return;
    }
    response.status(403).send("forbidden");
    return;
  }

  if (request.method !== "POST") {
    response.status(405).send("method-not-allowed");
    return;
  }

  const payload = (request.body ?? {}) as Record<string, unknown>;
  await db.collection("whatsapp_webhook_events").add({
    receivedAt: Date.now(),
    payload
  });

  logger.info("whatsappWebhookEvent", {
    hasEntry: Array.isArray(payload.entry),
    object: payload.object ?? null
  });
  response.status(200).send("EVENT_RECEIVED");
});
