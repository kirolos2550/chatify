import * as admin from "firebase-admin";
import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";

admin.initializeApp();
const db = admin.firestore();

export const issuePreKeyBundle = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("unauthenticated");
  }
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
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("unauthenticated");
  }
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
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("unauthenticated");
  }
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
  if (!uid || token.isEmpty) {
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
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("unauthenticated");
  }
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
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("unauthenticated");
  }
  const doc = await db.collection("users").doc(uid).collection("backup").doc("active").get();
  return { wrappedKey: doc.data()?.wrappedKey ?? null };
});

export const sendCallInvite = onCall(async (request) => {
  const callId = String(request.data.callId ?? "");
  if (callId.isEmpty) {
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
  if (conversationId.isEmpty || messageId.isEmpty) {
    throw new Error("invalid-args");
  }
  logger.info("fanoutMessageEvent", { conversationId, messageId });
  return { ok: true };
});

export const outboxRetryAssist = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new Error("unauthenticated");
  }
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

