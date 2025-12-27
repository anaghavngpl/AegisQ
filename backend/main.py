import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

app = FastAPI(title="AegisQ – Stable Demo Backend")

# ------------------------
# In-memory master secrets
# ------------------------
sessions = {}


# ------------------------
# Models
# ------------------------
class HandshakeRequest(BaseModel):
    conversation_id: str


class EncryptRequest(BaseModel):
    conversation_id: str
    plaintext: str


class DecryptRequest(BaseModel):
    conversation_id: str
    ciphertext: str
    iv: str
    n: int


# ------------------------
# Key derivation
# ------------------------
def derive_message_key(master: bytes, n: int) -> bytes:
    return HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=b"aegisq-msg-" + n.to_bytes(4, "big"),
    ).derive(master)


# ------------------------
# Handshake
# ------------------------
@app.post("/handshake")
def handshake(req: HandshakeRequest):
    sessions[req.conversation_id] = os.urandom(32)
    return {"status": "handshake completed"}


# ------------------------
# Encrypt
# ------------------------
@app.post("/encrypt")
def encrypt(req: EncryptRequest):
    if req.conversation_id not in sessions:
        raise HTTPException(400, "Session not initialized")

    master = sessions[req.conversation_id]
    n = 1  # for demo; can increment if needed

    key = derive_message_key(master, n)
    aes = AESGCM(key)
    iv = os.urandom(12)
    ct = aes.encrypt(iv, req.plaintext.encode(), None)

    return {
        "ciphertext": ct.hex(),
        "iv": iv.hex(),
        "n": n,
    }


# ------------------------
# Decrypt
# ------------------------
@app.post("/decrypt")
def decrypt(req: DecryptRequest):
    if req.conversation_id not in sessions:
        raise HTTPException(400, "Session not initialized")

    master = sessions[req.conversation_id]
    key = derive_message_key(master, req.n)

    aes = AESGCM(key)
    pt = aes.decrypt(
        bytes.fromhex(req.iv),
        bytes.fromhex(req.ciphertext),
        None,
    )

    return {"plaintext": pt.decode()}
