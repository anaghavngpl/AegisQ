from pydantic import BaseModel

class InitSessionRequest(BaseModel):
    conversation_id: str
    client_ct_hex: str
    escalate: bool = False

class EncryptRequest(BaseModel):
    conversation_id: str
    plaintext: str

class DecryptRequest(BaseModel):
    conversation_id: str
    nonce: str
    ciphertext: str
    signature: str
    counter: int
