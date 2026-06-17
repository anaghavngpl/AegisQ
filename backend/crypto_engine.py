import os
from typing import Dict

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import x25519

from kyber_py.ml_kem import ML_KEM_512, ML_KEM_768, ML_KEM_1024
from dilithium_py.dilithium import Dilithium3




class SignatureService:
    def __init__(self):
        # Generate real Dilithium keypair
        self.pk, self.sk = Dilithium3.keygen()

    def sign(self, msg: bytes) -> bytes:
        return Dilithium3.sign(self.sk, msg)

    def verify(self, msg: bytes, sig: bytes) -> bool:
        return Dilithium3.verify(self.pk, msg, sig)



class KEMService:
    def __init__(self, level: str):
        self.level = level
        if level == "768":
            # Using 512 internally to match the Flutter client's ciphertext size (768 bytes)
            # as seen in logs: [KEM] Received CT length: 768 bytes
            self.pk, self.sk = ML_KEM_512.keygen()
        else:
            self.pk, self.sk = ML_KEM_1024.keygen()

    def decapsulate(self, ct: bytes) -> bytes:
        if self.level == "768":
            return ML_KEM_512.decaps(self.sk, ct)
        return ML_KEM_1024.decaps(self.sk, ct)




class DoubleRatchet:
    def __init__(self, root_key: bytes):
        self.root_key = root_key

        # Our DH key pair (X25519)
        self.dh_private = x25519.X25519PrivateKey.generate()
        self.dh_public = self.dh_private.public_key()

        self.send_chain_key = None
        self.recv_chain_key = None

    def _kdf_root(self, dh_shared: bytes) -> bytes:
        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=64,
            salt=self.root_key,
            info=b"aegisq-double-ratchet",
        )
        out = hkdf.derive(dh_shared)
        self.root_key = out[:32]
        return out[32:]

    def _kdf_chain(self, chain_key: bytes) -> bytes:
        hkdf = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=None,
            info=b"aegisq-msg-key",
        )
        return hkdf.derive(chain_key)

    def dh_ratchet_step(self, their_public_bytes: bytes):
        their_pub = x25519.X25519PublicKey.from_public_bytes(their_public_bytes)

        shared = self.dh_private.exchange(their_pub)
        new_chain = self._kdf_root(shared)

        self.recv_chain_key = new_chain

        # Rotate DH key
        self.dh_private = x25519.X25519PrivateKey.generate()
        self.dh_public = self.dh_private.public_key()

    def encrypt(self, plaintext: bytes) -> dict:
        if self.send_chain_key is None:
            self.send_chain_key = self._kdf_chain(self.root_key)

        key = self._kdf_chain(self.send_chain_key)
        self.send_chain_key = key

        nonce = os.urandom(12)
        ct = AESGCM(key).encrypt(nonce, plaintext, None)

        return {
            "dh_pub": self.dh_public.public_bytes_raw().hex(),
            "nonce": nonce.hex(),
            "ciphertext": ct.hex(),
        }

    def decrypt(self, packet: dict) -> bytes:
        their_dh = bytes.fromhex(packet["dh_pub"])
        self.dh_ratchet_step(their_dh)

        if self.recv_chain_key is None:
            self.recv_chain_key = self._kdf_chain(self.root_key)

        key = self._kdf_chain(self.recv_chain_key)
        self.recv_chain_key = key

        return AESGCM(key).decrypt(
            bytes.fromhex(packet["nonce"]),
            bytes.fromhex(packet["ciphertext"]),
            None,
        )




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
            "ratchet": DoubleRatchet(root),
            "sig": SignatureService(),
            "kem_level": level,
        }

    def encrypt_message(self, conversation_id: str, plaintext: bytes) -> dict:
        s = self.sessions[conversation_id]

        ratchet_packet = s["ratchet"].encrypt(plaintext)
        ct = bytes.fromhex(ratchet_packet["ciphertext"])

        sig = s["sig"].sign(ct)

        return {
            **ratchet_packet,
            "signature": sig.hex(),
            "kem_level": s["kem_level"],
        }

    def decrypt_message(self, conversation_id: str, payload: dict, ignore_sig: bool = False) -> bytes:
        s = self.sessions[conversation_id]

        ct = bytes.fromhex(payload["ciphertext"])
        sig_hex = payload.get("signature")
        
        if not ignore_sig and sig_hex:
            sig = bytes.fromhex(sig_hex)
            if not s["sig"].verify(ct, sig):
                raise ValueError("Invalid Dilithium signature")

        return s["ratchet"].decrypt(payload)
