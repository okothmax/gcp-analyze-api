import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health_endpoint():
    """Test the health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_analyze_endpoint():
    """Test the analyze endpoint with valid input."""
    payload = {"text": "I love cloud engineering!"}
    response = client.post("/analyze", json=payload)
    assert response.status_code == 200
    
    data = response.json()
    assert data["original_text"] == "I love cloud engineering!"
    assert data["word_count"] == 4
    assert data["character_count"] == 25


def test_analyze_empty_text():
    """Test analyze endpoint with empty text."""
    payload = {"text": ""}
    response = client.post("/analyze", json=payload)
    assert response.status_code == 200
    
    data = response.json()
    assert data["original_text"] == ""
    assert data["word_count"] == 0
    assert data["character_count"] == 0


def test_analyze_spaces():
    """Test analyze endpoint with text containing spaces."""
    payload = {"text": "   hello   world   "}
    response = client.post("/analyze", json=payload)
    assert response.status_code == 200
    
    data = response.json()
    assert data["original_text"] == "   hello   world   "
    assert data["word_count"] == 2
    assert data["character_count"] == 19


def test_analyze_missing_text_field():
    """Test analyze endpoint with missing text field."""
    response = client.post("/analyze", json={})
    assert response.status_code == 422
    
    data = response.json()
    assert "detail" in data
    assert any("text" in str(error) for error in data["detail"])
