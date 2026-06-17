import os
from google.cloud import firestore as google_firestore
import firebase_admin
from firebase_admin import credentials, firestore
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
import json
from datetime import datetime, timedelta
from crypto_engine import AegisQEngine

# Initialize AegisQ engine
engine = AegisQEngine()

# Initialize Firebase Admin
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate("serviceAccountKey.json")
        firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"Firebase init error: {e}")

db = firestore.client()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Active connections: {conversation_id: [websocket1, websocket2, ...]}
connections = {}

@app.get("/")
async def root():
    return {"status": "AegisQ Backend Active", "engine": "ML-KEM-1024 + Double Ratchet"}

@app.get("/server-kem-pk")
async def get_server_pk():
    return {
        "pk_768": engine.kem_768.pk.hex(),
        "pk_1024": engine.kem_1024.pk.hex()
    }

@app.websocket("/ws/{conversation_id}")
async def websocket_endpoint(ws: WebSocket, conversation_id: str):
    print(f"[WS] New connection attempt for: {conversation_id}")
    await ws.accept()
    
    if conversation_id not in connections:
        connections[conversation_id] = []
    connections[conversation_id].append(ws)

    try:
        while True:
            try:
                data = await ws.receive_text()
                if not data:
                    continue
                    
                packet = json.loads(data)
                msg_type = packet.get("type")

                # 1) Handshake / Init
                if msg_type == "init":
                    try:
                        ct_hex = packet.get("client_ct_hex")
                        escalate = packet.get("escalate", False)
                        client_ct = bytes.fromhex(ct_hex)
                        engine.init_session(conversation_id, client_ct, escalate=escalate)
                        
                        db.collection("sessions").document(conversation_id).set({
                            "status": "active",
                            "last_init": firestore.SERVER_TIMESTAMP,
                            "kem_level": "1024" if escalate else "768"
                        })

                        await ws.send_text(json.dumps({
                            "type": "init_ok",
                            "message": "Security established",
                            "security_info": {"ml_kem_handshake": True, "root_key_established": True}
                        }))
                    except Exception as e:
                        print(f"[KEM] Handshake Error: {e}")
                        await ws.send_text(json.dumps({"type": "error", "message": str(e)}))

                # 2) Encrypted Messages
                elif msg_type == "message":
                    text = packet.get("text")
                    image = packet.get("imageBase64")
                    is_one_time = packet.get("isOneTime", False)
                    disappear_duration = packet.get("disappearDuration")
                    sender_id = packet.get("senderId", "unknown")

                    content = text if text else image
                    if not content: continue

                    payload = engine.encrypt_message(conversation_id, content.encode())
                    
                    expires_at = None
                    if disappear_duration:
                        expires_at = datetime.utcnow() + timedelta(seconds=int(disappear_duration))

                    db_data = {
                        "senderId": sender_id,
                        "ciphertext": payload["ciphertext"],
                        "signature": payload.get("signature"),
                        "header": payload.get("header"),
                        "nonce": payload.get("nonce"), 
                        "dh_pub": payload.get("dh_pub"), 
                        "timestamp": firestore.SERVER_TIMESTAMP,
                        "isOneTime": is_one_time,
                        "expiresAt": expires_at,
                        "viewed": False
                    }
                    
                    # 1. Use Canonical ID for 1-on-1 chats to ensure sync with frontend
                    target_cid = conversation_id
                    if not conversation_id.startswith("group_") and "_" in conversation_id:
                        uids = conversation_id.split("_")
                        if len(uids) == 2:
                            uids.sort()
                            target_cid = f"{uids[0]}_{uids[1]}"

                    # 2. Add message to Firestore
                    db.collection("chats").document(target_cid).collection("messages").add(db_data)

                    # 3. Update Preview and Unread Counts
                    preview = "🔒 Photo" if image else "🔒 Message"
                    chat_ref = db.collection("chats").document(target_cid)
                    
                    chat_doc = chat_ref.get()
                    participants = []
                    if chat_doc.exists:
                        participants = chat_doc.to_dict().get("participants", [])
                    
                    # Fallback for 1-on-1 chats: derive participants from ID if missing
                    if not participants and "_" in target_cid:
                        participants = target_cid.split("_")
                    
                    # Update metadata
                    update_data = {
                        "lastMessage": preview,
                        "lastMessageCiphertext": payload["ciphertext"],
                        "lastMessageTime": firestore.SERVER_TIMESTAMP,
                        "lastMessageSenderId": sender_id,
                        "participants": participants
                    }
                    
                    # Ensure participants are found for unread incrementing
                    if not participants:
                        chat_snap = chat_ref.get()
                        if chat_snap.exists:
                            participants = list(chat_snap.to_dict().get('participants', []))

                    final_updates = {
                        "lastMessage": preview,
                        "lastMessageTime": firestore.SERVER_TIMESTAMP,
                        "lastMessageSenderId": sender_id,
                    }
                    if participants:
                        for p_id in participants:
                            if p_id and p_id != sender_id:
                                final_updates[f"unreadCount.{p_id}"] = firestore.Increment(1)
                    
                    chat_ref.set({"participants": participants}, merge=True)
                    chat_ref.update(final_updates)

                    # Broadcast
                    for conn in connections.get(conversation_id, []):
                        try:
                            await conn.send_text(json.dumps({
                                "type": "secure_message",
                                **payload,
                                "text": text,
                                "imageBase64": image,
                                "senderId": sender_id
                            }))
                        except: pass

                # 3) Deletion
                elif msg_type == "delete":
                    msg_id = packet.get("message_id")
                    if msg_id:
                        msg_ref = db.collection("chats").document(conversation_id).collection("messages").document(msg_id)
                        if msg_ref.get().exists:
                            msg_ref.delete()
                            for conn in connections.get(conversation_id, []):
                                try: await conn.send_text(json.dumps({"type": "message_deleted", "message_id": msg_id}))
                                except: pass
                            # Quietly try to update preview
                            try:
                                last = db.collection("chats").document(conversation_id).collection("messages").order_by("timestamp", descending=True).limit(1).get()
                                chat_ref = db.collection("chats").document(conversation_id)
                                if not last:
                                    chat_ref.update({"lastMessage": "", "lastMessageStatus": "deleted"})
                                else:
                                    chat_ref.update({"lastMessage": "This message was deleted", "lastMessageStatus": "deleted"})
                            except: pass

                # 4) Clear Chat - Personal clearing is handled by the frontend via clearedAt timestamps
                elif msg_type == "clear_chat":
                    # We no longer delete from Firestore here to support personal clearing.
                    # Frontend updates its own 'clearedAt' timestamp in the chat document.
                    # We only broadcast the event so active clients can refresh their UI if needed.
                    for conn in connections.get(conversation_id, []):
                        try: await conn.send_text(json.dumps({"type": "chat_cleared"}))
                        except: pass

                elif msg_type == "decrypt_batch":
                    items = packet.get("items", [])
                    results = []
                    for item in items:
                        try:
                            cid = item.get("chatId")
                            mid = item.get("messageId")
                            if cid and mid and cid in engine.sessions:
                                # Fetch full message data from Firestore
                                msg_doc = db.collection("chats").document(cid).collection("messages").document(mid).get()
                                if msg_doc.exists:
                                    payload = msg_doc.to_dict()
                                    # For batch catch-up, we ignore signature failures if the keys have rotated
                                    # as long as the double-ratchet state still matches.
                                    plaintext = engine.decrypt_message(cid, payload, ignore_sig=True)
                                    results.append({
                                        "messageId": mid,
                                        "ciphertext": payload.get("ciphertext"),
                                        "text": plaintext.decode()
                                    })
                        except Exception as e:
                            print(f"[DecryptBatch] Error for {mid}: {e}")
                            continue
                    
                    if results:
                        await ws.send_text(json.dumps({
                            "type": "decrypt_batch_response",
                            "results": results
                        }))

                elif msg_type == "ping":
                    await ws.send_text(json.dumps({"type": "pong"}))

            except WebSocketDisconnect:
                raise WebSocketDisconnect()
            except Exception as e:
                print(f"[WS] Internal error: {e}")

    except WebSocketDisconnect:
        print(f"[WS] Disconnected: {conversation_id}")
        if conversation_id in connections:
            if ws in connections[conversation_id]: connections[conversation_id].remove(ws)
            if not connections[conversation_id]: del connections[conversation_id]
    except Exception as e:
        print(f"[WS] Endpoint fatal error: {e}")
