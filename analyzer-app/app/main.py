from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="Analyze API", version="1.0.0")


class AnalyzeRequest(BaseModel):
    text: str = Field(..., description="Text to analyze")


class AnalyzeResponse(BaseModel):
    original_text: str
    word_count: int
    character_count: int


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/analyze", response_model=AnalyzeResponse)
def analyze(payload: AnalyzeRequest):
    text = payload.text
    if text is None:
        raise HTTPException(status_code=400, detail="Missing 'text' field")

    # Words are separated by whitespace
    word_count = len(text.split())
    character_count = len(text)

    return AnalyzeResponse(
        original_text=text,
        word_count=word_count,
        character_count=character_count,
    )
