from low_dilithium import LowDilithium

sig = LowDilithium()

msg = b"Hello AegisQ"
signature = sig.sign(msg)

print("Signature:", signature.hex())
print("Valid:", sig.verify(msg, signature))
