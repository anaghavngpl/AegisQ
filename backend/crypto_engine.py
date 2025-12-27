import os
from typing import Dict
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

from kyber_py.ml_kem import ML_KEM_768, ML_KEM_1024
from dilithium_py.dilithium import Dilithium3


class SignatureService:
    def __init__(self):
        self.pk, self.sk = Dilithium3.keygen()

    def sign(self, msg: bytes) -> bytes:
        return Dilithium3.sign(self.sk, msg)

    def verify(self, msg: bytes, sig: bytes) -> bool:
        return Dilithium3.verify(self.pk, msg, sig)


class KEMService:
    def __init__(self, level: str):
        self.level = level
        if level == "768":
            self.pk, self.sk = ML_KEM_768.keygen()
        else:
            self.pk, self.sk = ML_KEM_1024.keygen()

    def decapsulate(self, ct: bytes) -> bytes:
        if self.level == "768":
            return ML_KEM_768.decaps(self.sk, ct)
        return ML_KEM_1024.decaps(self.sk, ct)


class SymmetricRatchet:
    def __init__(self, root_key: bytes):
        self.chain_key = root_key
        self.counter = 0

    def _step(self):
        out = HKDF(
            algorithm=hashes.SHA256(),
            length=64,
            salt=None,
            info=b"aegisq-ratchet",
        ).derive(self.chain_key)
        self.chain_key = out[32:]
        return out[:32]

    def encrypt(self, plaintext: bytes):
        self.counter += 1
        key = self._step()
        nonce = os.urandom(12)
        ct = AESGCM(key).encrypt(nonce, plaintext, None)
        return self.counter, nonce, ct

    def decrypt(self, counter: int, nonce: bytes, ciphertext: bytes):
        if counter != self.counter + 1:
            raise ValueError("Out-of-order message")
        self.counter += 1
        key = self._step()
        return AESGCM(key).decrypt(nonce, ciphertext, None)


class AegisQEngine:
    def __init__(self):
        self.kem_768 = KEMService("768")
        self.kem_1024 = KEMService("1024")
        self.sessions: Dict[str, Dict] = {}

    def init_session(self, conversation_id: str, client_ct: bytes, escalate=False):
        level = "1024" if escalate else "768"
        kem = self.kem_1024 if level == "1024" else self.kem_768

        shared = kem.decapsulate(client_ct)
        root = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=None,
            info=b"aegisq-root",
        ).derive(shared)

        self.sessions[conversation_id] = {
            "ratchet": SymmetricRatchet(root),
            "sig": SignatureService(),
            "kem_level": level,
            "sent": 0,
        }

    def encrypt_message(self, conversation_id: str, plaintext: bytes) -> dict:
        s = self.sessions[conversation_id]
        s["sent"] += 1
        if s["sent"] >= 50 and s["kem_level"] == "768":
            s["kem_level"] = "1024"

        counter, nonce, ct = s["ratchet"].encrypt(plaintext)
        sig = s["sig"].sign(ct)

        return {
            "counter": counter,
            "nonce": nonce.hex(),
            "ciphertext": ct.hex(),
            "signature": sig.hex(),
            "kem_level": s["kem_level"],
        }

    def decrypt_message(self, conversation_id: str, payload: dict) -> bytes:
        s = self.sessions[conversation_id]
        ct = bytes.fromhex(payload["ciphertext"])
        sig = bytes.fromhex(payload["signature"])

        if not s["sig"].verify(ct, sig):
            raise ValueError("Invalid signature")

        return s["ratchet"].decrypt(
            payload["counter"],
            bytes.fromhex(payload["nonce"]),
            ct,
        )
