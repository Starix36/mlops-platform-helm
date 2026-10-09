from fastapi import FastAPI
import os

app = FastAPI()
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")

@app.get("/")
def read_root():
    return {"message": f"Hello from the {ENVIRONMENT} ML Model API!"}

@app.get("/predict")
def predict():
    # Simulated ML Prediction
    return {"prediction": [0.85, 0.15], "model_version": "v1.0"}
