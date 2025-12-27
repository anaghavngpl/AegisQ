import os
from cryptography.hazmat.primitives import hashes


class LowDilithium:
    """
    Reduced / educational Dilithium-like signature scheme.
    NOT real NIST Dilithium.
    Demonstrates PQ-signature workflow.
    """

    def __init__(self):
        # Simulated private/public keys
        self.private_key = os.urandom(64)
        self.public_key = hashes.Hash(hashes.SHA256())
        self.public_key.update(self.private_key)
        self.public_key = self.public_key.finalize()

    def sign(self, message: bytes) -> bytes:
        digest = hashes.Hash(hashes.SHA256())
        digest.update(self.private_key)
        digest.update(message)
        return digest.finalize()

    def verify(self, message: bytes, signature: bytes) -> bool:
        digest = hashes.Hash(hashes.SHA256())
        digest.update(self.private_key)
        digest.update(message)
        expected = digest.finalize()
        return expected == signature
