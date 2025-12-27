from pydantic import BaseModel
from kyber_py.ml_kem import ML_KEM_768, ML_KEM_1024  # top of file

class ClientEncapsRequest(BaseModel):
    level: str                # "768" or "1024"
    server_public_key_hex: str

@app.post("/client-encaps")
def client_encaps(req: ClientEncapsRequest):
    ek = bytes.fromhex(req.server_public_key_hex)
    if req.level == "1024":
        shared, ct = ML_KEM_1024.encaps(ek)
    else:
        shared, ct = ML_KEM_768.encaps(ek)

    return {
        "ciphertext_hex": ct.hex(),
        "shared_secret_hex": shared.hex()  # optional, for debugging only
    }
